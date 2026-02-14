//
//  SettingsView.swift
//  Soluna
//

import AppKit
import SwiftUI

/// 设置页面。
struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                downloadSection
                cookieSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("设置")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("下载设置")
                .font(.title3)
                .bold()
            Text("配置下载路径与 Cookie 选项。")
                .foregroundStyle(.secondary)
        }
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("下载目录")
                .font(.headline)
            HStack(spacing: 12) {
                TextField("下载目录", text: $settings.downloadDirectory)
                    .textFieldStyle(.roundedBorder)
                Button("选择目录") {
                    pickDirectory()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var cookieSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cookie 选项")
                .font(.headline)

            Picker("Cookie", selection: $settings.cookieMode) {
                ForEach(CookieMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if settings.cookieMode == .file {
                HStack(spacing: 12) {
                    TextField("Cookie 文件路径", text: $settings.cookieFilePath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择文件") {
                        pickFile()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if settings.cookieMode == .browser {
                Picker("浏览器", selection: $settings.browserType) {
                    ForEach(BrowserType.allCases) { browser in
                        Text(browser.title).tag(browser)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadDirectory = url.path
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            settings.cookieFilePath = url.path
        }
    }
}
