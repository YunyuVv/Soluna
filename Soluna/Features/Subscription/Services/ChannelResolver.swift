//
//  ChannelResolver.swift
//  Soluna
//
//  中文注释：把用户输入（频道 ID / 链接 / @handle）解析为 channelId，并尽量补齐博主名与头像。
//  优先无 Cookie、无 yt-dlp 的公开网页解析；yt-dlp 仅作为可选兜底。
//

import Foundation
import os

/// `ChannelResolveResult` 的作用：解析 @handle / 链接后得到的标准化频道信息。
struct ChannelResolveResult {
    let channelId: String
    let title: String?
    let thumbnailURLString: String?
}

/// `YtDlpStatus` 的作用：描述本机 yt-dlp 的检测结果，供设置页展示。
struct YtDlpStatus {
    let isAvailable: Bool
    let path: String?
    let version: String?

    static let unavailable = YtDlpStatus(isAvailable: false, path: nil, version: nil)
}

@MainActor
/// `ChannelResolver` 的作用：把用户输入解析为 channelId，并补齐博主名/头像。
/// 解析顺序：①直接提取 UC 频道 ID → ②HTTP 公开页面解析 @handle（同时取名字/头像）→ ③yt-dlp 兜底。
final class ChannelResolver {
    private let logger = Logger(subsystem: "Soluna", category: "ChannelResolver")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(_ input: String) async -> Result<ChannelResolveResult, Error> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(NSError(domain: "Resolver", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请输入频道地址或 @handle"]))
        }

        // 中文注释：自动补全常见输入格式，提升容错：
        // - 只贴 @handle → 补成 https://www.youtube.com/@handle
        // - 忘了 https:// → 补全协议头。
        let normalized = normalizeInput(trimmed)

        // 1. 已经是 channelId：直接用 RSS/频道页补齐名字与头像。
        if let id = extractChannelId(from: normalized) {
            let meta = await fetchChannelMeta(channelId: id)
            return .success(ChannelResolveResult(channelId: id, title: meta.title, thumbnailURLString: meta.avatar))
        }

        // 2. 识别 @handle /c/ /user/ /channel/ 等 YouTube 链接，优先走公开 HTTP 页面解析（同时取名字/头像）。
        if let url = URL(string: normalized), isYouTubeChannelURL(url) {
            let httpResult = await resolveHandlePage(url: url)
            // 中文注释：HTTP 解析成功就直接返回；失败则继续 fallback 到 yt-dlp。
            if case .success = httpResult { return httpResult }
            logger.warning("HTTP 解析失败，尝试 yt-dlp 兜底: \(url.absoluteString, privacy: .public)")
        }

        // 3. 可选兜底：yt-dlp。
        return await resolveWithYtDlp(normalized)
    }

    /// 中文注释：对常见简写输入做友好补全。
    private func normalizeInput(_ text: String) -> String {
        let lower = text.lowercased()
        // 只输入 @handle
        if text.hasPrefix("@") {
            return "https://www.youtube.com/\(text)"
        }
        // 有域名但没协议头
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            if lower.hasPrefix("youtube.com") || lower.hasPrefix("www.youtube.com") || lower.hasPrefix("youtu.be") {
                return "https://\(text)"
            }
        }
        return text
    }

    // MARK: - HTTP 公开页面解析

    private func isYouTubeChannelURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let isYouTube = host == "youtube.com" || host == "www.youtube.com" || host == "youtu.be"
        guard isYouTube else { return false }
        let path = url.path
        return path.hasPrefix("/@") || path.hasPrefix("/c/") || path.hasPrefix("/user/") || path.hasPrefix("/channel/")
    }

    private func resolveHandlePage(url: URL) async -> Result<ChannelResolveResult, Error> {
        do {
            guard let html = try await fetchHTML(url: url) else {
                return .failure(NSError(domain: "Resolver", code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "YouTube 页面内容为空"]))
            }
            guard let channelId = extractChannelIdFromHTML(html) else {
                return .failure(NSError(domain: "Resolver", code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "无法从页面中识别频道 ID，请直接粘贴 UC 开头的频道 ID"]))
            }
            // 中文注释：顺带从同一份 HTML 里取博主名（og:title）与头像（og:image）。
            let title = extractOGContent(property: "og:title", in: html)
            let avatar = extractOGContent(property: "og:image", in: html)
            return .success(ChannelResolveResult(channelId: channelId, title: title, thumbnailURLString: avatar))
        } catch {
            return .failure(error)
        }
    }

    /// 中文注释：当输入本就是 channelId 时，用频道页/RSS 补齐名字与头像（best-effort，失败不影响订阅）。
    func fetchChannelMeta(channelId: String) async -> (title: String?, avatar: String?) {
        guard let url = URL(string: "https://www.youtube.com/channel/\(channelId)") else {
            return (nil, nil)
        }
        // 优先频道页（含头像 og:image）。
        if let html = try? await fetchHTML(url: url) {
            let title = extractOGContent(property: "og:title", in: html)
            let avatar = extractOGContent(property: "og:image", in: html)
            if title != nil || avatar != nil { return (title, avatar) }
        }
        // 兜底：RSS 顶层 <title> 至少能拿到名字（无头像）。
        if let rssTitle = await fetchRSSChannelTitle(channelId: channelId) {
            return (rssTitle, nil)
        }
        return (nil, nil)
    }

    private func fetchRSSChannelTitle(channelId: String) async -> String? {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Soluna/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request),
              let xml = String(data: data, encoding: .utf8) else { return nil }
        // 中文注释：RSS 第一个 <title> 即频道名（entry 的 title 在其后）。
        if let range = xml.range(of: "<title>"), let end = xml.range(of: "</title>", range: range.upperBound..<xml.endIndex) {
            let title = String(xml[range.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : decodeHTMLEntities(title)
        }
        return nil
    }

    private func fetchHTML(url: URL) async throws -> String? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // 中文注释：模拟浏览器 UA，降低被返回简化页面的概率。
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "Resolver", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "YouTube 页面请求失败，请检查网络或链接"])
        }
        return String(data: data, encoding: .utf8)
    }

    /// 中文注释：从 YouTube 页面 HTML 中抓取 canonical / og:url 里的 channel/UC... 链接。
    private func extractChannelIdFromHTML(_ html: String) -> String? {
        // 匹配 <link rel="canonical" href="https://www.youtube.com/channel/UC...">
        if let linkCanonical = firstMatch(for: #"<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']"#, in: html),
           let id = extractChannelId(from: linkCanonical) {
            return id
        }
        // 匹配 <meta property="og:url" content="https://www.youtube.com/channel/UC...">
        if let ogURL = firstMatch(for: #"<meta[^>]+property=["']og:url["'][^>]+content=["']([^"']+)["']"#, in: html),
           let id = extractChannelId(from: ogURL) {
            return id
        }
        return nil
    }

    /// 中文注释：提取 <meta property="og:xxx" content="..."> 的内容。
    private func extractOGContent(property: String, in html: String) -> String? {
        let pattern = "<meta[^>]+property=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"']"
        guard let raw = firstMatch(for: pattern, in: html)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return decodeHTMLEntities(raw)
    }

    /// 中文注释：解码常见 HTML 实体，避免频道名出现 &amp; 之类。
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, value) in map {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    private func firstMatch(for pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        let groupRange = match.range(at: 1)
        guard let swiftRange = Range(groupRange, in: text) else { return nil }
        return String(text[swiftRange])
    }

    // MARK: - 直接提取 channelId

    /// 中文注释：从纯文本或 URL 路径/查询里抠出形如 UCxxxx 的频道 ID。
    private func extractChannelId(from text: String) -> String? {
        if text.hasPrefix("UC"), text.count > 20 { return text }
        if let url = URL(string: text) {
            if let channel = url.pathComponents.first(where: { $0.hasPrefix("UC") }) {
                return channel
            }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let cid = components.queryItems?.first(where: { $0.name == "channel_id" })?.value,
               cid.hasPrefix("UC") {
                return cid
            }
        }
        return nil
    }

    // MARK: - yt-dlp 兜底 & 检测

    /// 中文注释：检测本机 yt-dlp 是否可用，并返回路径与版本，供设置页展示。
    /// 注意：GUI 应用不继承 shell 的 PATH，必须显式探测常见安装目录（与下载器一致）。
    func detectYtDlp() -> YtDlpStatus {
        guard let path = ExecutableLocator.find(named: "yt-dlp") else {
            return .unavailable
        }
        let version = ExecutableLocator.version(of: path)
        return YtDlpStatus(isAvailable: true, path: path, version: version)
    }

    private func resolveWithYtDlp(_ input: String) async -> Result<ChannelResolveResult, Error> {
        guard let ytDlpPath = ExecutableLocator.find(named: "yt-dlp") else {
            return .failure(NSError(domain: "Resolver", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "未找到 yt-dlp，且无法通过公开页面解析该链接。请直接粘贴频道 ID（UC 开头）。"]))
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = ["--no-warnings", "--skip-download",
                                 "--print", "%(channel_id)s||%(uploader)s||%(thumbnail)s", input]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            // 中文注释：用终止回调读取输出，避免在 async 上下文同步 waitUntilExit 阻塞主线程。
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
                    continuation.resume(returning: .failure(NSError(domain: "Resolver", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "yt-dlp 解析失败，请确认链接有效"])))
                    return
                }
                let parts = output.components(separatedBy: "||")
                let channelId = parts.first ?? ""
                guard channelId.hasPrefix("UC"), !channelId.isEmpty else {
                    continuation.resume(returning: .failure(NSError(domain: "Resolver", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "yt-dlp 返回异常: \(output)"])))
                    return
                }
                let title = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
                let thumb = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
                continuation.resume(returning: .success(ChannelResolveResult(
                    channelId: channelId, title: title, thumbnailURLString: thumb)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(error))
            }
        }
    }

}

