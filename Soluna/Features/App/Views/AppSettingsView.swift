//
//  AppSettingsView.swift
//  Soluna
//

import SwiftUI
import AppKit

/// `AppSettingsView` 的作用：统一的「设置」窗口内容（⌘, 打开），整合订阅与下载相关配置。
struct AppSettingsView: View {
    var body: some View {
        TabView {
            SubscriptionSettingsView()
                .tabItem { Label("订阅", systemImage: "bell") }
                .frame(width: 420, height: 320)

            DownloadSettingsSection()
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
                .frame(width: 420, height: 320)
        }
        .frame(minWidth: 440, minHeight: 340)
    }
}

/// `DownloadSettingsSection` 的作用：下载相关设置的汇总展示（yt-dlp 状态 + 说明）。
private struct DownloadSettingsSection: View {
    /// 中文注释：本地快速检测 yt-dlp 是否可用，与下载页检测逻辑一致。
    private var ytDlpInstalled: Bool {
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let search = Array(NSOrderedSet(array: envPaths + candidates)) as? [String] ?? candidates
        return search.contains { FileManager.default.isExecutableFile(atPath: "\($0)/yt-dlp") }
    }

    var body: some View {
        Form {
            Section("yt-dlp") {
                HStack {
                    Image(systemName: ytDlpInstalled ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(ytDlpInstalled ? .green : .red)
                    Text(ytDlpInstalled ? "已检测到 yt-dlp" : "未检测到 yt-dlp")
                    Spacer()
                }
                if !ytDlpInstalled {
                    Text("请先通过 Homebrew 安装：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("brew install yt-dlp")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Section("说明") {
                Text("画质、格式、编码、字幕、封面、元数据等下载选项，在「媒体下载」页面的顶部设置区进行调整。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
