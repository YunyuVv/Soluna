//
//  DownloadPanelView.swift
//  Soluna
//

import SwiftUI

/// 右侧下载页面（单个下载）。
struct DownloadPanelView: View {
    @Bindable var model: DownloadViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                inputSection
                actionSection
                logSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("下载")
    }

    private var headerSection: some View {
        HStack {
            Text("YouTube")
                .font(.title3)
                .bold()
            Spacer()
            Button {
                // 预留主题/皮肤按钮。
            } label: {
                Image(systemName: "paintpalette")
            }
            .buttonStyle(.plain)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("单个下载")
                .font(.headline)

            TextField("在此粘贴 YouTube 链接…", text: $model.url)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            Button {
                model.startDownload()
            } label: {
                Label(model.isDownloading ? "下载中…" : "开始下载", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isDownloading)

            Button("取消") {
                model.cancelDownload()
            }
            .buttonStyle(.bordered)
            .disabled(!model.isDownloading)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.status)
                    .foregroundStyle(.secondary)
                if !model.ytDlpPath.isEmpty {
                    Text(model.ytDlpPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("yt-dlp 输出")
                .font(.headline)
            ScrollView {
                Text(model.log.isEmpty ? "暂无日志" : model.log)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180)
            .padding(12)
            .background(Color.gray.opacity(0.08))
            .clipShape(.rect(cornerRadius: 12))
        }
    }
}
