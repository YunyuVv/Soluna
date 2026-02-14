//
//  DownloadViewModel.swift
//  Soluna
//

import AppKit
import Observation

/// 负责执行 ytdlp 下载的状态模型。
@MainActor
@Observable
final class DownloadViewModel {
    // 用户输入的 URL。
    var url: String = ""
    // 当前状态提示文本。
    var status: String = "就绪"
    // 是否正在下载。
    var isDownloading: Bool = false
    // 终端输出日志。
    var log: String = ""
    // 检测到的 yt-dlp 路径。
    var ytDlpPath: String = ""

    let logStore: LogStore
    let settings: SettingsStore

    // 内部持有的进程实例，方便取消。
    private var process: Process?

    init(logStore: LogStore, settings: SettingsStore) {
        self.logStore = logStore
        self.settings = settings
    }

    /// 开始下载。
    func startDownload() {
        guard !isDownloading else { return }
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "请输入链接"
            logStore.append("下载中止：链接为空", channel: .system)
            return
        }

        log = ""
        status = "检查 yt-dlp…"
        logStore.append("开始检查系统 yt-dlp", channel: .system)

        guard let executableURL = resolveSystemYtDlp() else {
            status = "未找到系统 yt-dlp，请先安装"
            logStore.append("未找到 yt-dlp：command -v 失败", channel: .system)
            return
        }

        ytDlpPath = executableURL.path
        status = "准备下载"
        logStore.append("使用 yt-dlp 路径：\(ytDlpPath)", channel: .system)
        logStore.append("下载目录：\(settings.downloadDirectory)", channel: .system)
        logStore.append("使用格式：默认最优（不指定 -f）", channel: .system)
        logStore.append("Cookie 模式：\(settings.cookieMode.title)", channel: .system)
        if settings.cookieMode == .file {
            logStore.append("Cookie 文件：\(settings.cookieFilePath.isEmpty ? "未设置" : settings.cookieFilePath)", channel: .system)
        }
        if settings.cookieMode == .browser {
            logStore.append("浏览器：\(settings.browserType.title)", channel: .system)
        }
        if settings.jsRuntimePath.isEmpty {
            logStore.append("JS Runtime：未设置", channel: .system)
        } else {
            logStore.append("JS Runtime：\(settings.jsRuntimePath)", channel: .system)
        }

        isDownloading = true

        let pipe = Pipe()
        let task = Process()
        task.executableURL = executableURL
        let args = buildArguments()
        task.arguments = args
        task.environment = buildEnvironment()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.isDownloading = false
                self?.status = proc.terminationStatus == 0 ? "下载完成" : "下载失败"
                self?.logStore.append("下载结束，退出码：\(proc.terminationStatus)", channel: .system)
                self?.process = nil
            }
        }

        process = task

        do {
            try task.run()
            status = "下载中…"
            logStore.append("执行命令：\(buildCommandString(executableURL: executableURL, arguments: args))", channel: .system)
            logStore.append("yt-dlp 进程启动成功", channel: .system)
            readOutput(from: pipe.fileHandleForReading)
        } catch {
            isDownloading = false
            status = "启动失败：\(error.localizedDescription)"
            logStore.append("yt-dlp 启动失败：\(error.localizedDescription)", channel: .system)
            process = nil
        }
    }

    /// 取消下载。
    func cancelDownload() {
        guard let process else { return }
        process.terminate()
        status = "已取消"
        isDownloading = false
        logStore.append("下载已取消", channel: .system)
        self.process = nil
    }

    /// 读取 ytdlp 输出日志。
    private func readOutput(from handle: FileHandle) {
        Task.detached { [weak self] in
            for try await line in handle.bytes.lines {
                await MainActor.run {
                    self?.appendLog(line)
                }
            }
        }
    }

    /// 追加日志文本。
    private func appendLog(_ line: String) {
        if log.isEmpty {
            log = line
        } else {
            log.append("\n\(line)")
        }
    }

    private func buildArguments() -> [String] {
        var args: [String] = ["-P", settings.downloadDirectory]

        switch settings.cookieMode {
        case .none:
            break
        case .file:
            if !settings.cookieFilePath.isEmpty {
                args.append(contentsOf: ["--cookies", settings.cookieFilePath])
            }
        case .browser:
            args.append(contentsOf: ["--cookies-from-browser", settings.browserType.ytDlpValue])
        }

        if let runtime = resolveRuntimeName() {
            args.append(contentsOf: ["--js-runtime", runtime])
        }

        args.append(url)
        return args
    }

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        guard !settings.jsRuntimePath.isEmpty else { return env }

        let runtimeDir = (settings.jsRuntimePath as NSString).deletingLastPathComponent
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = "\(runtimeDir):\(existingPath)"
        return env
    }

    private func resolveRuntimeName() -> String? {
        guard !settings.jsRuntimePath.isEmpty else { return nil }
        let name = URL(fileURLWithPath: settings.jsRuntimePath).lastPathComponent.lowercased()
        let supported = ["node", "bun", "deno", "quickjs"]
        return supported.contains(name) ? name : nil
    }

    private func buildCommandString(executableURL: URL, arguments: [String]) -> String {
        let escaped = arguments.map { argument in
            if argument.contains(" ") {
                return "\"\(argument)\""
            }
            return argument
        }
        return ([executableURL.path] + escaped).joined(separator: " ")
    }

    /// 使用系统 PATH 查找 yt-dlp。
    private func resolveSystemYtDlp() -> URL? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", "command -v yt-dlp"]

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
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: output)
    }

}
