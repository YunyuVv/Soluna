//
//  ExecutableLocator.swift
//  Soluna
//
//  中文注释：集中管理可执行文件搜索、版本探测、外部播放器定位、站点标识推断，
//  消除各模块中重复实现（下载器 / 订阅解析器 / 历史存储 / 播放列表解析器）。

import Foundation

/// `ExecutableLocator` 的作用：探测本机命令行工具（yt-dlp / ffmpeg 等）的路径与版本。
enum ExecutableLocator {
    /// 中文注释：GUI 进程不继承 shell 的 PATH，必须显式列出常见安装目录。
    static let defaultSearchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        "/usr/bin"
    ]

    /// 中文注释：合并进程环境变量 PATH 与默认路径，去重后返回完整搜索顺序。
    static func searchPaths() -> [String] {
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }
        return Array(NSOrderedSet(array: envPaths + defaultSearchPaths)) as? [String] ?? defaultSearchPaths
    }

    /// 中文注释：在常见路径中查找指定可执行文件，找到返回绝对路径，否则 nil。
    static func find(named name: String) -> String? {
        for path in searchPaths().map({ "\($0)/\(name)" }) {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// 中文注释：执行 `--version` 探测指定可执行文件的版本号，失败返回 nil。
    static func version(of path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }
}

/// `ExternalPlayerLocator` 的作用：定位本机已安装的第三方视频播放器。
enum ExternalPlayerLocator {
    static let candidateBundles: [String] = [
        "/Applications/IINA.app",
        "/Applications/VLC.app",
        "/Applications/Elmedia Player.app"
    ]

    /// 中文注释：优先 IINA，其次 VLC、Elmedia，找到返回应用 URL，否则 nil。
    static func find() -> URL? {
        for path in candidateBundles where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// 中文注释：返回播放器应用的可读名称（去除 .app 后缀）。
    static func displayName(_ appURL: URL) -> String {
        appURL.deletingPathExtension().lastPathComponent
    }
}

/// `ExtractorKey` 的作用：根据链接 host 推断站点标识（extractor），供历史站点筛选与输出目录。
enum ExtractorKey {
    /// 中文注释：从链接推断站点 key；YouTube / Bilibili 特殊识别，其余取主域二级名。
    static func infer(from urlText: String) -> String {
        guard let url = URL(string: urlText), let host = url.host?.lowercased() else { return "media" }
        if host.contains("youtube") || host.contains("youtu.be") { return "youtube" }
        if host.contains("bilibili") { return "bilibili" }
        let parts = host.split(separator: ".")
        if parts.count >= 2 {
            return String(parts[parts.count - 2])
        }
        return host
    }
}
