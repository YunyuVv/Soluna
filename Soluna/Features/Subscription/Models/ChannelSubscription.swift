//
//  ChannelSubscription.swift
//  Soluna
//

import Foundation
import SwiftData

/// `ChannelSubscription` 的作用：记录一条 YouTube 频道订阅，并保存最后一次检测状态。
@Model
final class ChannelSubscription {
    @Attribute(.unique) var id: UUID
    var channelId: String
    var title: String
    var thumbnailURLString: String?
    /// 中文注释：头像本地缓存路径（绝对路径），离线也能显示，避免每次从网络拉取。
    var localThumbnailPath: String?
    /// 中文注释：用户最初输入的 @handle / 链接，便于排查与展示来源。
    var sourceInput: String
    var isEnabled: Bool
    var createdAt: Date
    var lastCheckedAt: Date?
    var lastVideoId: String?
    /// 中文注释：最近一次轮询失败的原因，便于在卡片上提示用户。
    var pollErrorMessage: String?

    init(
        id: UUID = UUID(),
        channelId: String,
        title: String,
        thumbnailURLString: String? = nil,
        localThumbnailPath: String? = nil,
        sourceInput: String = "",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastCheckedAt: Date? = nil,
        lastVideoId: String? = nil,
        pollErrorMessage: String? = nil
    ) {
        self.id = id
        self.channelId = channelId
        self.title = title
        self.thumbnailURLString = thumbnailURLString
        self.localThumbnailPath = localThumbnailPath
        self.sourceInput = sourceInput
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastCheckedAt = lastCheckedAt
        self.lastVideoId = lastVideoId
        self.pollErrorMessage = pollErrorMessage
    }
}

/// `ChannelSubscriptionSnapshot` 的作用：订阅记录的值类型快照，供 SwiftUI 视图消费。
struct ChannelSubscriptionSnapshot: Identifiable, Hashable {
    let id: UUID
    let channelId: String
    let title: String
    let thumbnailURLString: String?
    let localThumbnailPath: String?
    let sourceInput: String
    let isEnabled: Bool
    let createdAt: Date
    let lastCheckedAt: Date?
    let lastVideoId: String?
    let pollErrorMessage: String?

    init(record: ChannelSubscription) {
        self.id = record.id
        self.channelId = record.channelId
        self.title = record.title
        self.thumbnailURLString = record.thumbnailURLString
        self.localThumbnailPath = record.localThumbnailPath
        self.sourceInput = record.sourceInput
        self.isEnabled = record.isEnabled
        self.createdAt = record.createdAt
        self.lastCheckedAt = record.lastCheckedAt
        self.lastVideoId = record.lastVideoId
        self.pollErrorMessage = record.pollErrorMessage
    }

    /// 中文注释：该频道的 YouTube 主页链接，用于「在浏览器打开」。优先保留用户最初输入的 @handle/频道主页，
    /// 否则用频道 ID 构造 canonical 主页（始终有效）。
    var channelURLString: String {
        let input = sourceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.hasPrefix("@") {
            return "https://www.youtube.com/\(input)"
        }
        if let url = URL(string: input),
           let host = url.host,
           (host.contains("youtube.com") || host.contains("youtu.be")) {
            let path = url.pathComponents
            // 用户最初输入的就是频道主页（/@handle 或 /channel/ID）时直接复用。
            if path.contains("@") || path.contains("channel") {
                return input
            }
        }
        return "https://www.youtube.com/channel/\(channelId)"
    }
}
