//
//  MediaDownloaderWindow+Actions.swift
//  Soluna
//
//  中文注释：把 MediaDownloaderWindow 中与播放 / 历史 / 播放列表相关的动作处理逻辑拆分到扩展，
//  降低单文件体量（原窗口文件超过 1900 行），保持主文件聚焦布局。

import SwiftUI
import AppKit

extension MediaDownloaderWindow {
    /// 中文注释：处理历史记录卡片的操作行为。
    func handleHistoryAction(_ action: MediaHistoryAction, record: MediaDownloadHistorySnapshot, viewModel: MediaDownloaderViewModel) {
        switch action {
        case .openFolder:
            viewModel.openFolder(for: record)
        case .playFile:
            handlePlay(fileURL: viewModel.playableFileURL(for: record), title: record.displayTitle)
        case .openSourceURL:
            viewModel.openSourceURL(for: record)
        case .copySourceURL:
            viewModel.copySourceURL(for: record)
        case .downloadThumbnail:
            viewModel.downloadCover(for: record)
        case .retryDownload:
            viewModel.enqueueHistoryRecord(record)
            selectedSection = .download
        case .deleteRecord:
            viewModel.deleteHistoryRecord(record.id)
        case .deleteRecordAndFile:
            historyDeleteTarget = MediaHistoryDeleteTarget(id: record.id, fileURL: record.outputFileURL)
        }
    }

    /// 中文注释：统一处理「播放」动作。
    /// 原生格式（mp4/mov/...）在应用内用 AVPlayer 播放；WebM 等 AVFoundation 不支持的格式，
    /// 优先调用本机已装的 IINA/VLC 直接打开，否则提示安装播放器。
    func handlePlay(fileURL: URL?, title: String) {
        guard let fileURL else { return }
        switch viewModel.playbackRoute(for: fileURL) {
        case .inApp(let url):
            mediaPlayTarget = MediaPlayTarget(title: title, fileURL: url)
        case .external(let appURL, let url):
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            viewModel.publishStatus("已使用 \(ExternalPlayerLocator.displayName(appURL)) 打开播放", isError: false)
        case .unsupported:
            viewModel.publishStatus("当前格式无法播放，请安装 IINA 或 VLC 后再试", isError: true)
        }
    }

    /// 中文注释：调用 yt-dlp 解析播放列表链接，解析成功后弹出「选择下载条目」弹窗。
    @MainActor
    func resolvePlaylist() {
        let url = viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.isEmpty == false else {
            viewModel.publishStatus("请先粘贴播放列表链接", isError: true)
            return
        }
        guard viewModel.isYtDlpAvailable, let ytPath = viewModel.ytDlpPath else {
            viewModel.publishStatus("未检测到 yt-dlp，无法解析播放列表（请先 brew install yt-dlp）", isError: true)
            return
        }
        let useCookies = viewModel.useBrowserCookies
        let cookieSource = viewModel.browserCookieSource
        isResolvingPlaylist = true
        // 中文注释：yt-dlp 解析是同步阻塞的进程调用，放到后台线程执行避免界面卡顿。
        Task.detached(priority: .userInitiated) {
            let service = MediaPlaylistResolverService()
            let resolved = service.resolve(
                urlText: url,
                executablePath: ytPath,
                useBrowserCookies: useCookies,
                browserCookieSource: cookieSource
            )
            await MainActor.run {
                isResolvingPlaylist = false
                if let resolved {
                    playlistTarget = resolved
                } else {
                    viewModel.publishStatus("解析播放列表失败：可能不是列表链接，或需要 Cookies", isError: true)
                }
            }
        }
    }

    /// 中文注释：统一处理“添加并开始下载”的动作。
    func addAndStart(viewModel: MediaDownloaderViewModel) {
        viewModel.addTasksFromInput()
        viewModel.startQueue()
    }

    /// 中文注释：复制指定链接到剪贴板。
    func copyURL(_ url: String) {
        copyText(url)
    }

    /// 中文注释：复制文本到剪贴板。
    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 中文注释：打开指定链接。
    func openURL(_ url: String) {
        guard let link = URL(string: url) else { return }
        NSWorkspace.shared.open(link)
    }

    /// 中文注释：弹出系统面板选择输出目录。
    func chooseOutputFolder(viewModel: MediaDownloaderViewModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"

        if panel.runModal() == .OK {
            viewModel.updateOutputFolder(panel.url)
        }
    }

    /// 中文注释：渲染 yt-dlp 可用性展示行。
    @ViewBuilder
    func statusBanner(viewModel: MediaDownloaderViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isYtDlpAvailable ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(viewModel.isYtDlpAvailable ? .green : .red)
                Text(viewModel.isYtDlpAvailable ? "已检测到 yt-dlp" : "未检测到 yt-dlp")
                    .font(.headline)
                Spacer()
                Button("重新检测") {
                    viewModel.refreshYtDlpStatus()
                }
                .buttonStyle(.bordered)
            }

            if let path = viewModel.ytDlpPath {
                Text(path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("请使用 brew install yt-dlp 安装")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
    }
}
