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
    // 是否正在下载（队列处理中）。
    var isDownloading: Bool = false
    // 检测到的 yt-dlp 路径。
    var ytDlpPath: String = ""

    // 下载任务列表（按入队顺序）。
    var tasks: [DownloadTask] = []
    // 当前任务 ID。
    var currentTaskID: UUID?
    // 是否展示日志详情弹窗。
    var showTaskLog: Bool = false
    // 当前查看的任务 ID。
    var selectedTaskID: UUID?

    // 选段开始时间（MM:SS 或 HH:MM:SS）。
    var clipStart: String = ""
    // 选段结束时间（MM:SS 或 HH:MM:SS）。
    var clipEnd: String = ""
    // 自定义文件名（不含扩展名，可选）。
    var outputName: String = ""

    let logStore: LogStore
    let settings: SettingsStore

    // 内部持有的进程实例，方便取消。
    private var process: Process?
    // 等待队列（存任务 ID）。
    private var queue: [UUID] = []
    // 缓存的 yt-dlp 路径。
    private var cachedYtDlpPath: String?

    init(logStore: LogStore, settings: SettingsStore) {
        self.logStore = logStore
        self.settings = settings
        warmupYtDlpPath()
    }

    /// 入队下载（UI 立即响应）。
    func startDownload() {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "请输入链接"
            logStore.append("下载中止：链接为空", channel: .system)
            return
        }

        let newTask = DownloadTask(
            id: UUID(),
            url: url,
            title: outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url : outputName,
            status: "排队中",
            log: "",
            progress: 0,
            thumbnailURL: "",
            isThumbnailLoading: true,
            clipStart: clipStart,
            clipEnd: clipEnd,
            outputName: outputName
        )

        tasks.insert(newTask, at: 0)
        queue.append(newTask.id)
        logStore.append("任务入队：\(newTask.title)", channel: .system)

        // 异步获取缩略图（后台执行，避免阻塞主线程）。
        if let request = makeThumbnailRequest(url: newTask.url) {
            Task.detached { [weak self] in
                let output = DownloadViewModel.fetchThumbnail(request: request)
                await MainActor.run {
                    guard let self else { return }
                    if let index = self.tasks.firstIndex(where: { $0.id == newTask.id }) {
                        self.tasks[index].thumbnailURL = output ?? ""
                        self.tasks[index].isThumbnailLoading = false
                    }
                }
            }
        }

        // 启动队列处理（异步，不阻塞 UI）。
        Task.detached { [weak self] in
            await self?.startNextIfIdleAsync()
        }
    }

    /// 取消当前下载。
    func cancelDownload() {
        guard let process else { return }
        process.terminate()
        status = "已取消"
        isDownloading = false
        logStore.append("下载已取消", channel: .system)
        if let id = currentTaskID {
            updateTaskStatus(id: id, status: "已取消")
        }
        self.process = nil
        Task.detached { [weak self] in
            await self?.startNextIfIdleAsync()
        }
    }

    /// 暂停当前下载。
    func pauseDownload() {
        guard let process, !isPaused else { return }
        if process.suspend() {
            isPaused = true
            status = "已暂停"
            logStore.append("下载已暂停", channel: .system)
            if let id = currentTaskID {
                updateTaskStatus(id: id, status: "已暂停")
            }
        }
    }

    /// 继续当前下载。
    func resumeDownload() {
        guard let process, isPaused else { return }
        if process.resume() {
            isPaused = false
            status = "下载中…"
            logStore.append("下载已继续", channel: .system)
            if let id = currentTaskID {
                updateTaskStatus(id: id, status: "下载中…")
            }
        }
    }

    // 是否暂停当前下载。
    var isPaused: Bool = false

    func pauseTask(id: UUID) {
        guard id == currentTaskID else { return }
        pauseDownload()
    }

    func resumeTask(id: UUID) {
        guard id == currentTaskID else { return }
        resumeDownload()
    }

    func cancelTask(id: UUID) {
        if id == currentTaskID {
            cancelDownload()
            return
        }
        if let index = queue.firstIndex(of: id) {
            queue.remove(at: index)
        }
        if let taskIndex = tasks.firstIndex(where: { $0.id == id }) {
            tasks[taskIndex].status = "已取消"
        }
    }

    func removeTask(id: UUID) {
        guard id != currentTaskID else { return }
        if let index = queue.firstIndex(of: id) {
            queue.remove(at: index)
        }
        tasks.removeAll { $0.id == id }
    }

    /// 预热 yt-dlp 路径（后台缓存）。
    private func warmupYtDlpPath() {
        Task.detached { [weak self] in
            let path = DownloadViewModel.resolveSystemYtDlpSync()?.path
            await MainActor.run {
                if let path { self?.cachedYtDlpPath = path }
            }
        }
    }

    /// 异步启动队列中的下一个任务。
    private func startNextIfIdleAsync() async {
        await MainActor.run {
            guard process == nil else { return }
        }

        let nextID: UUID? = await MainActor.run {
            guard !queue.isEmpty else {
                isDownloading = false
                status = "就绪"
                return nil
            }
            let id = queue.removeFirst()
            currentTaskID = id
            isDownloading = true
            return id
        }

        guard let nextID else { return }

        let taskIndex = await MainActor.run { tasks.firstIndex(where: { $0.id == nextID }) }
        guard let taskIndex else {
            await MainActor.run {
                process = nil
            }
            await startNextIfIdleAsync()
            return
        }

        let taskData = await MainActor.run { tasks[taskIndex] }

        await MainActor.run {
            status = "下载中…"
            updateTaskStatus(id: nextID, status: "下载中…")
            logStore.append("开始任务：\(taskData.title)", channel: .system)
        }

        // 获取 yt-dlp 路径（优先缓存）。
        let executablePath = await MainActor.run { cachedYtDlpPath } ?? DownloadViewModel.resolveSystemYtDlpSync()?.path

        guard let executablePath else {
            await MainActor.run {
                status = "未找到系统 yt-dlp，请先安装"
                logStore.append("未找到 yt-dlp：command -v 失败", channel: .system)
                updateTaskStatus(id: nextID, status: "失败")
            }
            await startNextIfIdleAsync()
            return
        }

        await MainActor.run {
            ytDlpPath = executablePath
            cachedYtDlpPath = executablePath
            logStore.append("使用 yt-dlp 路径：\(ytDlpPath)", channel: .system)
            logStore.append("下载目录：\(settings.downloadDirectory)", channel: .system)
            logStore.append("使用格式：默认最优（不指定 -f）", channel: .system)
            if !taskData.clipStart.isEmpty || !taskData.clipEnd.isEmpty {
                let normalizedStart = normalizeTime(taskData.clipStart) ?? taskData.clipStart
                let normalizedEnd = normalizeTime(taskData.clipEnd) ?? taskData.clipEnd
                logStore.append("选段下载：\(normalizedStart) - \(normalizedEnd)", channel: .system)
            }
            if taskData.outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logStore.append("文件名：使用原始名称", channel: .system)
            } else {
                logStore.append("文件名：\(taskData.outputName)", channel: .system)
            }
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
            if settings.ffmpegPath.isEmpty {
                logStore.append("ffmpeg：未设置", channel: .system)
            } else {
                logStore.append("ffmpeg：\(settings.ffmpegPath)", channel: .system)
            }
        }

        let pipe = Pipe()
        let task = Process()
        let args = buildArguments(for: taskData)
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = args
        task.environment = buildEnvironment()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.process = nil
                self?.isDownloading = false
                self?.isPaused = false
                let succeeded = proc.terminationStatus == 0
                self?.updateTaskStatus(id: nextID, status: succeeded ? "下载完成" : "下载失败")
                if succeeded {
                    self?.updateTaskProgress(id: nextID, progress: 1)
                }
                self?.logStore.append("任务结束：\(taskData.title) 退出码：\(proc.terminationStatus)", channel: .system)
            }
            Task { await self?.startNextIfIdleAsync() }
        }

        await MainActor.run {
            process = task
        }

        do {
            try task.run()
            await MainActor.run {
                logStore.append("执行命令：\(buildCommandString(executableURL: URL(fileURLWithPath: executablePath), arguments: args))", channel: .system)
                logStore.append("yt-dlp 进程启动成功", channel: .system)
            }
            readOutput(from: pipe.fileHandleForReading, taskID: nextID)
        } catch {
            await MainActor.run {
                process = nil
                updateTaskStatus(id: nextID, status: "启动失败")
                logStore.append("yt-dlp 启动失败：\(error.localizedDescription)", channel: .system)
            }
            await startNextIfIdleAsync()
        }
    }

    /// 读取 ytdlp 输出日志。
    private func readOutput(from handle: FileHandle, taskID: UUID) {
        Task.detached { [weak self] in
            for try await line in handle.bytes.lines {
                await MainActor.run {
                    self?.appendLog(line, taskID: taskID)
                }
            }
        }
    }

    /// 追加日志文本。
    private func appendLog(_ line: String, taskID: UUID) {
        appendTaskLog(line, taskID: taskID)
        if let percent = parseProgress(line) {
            updateTaskProgress(id: taskID, progress: percent)
        }
    }

    private func buildArguments(for task: DownloadTask) -> [String] {
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

        if !settings.ffmpegPath.isEmpty {
            args.append(contentsOf: ["--ffmpeg-location", settings.ffmpegPath])
        }

        if let template = buildOutputTemplate(task.outputName) {
            args.append(contentsOf: ["-o", template])
        }

        if let section = buildDownloadSection(task.clipStart, task.clipEnd) {
            args.append(contentsOf: ["--download-sections", section])
        }

        args.append(task.url)
        return args
    }

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var extraPaths: [String] = []

        if !settings.jsRuntimePath.isEmpty {
            let runtimeDir = (settings.jsRuntimePath as NSString).deletingLastPathComponent
            extraPaths.append(runtimeDir)
        }
        if !settings.ffmpegPath.isEmpty {
            let ffmpegDir = (settings.ffmpegPath as NSString).deletingLastPathComponent
            extraPaths.append(ffmpegDir)
        }
        if !extraPaths.isEmpty {
            let existingPath = env["PATH"] ?? ""
            env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        }
        return env
    }

    private func resolveRuntimeName() -> String? {
        guard !settings.jsRuntimePath.isEmpty else { return nil }
        let name = URL(fileURLWithPath: settings.jsRuntimePath).lastPathComponent.lowercased()
        let supported = ["node", "bun", "deno", "quickjs"]
        return supported.contains(name) ? name : nil
    }

    private func buildOutputTemplate(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let safeName = trimmed.replacingOccurrences(of: "/", with: "_")
        return "\(settings.downloadDirectory)/\(safeName).%(ext)s"
    }

    private func buildDownloadSection(_ startInput: String, _ endInput: String) -> String? {
        let start = normalizeTime(startInput)
        let end = normalizeTime(endInput)

        if start == nil && end == nil { return nil }

        let startValue = start ?? "00:00:00"
        let endValue = end ?? ""
        if endValue.isEmpty {
            return "*\(startValue)-"
        }
        return "*\(startValue)-\(endValue)"
    }

    private func normalizeTime(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let parts = trimmed.split(separator: ":").map(String.init)
        if parts.count == 2 {
            let m = parts[0].paddingLeft(to: 2)
            let s = parts[1].paddingLeft(to: 2)
            return "00:\(m):\(s)"
        }
        if parts.count == 3 {
            let h = parts[0].paddingLeft(to: 2)
            let m = parts[1].paddingLeft(to: 2)
            let s = parts[2].paddingLeft(to: 2)
            return "\(h):\(m):\(s)"
        }
        return nil
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

    nonisolated private static func resolveSystemYtDlpSync() -> URL? {
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

    private func parseProgress(_ line: String) -> Double? {
        let pattern = "(\\d+(?:\\.\\d+)?)%"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        guard let percentRange = Range(match.range(at: 1), in: line) else { return nil }
        let value = Double(line[percentRange]) ?? 0
        return min(max(value / 100.0, 0), 1)
    }

    private func updateTaskStatus(id: UUID, status: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
    }

    private func updateTaskProgress(id: UUID, progress: Double) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].progress = progress
    }

    private func appendTaskLog(_ line: String, taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if tasks[index].log.isEmpty {
            tasks[index].log = line
        } else {
            tasks[index].log.append("\n\(line)")
        }
    }

    private func makeThumbnailRequest(url: String) -> ThumbnailRequest? {
        ThumbnailRequest(
            url: url,
            cookieMode: settings.cookieMode,
            cookieFilePath: settings.cookieFilePath,
            browserType: settings.browserType,
            runtimeName: resolveRuntimeName(),
            environment: buildEnvironment()
        )
    }

    nonisolated private static func fetchThumbnail(request: ThumbnailRequest) -> String? {
        guard let executableURL = resolveSystemYtDlpSync() else { return nil }

        let task = Process()
        task.executableURL = executableURL
        task.arguments = buildThumbnailArgumentsStatic(request: request)
        task.environment = request.environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }

    nonisolated private static func buildThumbnailArgumentsStatic(request: ThumbnailRequest) -> [String] {
        var args: [String] = ["--get-thumbnail"]

        switch request.cookieMode {
        case .none:
            break
        case .file:
            if !request.cookieFilePath.isEmpty {
                args.append(contentsOf: ["--cookies", request.cookieFilePath])
            }
        case .browser:
            args.append(contentsOf: ["--cookies-from-browser", request.browserType.ytDlpValue])
        }

        if let runtime = request.runtimeName {
            args.append(contentsOf: ["--js-runtime", runtime])
        }

        args.append(request.url)
        return args
    }
}

/// 下载任务条目。
struct DownloadTask: Identifiable, Hashable {
    let id: UUID
    let url: String
    let title: String
    var status: String
    var log: String
    var progress: Double
    var thumbnailURL: String
    var isThumbnailLoading: Bool
    let clipStart: String
    let clipEnd: String
    let outputName: String
}

struct ThumbnailRequest {
    let url: String
    let cookieMode: CookieMode
    let cookieFilePath: String
    let browserType: BrowserType
    let runtimeName: String?
    let environment: [String: String]
}

private extension String {
    func paddingLeft(to length: Int) -> String {
        if count >= length { return self }
        return String(repeating: "0", count: length - count) + self
    }
}
