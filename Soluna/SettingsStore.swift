//
//  SettingsStore.swift
//  Soluna
//

import Foundation
import Observation

/// Cookie 选项。
enum CookieMode: String, CaseIterable, Identifiable {
    case none
    case file
    case browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不使用"
        case .file: return "Cookie 文件"
        case .browser: return "浏览器"
        }
    }
}

/// 支持的浏览器。
enum BrowserType: String, CaseIterable, Identifiable {
    case chrome
    case safari
    case firefox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chrome: return "Chrome"
        case .safari: return "Safari"
        case .firefox: return "Firefox"
        }
    }

    var ytDlpValue: String {
        switch self {
        case .chrome: return "chrome"
        case .safari: return "safari"
        case .firefox: return "firefox"
        }
    }
}

/// 应用设置。
@MainActor
@Observable
final class SettingsStore {
    // 默认下载目录。
    var downloadDirectory: String = "/Users/wangpenglong/Downloads"
    // Cookie 选择模式。
    var cookieMode: CookieMode = .browser
    // Cookie 文件路径（当 cookieMode = .file）。
    var cookieFilePath: String = ""
    // 浏览器类型（当 cookieMode = .browser）。
    var browserType: BrowserType = .chrome
    // JS runtime 路径（用于挑战解密）。
    var jsRuntimePath: String = ""
    // JS runtime 状态提示。
    var jsRuntimeStatus: String = "未检测"
    // ffmpeg 路径。
    var ffmpegPath: String = ""
    // ffmpeg 状态提示。
    var ffmpegStatus: String = "未检测"

    private let logStore: LogStore

    init(logStore: LogStore) {
        self.logStore = logStore
        autoDetectRuntime()
        autoDetectFFmpeg()
    }

    /// 自动检测 JS runtime（node / bun）。
    func autoDetectRuntime() {
        let candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/opt/homebrew/bin/bun", "/usr/local/bin/bun"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            jsRuntimePath = path
            jsRuntimeStatus = "已检测到：\(path)"
            logStore.append("JS Runtime 自动检测成功：\(path)", channel: .system)
            return
        }

        if let resolved = resolveFromShell() {
            jsRuntimePath = resolved
            jsRuntimeStatus = "已检测到：\(resolved)"
            logStore.append("JS Runtime shell 检测成功：\(resolved)", channel: .system)
            return
        }

        jsRuntimeStatus = "未检测到，请安装 Node 或 Bun"
        logStore.append("JS Runtime 未检测到", channel: .system)
    }

    /// 自动检测 ffmpeg。
    func autoDetectFFmpeg() {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            ffmpegPath = path
            ffmpegStatus = "已检测到：\(path)"
            logStore.append("ffmpeg 自动检测成功：\(path)", channel: .system)
            return
        }

        if let resolved = resolveFFmpegFromShell() {
            ffmpegPath = resolved
            ffmpegStatus = "已检测到：\(resolved)"
            logStore.append("ffmpeg shell 检测成功：\(resolved)", channel: .system)
            return
        }

        ffmpegStatus = "未检测到，请安装 ffmpeg"
        logStore.append("ffmpeg 未检测到", channel: .system)
    }

    /// 测试 ffmpeg 是否可用。
    func testFFmpeg() {
        guard !ffmpegPath.isEmpty else {
            ffmpegStatus = "未设置路径"
            logStore.append("ffmpeg 测试失败：未设置路径", channel: .system)
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpegPath)
        task.arguments = ["-version"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            ffmpegStatus = "测试失败：\(error.localizedDescription)"
            logStore.append("ffmpeg 测试失败：\(error.localizedDescription)", channel: .system)
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if task.terminationStatus == 0 {
            let firstLine = output.split(separator: "\n").first.map(String.init) ?? "可用"
            ffmpegStatus = "可用：\(firstLine)"
            logStore.append("ffmpeg 测试成功：\(ffmpegStatus)", channel: .system)
        } else {
            ffmpegStatus = "测试失败：退出码 \(task.terminationStatus)"
            logStore.append("ffmpeg 测试失败：退出码 \(task.terminationStatus)", channel: .system)
        }
    }

    /// 测试 runtime 是否可用。
    func testRuntime() {
        guard !jsRuntimePath.isEmpty else {
            jsRuntimeStatus = "未设置路径"
            logStore.append("JS Runtime 测试失败：未设置路径", channel: .system)
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: jsRuntimePath)
        task.arguments = ["-v"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            jsRuntimeStatus = "测试失败：\(error.localizedDescription)"
            logStore.append("JS Runtime 测试失败：\(error.localizedDescription)", channel: .system)
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if task.terminationStatus == 0 {
            jsRuntimeStatus = output.isEmpty ? "可用" : "可用：\(output)"
            logStore.append("JS Runtime 测试成功：\(jsRuntimeStatus)", channel: .system)
        } else {
            jsRuntimeStatus = "测试失败：退出码 \(task.terminationStatus)"
            logStore.append("JS Runtime 测试失败：退出码 \(task.terminationStatus)", channel: .system)
        }
    }

    private func resolveFromShell() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [
            "-lc",
            "source ~/.zshrc >/dev/null 2>&1; which -a node | head -n 1 || which -a bun | head -n 1"
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }

    private func resolveFFmpegFromShell() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [
            "-lc",
            "source ~/.zshrc >/dev/null 2>&1; which -a ffmpeg | head -n 1"
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }
}
