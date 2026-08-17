//
//  MediaPlaylistResolverService.swift
//  Soluna
//
//  Created by Codex on 2026/5/28.
//

import Foundation

/// `MediaPlaylistResolverService` 的作用：调用 `yt-dlp` 解析列表链接元数据，供下载前交互决策使用。
final class MediaPlaylistResolverService {
    private let decoder = JSONDecoder()

    /// 中文注释：yt-dlp 单条网络请求的超时（秒）。弱网/被限流时单个请求可能长时间挂起，
    /// 设置后让 yt-dlp 主动放弃而不是把整个进程拖死。
    private static let ytDlpSocketTimeoutSeconds: Int = 20

    /// 中文注释：解析指定链接的列表结构，若不是列表则返回空值。
    /// `playlistEnd` 为非 nil 时仅取列表前 N 条（如频道最近上传），避免全量列举拖垮轮询。
    /// `timeoutSeconds` 为整个进程的最长运行时间——到点由看门狗强制终止，避免无限挂起（卡死）。
    func resolve(urlText: String, executablePath: String, useBrowserCookies: Bool, browserCookieSource: BrowserCookieSource, playlistEnd: Int? = nil, timeoutSeconds: TimeInterval = 120) -> MediaPlaylistResolutionResult? {
        let arguments = buildArguments(urlText: urlText, useBrowserCookies: useBrowserCookies, browserCookieSource: browserCookieSource, playlistEnd: playlistEnd)
        guard let data = runProcess(executablePath: executablePath, arguments: arguments, timeoutSeconds: timeoutSeconds) else { return nil }
        guard let payload = try? decoder.decode(PlaylistPayload.self, from: data) else { return nil }
        return buildResolutionResult(urlText: urlText, payload: payload)
    }

    /// 中文注释：构建列表解析命令参数，优先使用平铺结果避免下载额外媒体信息。
    private func buildArguments(urlText: String, useBrowserCookies: Bool, browserCookieSource: BrowserCookieSource, playlistEnd: Int? = nil) -> [String] {
        var arguments = ["--dump-single-json", "--flat-playlist", "--no-warnings", "--socket-timeout", "\(Self.ytDlpSocketTimeoutSeconds)"]
        if useBrowserCookies {
            arguments.append(contentsOf: ["--cookies-from-browser", browserCookieSource.argumentValue])
        }
        // 中文注释：限制拉取条数。新视频始终在 uploads 列表顶部，轮询只需最近一批即可检测新上传，
        // 同时避免巨型 JSON 解码与内存暴涨。下载页调用不传此参数，保持全量行为。
        if let end = playlistEnd, end > 0 {
            arguments.append(contentsOf: ["--playlist-end", "\(end)"])
        }
        arguments.append(urlText)
        return arguments
    }

    /// 中文注释：执行外部进程并返回标准输出数据，失败时回退为空。
    /// `timeoutSeconds` 为看门狗上限：yt-dlp 在弱网/被限流时可能长时间（甚至无限）挂起，
    /// 到点强制终止进程并返回空，使上层走「解析失败」分支而不是永久卡在「加载中」。
    private func runProcess(executablePath: String, arguments: [String], timeoutSeconds: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let envPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let merged = Array(NSOrderedSet(array: envPaths + defaults)) as? [String] ?? defaults
        environment["PATH"] = merged.joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // 中文注释：看门狗定时器——超时后强制终止 yt-dlp 进程，确保调用方总能拿到结果（成功或失败），不会无限挂起。
        let watchdog = DispatchSource.makeTimerSource()
        watchdog.schedule(deadline: .now() + timeoutSeconds)
        watchdog.setEventHandler { [weak process] in
            process?.terminate()
        }
        watchdog.resume()

        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    /// 中文注释：把 `yt-dlp` JSON 结果转换为应用内部的列表解析结果。
    private func buildResolutionResult(urlText: String, payload: PlaylistPayload) -> MediaPlaylistResolutionResult? {
        guard let entries = payload.entries, entries.isEmpty == false else { return nil }

        let normalizedEntries = entries.enumerated().map { offset, entry in
            let id = entry.id ?? "\(offset + 1)"
            let webpageURL = entry.url.flatMap { buildWebpageURL(from: $0, extractor: payload.extractorKey) } ?? entry.webpageURL
            return MediaPlaylistEntry(
                id: id,
                index: offset + 1,
                videoID: entry.id,
                title: entry.title ?? "",
                durationText: formatDuration(entry.duration),
                uploader: entry.uploader ?? entry.channel,
                webpageURL: webpageURL,
                thumbnailURL: URL(string: entry.thumbnail ?? ""),
                isSelected: true
            )
        }

        let playlistType = detectPlaylistType(from: urlText, payload: payload)
        return MediaPlaylistResolutionResult(
            sourceURL: urlText,
            title: payload.title ?? "",
            extractorKey: payload.extractorKey ?? ExtractorKey.infer(from: urlText),
            playlistID: payload.id ?? extractPlaylistID(from: urlText),
            playlistType: playlistType,
            entries: normalizedEntries,
            currentVideoID: extractCurrentVideoID(from: urlText)
        )
    }

    /// 中文注释：根据链接与 payload 判断列表类型，区分普通列表与 Mix。
    private func detectPlaylistType(from urlText: String, payload: PlaylistPayload) -> MediaPlaylistType {
        if isMixURL(urlText) {
            return .mix
        }
        if extractCurrentVideoID(from: urlText) != nil {
            return .videoInPlaylist
        }
        if payload.entries?.isEmpty == false {
            return .playlist
        }
        return .none
    }

    /// 中文注释：判断链接是否属于 YouTube Mix / Radio 类型。
    private func isMixURL(_ urlText: String) -> Bool {
        guard let components = URLComponents(string: urlText) else { return false }
        let listValue = components.queryItems?.first(where: { $0.name == "list" })?.value?.lowercased() ?? ""
        let hasStartRadio = components.queryItems?.contains(where: { $0.name == "start_radio" }) == true
        return listValue.hasPrefix("rd") || hasStartRadio
    }

    /// 中文注释：从当前链接中提取当前视频 ID，用于“仅当前视频”模式。
    private func extractCurrentVideoID(from urlText: String) -> String? {
        guard let components = URLComponents(string: urlText) else { return nil }
        return components.queryItems?.first(where: { $0.name == "v" })?.value
    }

    /// 中文注释：从当前链接中提取列表 ID。
    private func extractPlaylistID(from urlText: String) -> String? {
        guard let components = URLComponents(string: urlText) else { return nil }
        return components.queryItems?.first(where: { $0.name == "list" })?.value
    }

    /// 中文注释：根据站点和相对 URL 推断可直接打开的网页地址。
    private func buildWebpageURL(from rawURL: String, extractor: String?) -> String? {
        if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
            return rawURL
        }
        if let extractor, extractor.lowercased().contains("youtube"), rawURL.isEmpty == false {
            return "https://www.youtube.com/watch?v=\(rawURL)"
        }
        return nil
    }

    /// 中文注释：把秒数格式化成 `HH:MM:SS` 或 `MM:SS` 文本。
    private func formatDuration(_ duration: Double?) -> String? {
        guard let duration, duration > 0 else { return nil }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours):" + String(format: "%02d:%02d", minutes, seconds)
        }
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}

/// `PlaylistPayload` 的作用：映射 `yt-dlp --dump-single-json` 返回的顶层 JSON。
private struct PlaylistPayload: Decodable {
    let id: String?
    let title: String?
    let extractorKey: String?
    let entries: [PlaylistEntryPayload]?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case extractorKey = "extractor_key"
        case entries
    }
}

/// `PlaylistEntryPayload` 的作用：映射列表中单个条目的 JSON 字段。
private struct PlaylistEntryPayload: Decodable {
    let id: String?
    let title: String?
    let duration: Double?
    let uploader: String?
    let channel: String?
    let url: String?
    let webpageURL: String?
    let thumbnail: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case uploader
        case channel
        case url
        case webpageURL = "webpage_url"
        case thumbnail
    }
}
