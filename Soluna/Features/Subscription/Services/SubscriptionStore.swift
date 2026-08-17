//
//  SubscriptionStore.swift
//  Soluna
//

import Foundation
import SwiftData
import os

@MainActor
/// `SubscriptionStore` 的作用：封装 YouTube 订阅与通知的 SwiftData 读写逻辑，与下载历史库解耦。
final class SubscriptionStore {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "Soluna", category: "SubscriptionStore")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 订阅读写

    /// 中文注释：按创建时间倒序读取全部订阅。
    func loadSubscriptions() -> [ChannelSubscription] {
        let descriptor = FetchDescriptor<ChannelSubscription>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 中文注释：判断某个频道 ID 是否已订阅，避免重复添加。
    func subscriptionExists(channelId: String) -> Bool {
        loadSubscriptions().contains { $0.channelId == channelId }
    }

    /// 中文注释：按频道 ID 查找已订阅记录，供备份恢复时取本地 id。
    func firstSubscription(channelId: String) -> ChannelSubscription? {
        loadSubscriptions().first { $0.channelId == channelId }
    }

    func addSubscription(_ subscription: ChannelSubscription) {
        modelContext.insert(subscription)
        _ = saveContext()
    }

    /// 中文注释：删除订阅时，一并删除其下所有通知，避免孤儿数据。
    func deleteSubscription(id: UUID) {
        guard let sub = fetchSubscription(id: id) else { return }
        loadNotifications().filter { $0.subscriptionID == id }.forEach { modelContext.delete($0) }
        modelContext.delete(sub)
        _ = saveContext()
    }

    /// 中文注释：回写轮询结果，记录最后检测时间与失败原因。
    func updateSubscriptionChecked(id: UUID, lastVideoId: String?, errorMessage: String?) {
        guard let sub = fetchSubscription(id: id) else { return }
        sub.lastCheckedAt = Date()
        if let lastVideoId { sub.lastVideoId = lastVideoId }
        sub.pollErrorMessage = errorMessage
        _ = saveContext()
    }

    /// 中文注释：更新频道的展示信息（名称/头像缓存路径/远程头像地址），用于「更新信息」功能。
    /// 仅覆盖非空的传入字段，避免误清空已有数据。
    func updateChannelInfo(id: UUID, title: String?, localThumbnailPath: String?, remoteThumbnailURLString: String?) {
        guard let sub = fetchSubscription(id: id) else { return }
        if let title, !title.isEmpty { sub.title = title }
        if let localThumbnailPath { sub.localThumbnailPath = localThumbnailPath }
        if let remoteThumbnailURLString { sub.thumbnailURLString = remoteThumbnailURLString }
        _ = saveContext()
    }

    private func fetchSubscription(id: UUID) -> ChannelSubscription? {
        loadSubscriptions().first { $0.id == id }
    }

    // MARK: - 通知读写

    /// 中文注释：读取通知，可按状态过滤；默认按发布时间倒序。
    func loadNotifications(status: VideoNotificationStatus? = nil) -> [VideoNotification] {
        let descriptor = FetchDescriptor<VideoNotification>(
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        guard var all = try? modelContext.fetch(descriptor) else { return [] }
        if let status { all = all.filter { $0.status == status } }
        return all
    }

    /// 中文注释：用复合去重键判断该视频是否已有任意状态的通知，防止重复建通知。
    func notificationExists(subscriptionID: UUID, videoId: String) -> Bool {
        let key = "\(subscriptionID.uuidString)_\(videoId)"
        return loadNotifications().contains { $0.dedupeKey == key }
    }

    func addNotification(_ notification: VideoNotification) {
        modelContext.insert(notification)
        _ = saveContext()
    }

    /// 中文注释：测试通知用——若该视频通知已存在（如基线 handled）则重置为 pending 使其重新出现在收件箱；
    /// 返回是否命中已有记录（未命中则调用方需新建 pending 通知）。
    func resetNotificationToPending(subscriptionID: UUID, videoId: String) -> Bool {
        let key = "\(subscriptionID.uuidString)_\(videoId)"
        guard let existing = loadNotifications().first(where: { $0.dedupeKey == key }) else { return false }
        existing.status = .pending
        existing.handledAt = nil
        _ = saveContext()
        return true
    }

    func markNotificationHandled(id: UUID) {
        guard let n = fetchNotification(id: id) else { return }
        n.status = .handled
        n.handledAt = Date()
        _ = saveContext()
    }

    /// 中文注释：物理删除一条通知（用户手动删除）。
    func deleteNotification(id: UUID) {
        guard let n = fetchNotification(id: id) else { return }
        modelContext.delete(n)
        _ = saveContext()
    }

    private func fetchNotification(id: UUID) -> VideoNotification? {
        loadNotifications().first { $0.id == id }
    }

    /// 中文注释：把所有待处理通知批量标记为已处理。
    func markAllPendingHandled() {
        let pending = loadNotifications(status: .pending)
        guard pending.isEmpty == false else { return }
        for n in pending {
            n.status = .handled
            n.handledAt = Date()
        }
        _ = saveContext()
    }

    /// 中文注释：批量删除所有「已处理」通知，用于清空收件箱历史。
    func deleteAllHandled() {
        let handled = loadNotifications(status: .handled)
        guard handled.isEmpty == false else { return }
        for n in handled { modelContext.delete(n) }
        _ = saveContext()
    }

    /// 中文注释：统一保存并回滚，避免调用方重复处理异常。
    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            logger.error("保存订阅数据失败: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
            return false
        }
    }
}
