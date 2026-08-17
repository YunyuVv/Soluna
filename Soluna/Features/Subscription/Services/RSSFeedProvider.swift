//
//  RSSFeedProvider.swift
//  Soluna
//

import Foundation
import os

/// `ChannelUpdateProvider` 的作用：抽象“获取频道最新视频”的数据源，便于未来切换到 YouTube Data API。
protocol ChannelUpdateProvider {
    func fetchLatestVideos(channelId: String, maxCount: Int) async throws -> [RemoteVideo]
}

/// `RemoteVideo` 的作用：单条视频的轻量数据，不包含任何账号/Cookies 信息。
struct RemoteVideo {
    let videoId: String
    let title: String
    let publishedAt: Date
    let thumbnailURLString: String?
    let videoURLString: String

    var watchURL: URL? { URL(string: videoURLString) }

    /// 中文注释：Shorts 的观看链接路径为 /shorts/，RSS 常混入，默认忽略。
    var isShorts: Bool {
        videoURLString.contains("/shorts/")
    }

    /// 中文注释：按标题特征尽力识别直播/首播（YouTube RSS 不标注直播状态）。
    var isLive: Bool {
        let lower = title.lowercased()
        return lower.contains("直播") || lower.contains("首播")
            || lower.contains("live") || lower.contains("premiere")
    }
}

@MainActor
/// `RSSFeedProvider` 的作用：通过 YouTube 官方公开 RSS 源（无 Cookies、免鉴权）获取频道最新视频。
final class RSSFeedProvider: ChannelUpdateProvider {
    private let logger = Logger(subsystem: "Soluna", category: "RSSFeedProvider")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestVideos(channelId: String, maxCount: Int) async throws -> [RemoteVideo] {
        let urlString = "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "RSS", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无效的频道 ID"])
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        // 中文注释：带常规 UA，降低被当成异常脚本限流的概率。
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Soluna/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            throw RSSFeedError.rateLimited
        }

        let parser = RSSVideoParser(data: data)
        var videos = parser.parse()
        // 中文注释：按设置过滤 Shorts / 直播，减少无意义通知（设计文档风险 #4）。
        if SubscriptionSettings.ignoreShorts {
            videos = videos.filter { !$0.isShorts }
        }
        if SubscriptionSettings.ignoreLive {
            videos = videos.filter { !$0.isLive }
        }
        return Array(videos.prefix(maxCount))
    }
}

enum RSSFeedError: LocalizedError {
    case rateLimited
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "请求过于频繁（HTTP 429），请稍后重试或调大检查间隔"
        case .parseFailed: return "RSS 解析失败"
        }
    }
}

/// `RSSVideoParser` 的作用：解析 YouTube RSS XML，提取 entry 中的视频信息。
private final class RSSVideoParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var currentEntry: Entry?
    private var currentElement = ""
    private var buffer = ""
    private var entries: [RemoteVideo] = []

    private struct Entry {
        var videoId: String?
        var title: String?
        var published: String?
        var thumbnail: String?
        var watchURL: String?
    }

    init(data: Data) { self.data = data }

    func parse() -> [RemoteVideo] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        currentElement = elementName
        if elementName == "entry" {
            currentEntry = Entry()
        }
        if elementName == "media:thumbnail", let url = attributes["url"] {
            currentEntry?.thumbnail = url
        }
        if elementName == "link", let href = attributes["href"] {
            currentEntry?.watchURL = href
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "yt:videoId":
            currentEntry?.videoId = text
        case "title":
            currentEntry?.title = text
        case "published":
            currentEntry?.published = text
        case "entry":
            if let entry = currentEntry,
               let vid = entry.videoId, let title = entry.title {
                let published = RSSVideoParser.parseDate(entry.published) ?? Date()
                entries.append(RemoteVideo(
                    videoId: vid,
                    title: title,
                    publishedAt: published,
                    thumbnailURLString: entry.thumbnail,
                    videoURLString: entry.watchURL ?? "https://www.youtube.com/watch?v=\(vid)"
                ))
            }
            currentEntry = nil
        default:
            break
        }
        buffer = ""
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
