//
//  SubscriptionBackupService.swift
//  Soluna
//
//  中文注释：订阅数据的导出/导入备份，序列化全部频道与其通知为 JSON，
//  导入时按 channelId 幂等恢复，避免重装或换机后丢失订阅。

import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// `SubscriptionBackup` 的作用：一次完整备份的顶层容器，可编码为 JSON 文件。
struct SubscriptionBackup: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let subscriptions: [SubscriptionBackupItem]

    init(schemaVersion: Int = 1, exportedAt: Date = Date(), subscriptions: [SubscriptionBackupItem]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.subscriptions = subscriptions
    }
}

/// `SubscriptionBackupItem` 的作用：单个频道的备份数据，附带其下通知列表。
struct SubscriptionBackupItem: Codable {
    let id: String
    let channelId: String
    let title: String
    let thumbnailURLString: String?
    let localThumbnailPath: String?
    let sourceInput: String
    let isEnabled: Bool
    let createdAt: Date
    let lastCheckedAt: Date?
    let lastVideoId: String?
    let notifications: [NotificationBackupItem]
}

/// `NotificationBackupItem` 的作用：单条通知的备份数据。
struct NotificationBackupItem: Codable {
    let id: String
    let videoId: String
    let channelTitle: String
    let title: String
    let publishedAt: Date
    let thumbnailURLString: String?
    let videoURLString: String
    let status: VideoNotificationStatus
    let discoveredAt: Date
    let handledAt: Date?
}

/// `SubscriptionBackupDocument` 的作用：适配 SwiftUI `fileExporter` 的 JSON 文档。
struct SubscriptionBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// `SubscriptionBackupService` 的作用：构建与恢复订阅备份，集中读写逻辑。
enum SubscriptionBackupService {
    /// 中文注释：把当前 store 内所有订阅（含通知）序列化为备份结构。
    static func build(store: SubscriptionStore) throws -> SubscriptionBackup {
        let subs = store.loadSubscriptions()
        let items = subs.map { sub -> SubscriptionBackupItem in
            let notifs = store.loadNotifications().filter { $0.subscriptionID == sub.id }
            let notificationItems = notifs.map { n -> NotificationBackupItem in
                NotificationBackupItem(
                    id: n.id.uuidString,
                    videoId: n.videoId,
                    channelTitle: n.channelTitle,
                    title: n.title,
                    publishedAt: n.publishedAt,
                    thumbnailURLString: n.thumbnailURLString,
                    videoURLString: n.videoURLString,
                    status: n.status,
                    discoveredAt: n.discoveredAt,
                    handledAt: n.handledAt
                )
            }
            return SubscriptionBackupItem(
                id: sub.id.uuidString,
                channelId: sub.channelId,
                title: sub.title,
                thumbnailURLString: sub.thumbnailURLString,
                localThumbnailPath: sub.localThumbnailPath,
                sourceInput: sub.sourceInput,
                isEnabled: sub.isEnabled,
                createdAt: sub.createdAt,
                lastCheckedAt: sub.lastCheckedAt,
                lastVideoId: sub.lastVideoId,
                notifications: notificationItems
            )
        }
        return SubscriptionBackup(subscriptions: items)
    }

    /// 中文注释：把备份恢复到本地。返回 (新增订阅数, 新增通知数)。
    /// 幂等：已存在的频道（按 channelId）与通知（按 dedupeKey）不会重复创建。
    @discardableResult
    static func apply(_ backup: SubscriptionBackup, store: SubscriptionStore) -> (subscriptions: Int, notifications: Int) {
        var newSubscriptions = 0
        var newNotifications = 0
        // channelId -> 本地订阅 id，用于把通知挂到正确订阅下。
        var idMap: [String: UUID] = [:]

        for item in backup.subscriptions {
            let backupID = UUID(uuidString: item.id) ?? UUID()
            if let existing = store.firstSubscription(channelId: item.channelId) {
                idMap[item.channelId] = existing.id
                store.updateChannelInfo(
                    id: existing.id,
                    title: item.title,
                    localThumbnailPath: item.localThumbnailPath,
                    remoteThumbnailURLString: item.thumbnailURLString
                )
            } else {
                let sub = ChannelSubscription(
                    id: backupID,
                    channelId: item.channelId,
                    title: item.title,
                    thumbnailURLString: item.thumbnailURLString,
                    localThumbnailPath: item.localThumbnailPath,
                    sourceInput: item.sourceInput,
                    isEnabled: item.isEnabled,
                    createdAt: item.createdAt,
                    lastCheckedAt: item.lastCheckedAt,
                    lastVideoId: item.lastVideoId
                )
                store.addSubscription(sub)
                idMap[item.channelId] = backupID
                newSubscriptions += 1
            }
        }

        for item in backup.subscriptions {
            guard let subscriptionID = idMap[item.channelId] else { continue }
            for n in item.notifications {
                if store.notificationExists(subscriptionID: subscriptionID, videoId: n.videoId) {
                    continue
                }
                let notification = VideoNotification(
                    id: UUID(uuidString: n.id) ?? UUID(),
                    subscriptionID: subscriptionID,
                    channelTitle: n.channelTitle,
                    videoId: n.videoId,
                    title: n.title,
                    publishedAt: n.publishedAt,
                    thumbnailURLString: n.thumbnailURLString,
                    videoURLString: n.videoURLString,
                    status: n.status,
                    discoveredAt: n.discoveredAt,
                    handledAt: n.handledAt
                )
                store.addNotification(notification)
                newNotifications += 1
            }
        }

        return (newSubscriptions, newNotifications)
    }
}
