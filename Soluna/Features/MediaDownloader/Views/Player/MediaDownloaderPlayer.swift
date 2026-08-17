//
//  MediaDownloaderPlayer.swift
//  Soluna
//
//  中文注释：把播放器弹窗与删除确认所用的数据/视图类型从 MediaDownloaderWindow 拆分出来，
//  降低单文件体量。这些类型自包含、不依赖窗口的 @State，故以 internal 暴露给窗口主文件。

import SwiftUI
import AVKit
import AppKit

/// `MediaPlayTarget` 的作用：封装一次播放请求的目标标题与本地文件。
struct MediaPlayTarget: Identifiable {
    let id = UUID()
    let title: String
    let fileURL: URL
}

/// `MediaPlayerSheet` 的作用：使用系统 `AVPlayer` 在弹窗中播放下载完成的本地媒体，按视频真实比例自适应铺满、不变形。
struct MediaPlayerSheet: View {
    let target: MediaPlayTarget
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    /// 中文注释：视频真实宽高比（width/height），用于按容器自适应铺满、避免变形或大面积黑边。
    @State private var videoAspect: CGFloat?
    /// 中文注释：本机可用的第三方播放器（IINA/VLC/Elmedia），用于「用外部播放器打开」。
    @State private var externalPlayerURL: URL?

    /// 中文注释：根据播放目标初始化播放器实例。
    init(target: MediaPlayTarget) {
        self.target = target
        _player = State(initialValue: AVPlayer(url: target.fileURL))
    }

    /// 中文注释：构建本地媒体播放弹窗布局。
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 中文注释：标题栏——标题、文件信息、外部打开 / Finder / 关闭。
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(target.fileURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let ext = externalPlayerURL {
                    Button {
                        NSWorkspace.shared.open([target.fileURL], withApplicationAt: ext, configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        Label("用\(ExternalPlayerLocator.displayName(ext))打开", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([target.fileURL])
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
            }
            .padding(14)

            Divider()

            // 中文注释：播放舞台——纯黑背景，视频按真实比例居中铺满，无变形、极小黑边。
            GeometryReader { geo in
                Color.black
                    .overlay(alignment: .center) {
                        VideoPlayer(player: player)
                            .frame(width: fittedSize(in: geo.size).width,
                                   height: fittedSize(in: geo.size).height)
                    }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            loadVideoAspect()
            externalPlayerURL = ExternalPlayerLocator.find()
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }

    /// 中文注释：根据容器尺寸与视频真实比例，算出既不超出也不变形的铺满尺寸。
    private func fittedSize(in size: CGSize) -> CGSize {
        let aspect = videoAspect ?? (16.0 / 9.0)
        let boxH = min(size.height, size.width / aspect)
        let boxW = boxH * aspect
        return CGSize(width: max(0, boxW), height: max(0, boxH))
    }

    /// 中文注释：从 AVAsset 读取视频轨真实尺寸（含旋转变换），算出宽高比。
    private func loadVideoAspect() {
        let asset = AVURLAsset(url: target.fileURL)
        Task {
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            let natural = try? await track.load(.naturalSize)
            let transform = try? await track.load(.preferredTransform)
            await MainActor.run {
                if let natural, let transform {
                    let rect = natural.applying(transform)
                    let w = abs(rect.width), h = abs(rect.height)
                    if h > 0 { videoAspect = w / h }
                } else if let natural, natural.height > 0 {
                    videoAspect = natural.width / natural.height
                }
            }
        }
    }
}

/// `MediaDeleteTarget` 的作用：封装待删除的任务与文件信息。
struct MediaDeleteTarget: Identifiable {
    let id: UUID
    let fileURL: URL?
    let isInferred: Bool
}

/// `MediaHistoryDeleteTarget` 的作用：封装历史记录删除文件时的确认数据。
struct MediaHistoryDeleteTarget: Identifiable {
    let id: UUID
    let fileURL: URL?
}
