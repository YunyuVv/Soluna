//
//  VideoNotification.swift
//  Soluna
//

import Foundation
import SwiftData

/// `VideoNotificationStatus` 的作用：通知在收件箱中的生命周期状态。
enum VideoNotificationStatus: String, Codable, CaseIterable {
    case pending   // 待处理：出现在收件箱，需用户手动处理或删除
    case handled   // 已处理：用户已下载/标记，离开收件箱（含订阅基线）
    case deleted   // 已删除

    var title: String {
        switch self {
        case .pending: return "待处理"
        case .handled: return "已处理"
        case .deleted: return "已删除"
        }
    }
}

/// `VideoNotification` 的作用：某订阅频道出现的一条新视频通知，必须用户手动处理或删除。
@Model
final class VideoNotification {
    @Attribute(.unique) var id: UUID
    /// 中文注释：复合去重键 (subscriptionID_videoId)，保证同一视频不会重复建通知。
    @Attribute(.unique) var dedupeKey: String
    var subscriptionID: UUID
    var channelTitle: String
    var videoId: String
    var title: String
    var publishedAt: Date
    var thumbnailURLString: String?
    var videoURLString: String
    private var statusRawValue: String
    var discoveredAt: Date
    var handledAt: Date?

    var status: VideoNotificationStatus {
        get { VideoNotificationStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        subscriptionID: UUID,
        channelTitle: String,
        videoId: String,
        title: String,
        publishedAt: Date,
        thumbnailURLString: String? = nil,
        videoURLString: String,
        status: VideoNotificationStatus = .pending,
        discoveredAt: Date = Date(),
        handledAt: Date? = nil
    ) {
        self.id = id
        self.dedupeKey = "\(subscriptionID.uuidString)_\(videoId)"
        self.subscriptionID = subscriptionID
        self.channelTitle = channelTitle
        self.videoId = videoId
        self.title = title
        self.publishedAt = publishedAt
        self.thumbnailURLString = thumbnailURLString
        self.videoURLString = videoURLString
        self.statusRawValue = status.rawValue
        self.discoveredAt = discoveredAt
        self.handledAt = handledAt
    }
}

/// `VideoNotificationSnapshot` 的作用：通知记录的值类型快照，供 SwiftUI 视图消费。
struct VideoNotificationSnapshot: Identifiable {
    let id: UUID
    let subscriptionID: UUID
    let channelTitle: String
    let videoId: String
    let title: String
    let publishedAt: Date
    let thumbnailURLString: String?
    let videoURLString: String
    let status: VideoNotificationStatus
    let discoveredAt: Date
    let handledAt: Date?

    init(record: VideoNotification) {
        self.id = record.id
        self.subscriptionID = record.subscriptionID
        self.channelTitle = record.channelTitle
        self.videoId = record.videoId
        self.title = record.title
        self.publishedAt = record.publishedAt
        self.thumbnailURLString = record.thumbnailURLString
        self.videoURLString = record.videoURLString
        self.status = record.status
        self.discoveredAt = record.discoveredAt
        self.handledAt = record.handledAt
    }

    var watchURL: URL? { URL(string: videoURLString) }
}
