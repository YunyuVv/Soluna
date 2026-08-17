//
//  SubscriptionViewModel.swift
//  Soluna
//

import Foundation
import SwiftData
import SwiftUI
import AppKit
import Observation
import os

@MainActor
@Observable
/// `SubscriptionViewModel` 的作用：订阅功能的统一状态与业务入口，连接 Store / 解析器 / RSS / 轮询 / 通知。
final class SubscriptionViewModel {
    private(set) var subscriptions: [ChannelSubscriptionSnapshot] = []
    private(set) var pendingNotifications: [VideoNotificationSnapshot] = []
    private(set) var isPolling = false
    private(set) var lastPolledAt: Date?
    private(set) var errorMessage: String?
    private(set) var pendingCount: Int = 0
    /// 中文注释：已处理通知数量，用于「清空已处理」按钮可见性与提示。
    private(set) var handledCount: Int = 0
    /// 中文注释：正在手动检测的订阅 ID 集合，用于卡片按钮显示进度/禁用。
    private(set) var checkingIDs: Set<UUID> = []
    /// 中文注释：正在「更新信息」的订阅 ID 集合，用于卡片按钮显示进度/禁用。
    private(set) var refreshingIDs: Set<UUID> = []
    /// 中文注释：是否正在执行「更新全部信息」，用于按钮进度态。
    private(set) var isRefreshingAll = false
    /// 中文注释：最近一次「立即检查/全部检查」的结果明细（含每条视频标题+链接），用于结果弹窗交互展示。
    private(set) var lastCheckOutcomes: [ChannelCheckOutcome] = []
    /// 中文注释：结果弹窗顶部的汇总一行文案。
    private(set) var lastCheckHeadline: String = ""
    /// 中文注释：控制检查结果弹窗展示。
    var showCheckResult = false
    /// 中文注释：测试通知的结果提示（成功/失败原因），用于弹窗反馈。
    var testNotificationMessage: String?
    /// 中文注释：控制测试通知结果弹窗展示。
    var showTestNotificationResult = false
    /// 中文注释：是否正在执行「全部检查」，用于按钮进度态。
    private(set) var isCheckingAll = false
    var selectedTab: SubscriptionTab = .manage

    private var store: SubscriptionStore?
    private let resolver = ChannelResolver()
    private let notifier = SystemNotificationService()
    private var pollingService: SubscriptionPollingService?
    private let logger = Logger(subsystem: "Soluna", category: "SubscriptionVM")

    /// 中文注释：注入 ModelContext 并启动轮询，仅在首次调用时执行。
    func configure(modelContext: ModelContext) {
        guard store == nil else { return }
        let store = SubscriptionStore(modelContext: modelContext)
        self.store = store
        self.pollingService = SubscriptionPollingService(store: store, notifier: notifier)
        notifier.requestAuthorizationIfNeeded()
        load()
        startPolling()
    }

    func load() {
        guard let store else { return }
        subscriptions = store.loadSubscriptions().map(ChannelSubscriptionSnapshot.init)
        let pending = store.loadNotifications(status: .pending).map(VideoNotificationSnapshot.init)
        pendingNotifications = pending
        pendingCount = pending.count
        handledCount = store.loadNotifications(status: .handled).count
    }

    /// 中文注释：清空错误提示，供添加订阅弹窗在出现前重置状态。
    func clearErrorMessage() {
        errorMessage = nil
    }

    /// 中文注释：在视图层（如导入/导出失败）写入错误提示。
    func reportError(_ message: String) {
        errorMessage = message
    }

    // MARK: - 备份导出 / 导入

    /// 中文注释：构建当前订阅（含通知）的备份结构，供导出为 JSON 文件。
    func exportBackup() -> SubscriptionBackup? {
        guard let store else { return nil }
        return try? SubscriptionBackupService.build(store: store)
    }

    /// 中文注释：从 JSON 数据恢复备份；返回新增的频道/通知数量，失败返回 nil 并写入错误提示。
    @discardableResult
    func importBackup(from data: Data) -> (subscriptions: Int, notifications: Int)? {
        guard let store else { return nil }
        do {
            let backup = try JSONDecoder().decode(SubscriptionBackup.self, from: data)
            let result = SubscriptionBackupService.apply(backup, store: store)
            load()
            errorMessage = nil
            return result
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 订阅管理

    func addSubscription(input: String) async {
        errorMessage = nil
        let result = await resolver.resolve(input)
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let resolved):
            guard let store else { return }
            if store.subscriptionExists(channelId: resolved.channelId) {
                errorMessage = "该频道已经订阅过了"
                return
            }
            // 中文注释：若解析结果缺名字或头像，再补一次频道元信息，尽量拿到博主名与头像。
            var title = resolved.title
            var thumbnail = resolved.thumbnailURLString
            if title == nil || thumbnail == nil {
                let meta = await resolver.fetchChannelMeta(channelId: resolved.channelId)
                title = title ?? meta.title
                thumbnail = thumbnail ?? meta.avatar
            }
            let subscription = ChannelSubscription(
                channelId: resolved.channelId,
                title: title ?? "频道 \(resolved.channelId)",
                thumbnailURLString: thumbnail,
                localThumbnailPath: await SubscriptionArtworkService.cacheAvatar(remoteURLString: thumbnail, channelId: resolved.channelId),
                sourceInput: input
            )
            store.addSubscription(subscription)
            // 中文注释：建立基线——把当前已有视频标记为已处理，避免历史视频轰炸收件箱。
            await createBaseline(for: subscription)
            load()
        }
    }

    private func createBaseline(for subscription: ChannelSubscription) async {
        guard let store else { return }
        do {
            let videos = try await RSSFeedProvider().fetchLatestVideos(channelId: subscription.channelId, maxCount: 15)
            for video in videos {
                let notification = VideoNotification(
                    subscriptionID: subscription.id,
                    channelTitle: subscription.title,
                    videoId: video.videoId,
                    title: video.title,
                    publishedAt: video.publishedAt,
                    thumbnailURLString: video.thumbnailURLString,
                    videoURLString: video.videoURLString,
                    status: .handled
                )
                store.addNotification(notification)
            }
        } catch {
            // 中文注释：基线建立失败不阻塞订阅，后续轮询会自然补齐（可能多发几条历史通知）。
            logger.warning("建立订阅基线失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeSubscription(id: UUID) {
        store?.deleteSubscription(id: id)
        load()
    }

    // MARK: - 更新频道信息

    /// 中文注释：手动刷新单个频道的博主名称与头像（频道信息可能变更），并更新本地头像缓存。
    func refreshChannelInfo(id: UUID) async {
        guard !refreshingIDs.contains(id) else { return }
        guard let sub = store?.loadSubscriptions().first(where: { $0.id == id }) else { return }
        refreshingIDs.insert(id)
        defer { refreshingIDs.remove(id) }
        // 中文注释：复用解析器的频道元信息抓取（频道页 og:title/og:image，兜底 RSS 标题）。
        let meta = await resolver.fetchChannelMeta(channelId: sub.channelId)
        // 中文注释：force 重新下载头像到本地缓存，覆盖可能已变更的头像。
        let localPath = await SubscriptionArtworkService.cacheAvatar(
            remoteURLString: meta.avatar ?? sub.thumbnailURLString,
            channelId: sub.channelId,
            force: true
        )
        store?.updateChannelInfo(
            id: id,
            title: meta.title,
            localThumbnailPath: localPath,
            remoteThumbnailURLString: meta.avatar
        )
        load()
    }

    /// 中文注释：批量刷新所有已订阅频道的信息（管理面板「更新全部」按钮调用）。
    func refreshAllChannelInfo() async {
        guard !isRefreshingAll else { return }
        guard let store else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }
        let ids = store.loadSubscriptions().map { $0.id }
        for id in ids {
            await refreshChannelInfo(id: id)
        }
    }

    // MARK: - 通知收件箱

    func removeNotification(id: UUID) {
        store?.deleteNotification(id: id)
        load()
    }

    func markHandled(id: UUID) {
        store?.markNotificationHandled(id: id)
        load()
    }

    /// 中文注释：一键标记全部为已处理。
    func markAllHandled() {
        for notification in pendingNotifications {
            store?.markNotificationHandled(id: notification.id)
        }
        load()
    }

    /// 中文注释：清空所有「已处理」通知（批量删除历史）。
    func clearHandled() {
        store?.deleteAllHandled()
        load()
    }

    // MARK: - 轮询控制

    func startPolling() {
        pollingService?.start()
        isPolling = pollingService?.isPolling ?? false
    }

    func stopPolling() {
        pollingService?.stop()
        isPolling = false
    }

    /// 中文注释：全部检查——逐个检查所有订阅并汇总结果，反馈给用户。
    func pollNow() async {
        guard let pollingService, let store else { return }
        guard !isCheckingAll else { return }
        isCheckingAll = true
        defer { isCheckingAll = false }

        let subs = store.loadSubscriptions().filter { $0.isEnabled }
        var outcomes: [ChannelCheckOutcome] = []
        for sub in subs {
            if let outcome = await pollingService.runOnce(subscriptionID: sub.id) {
                outcomes.append(outcome)
            }
        }
        lastPolledAt = pollingService.lastPolledAt
        load()
        presentCheckResult(outcomes: outcomes, scope: "全部检查")
    }

    /// 中文注释：手动检测单个订阅频道（卡片上的「立即检查」按钮），并把检查内容反馈出来。
    func checkNow(subscriptionID: UUID) async {
        guard !checkingIDs.contains(subscriptionID) else { return }
        checkingIDs.insert(subscriptionID)
        let outcome = await pollingService?.runOnce(subscriptionID: subscriptionID)
        lastPolledAt = pollingService?.lastPolledAt
        checkingIDs.remove(subscriptionID)
        load()
        if let outcome {
            presentCheckResult(outcomes: [outcome], scope: "立即检查")
        }
    }

    /// 中文注释：把一次或多次检查结果存起来并弹出交互式结果弹窗（列出视频标题+链接，可复制/打开）。
    private func presentCheckResult(outcomes: [ChannelCheckOutcome], scope: String) {
        lastCheckOutcomes = outcomes
        guard !outcomes.isEmpty else {
            lastCheckHeadline = "没有已启用的订阅频道可检查。"
            showCheckResult = true
            return
        }
        let totalNew = outcomes.reduce(0) { $0 + $1.newCount }
        let totalFetched = outcomes.reduce(0) { $0 + $1.fetchedCount }
        lastCheckHeadline = "本次\(scope)：共 \(outcomes.count) 个频道，抓取 \(totalFetched) 条视频，发现 \(totalNew) 条新视频。"
        showCheckResult = true
    }

    // MARK: - 测试通知

    /// 中文注释：用「第一个订阅博主的最新视频」发送真实测试通知，并把该视频放入收件箱。
    /// 无订阅时给出提示（UI 层会隐藏按钮，这里作为兜底）。
    func sendTestNotification() async {
        guard let store else { return }
        let subs = store.loadSubscriptions().filter { $0.isEnabled }
        guard let firstSub = subs.first else {
            testNotificationMessage = "请先订阅至少一个频道，再测试通知。"
            showTestNotificationResult = true
            return
        }

        do {
            // 中文注释：真实拉取该博主最新一条视频，保证测试内容完全真实。
            let videos = try await RSSFeedProvider().fetchLatestVideos(channelId: firstSub.channelId, maxCount: 1)
            guard let video = videos.first else {
                testNotificationMessage = "未能获取「\(firstSub.title)」的最新视频，请稍后重试。"
                showTestNotificationResult = true
                return
            }

            // 中文注释：放入收件箱——若基线里已有该视频则重置为 pending，否则新建 pending 通知。
            if !store.resetNotificationToPending(subscriptionID: firstSub.id, videoId: video.videoId) {
                let notification = VideoNotification(
                    subscriptionID: firstSub.id,
                    channelTitle: firstSub.title,
                    videoId: video.videoId,
                    title: video.title,
                    publishedAt: video.publishedAt,
                    thumbnailURLString: video.thumbnailURLString,
                    videoURLString: video.videoURLString,
                    status: .pending
                )
                store.addNotification(notification)
            }
            load()

            // 中文注释：发送真实系统通知（前台也会弹横幅，靠 SystemNotificationService 的 delegate）。
            let channelTitle = firstSub.title
            notifier.sendTestNotification(channelTitle: channelTitle,
                                          videoTitle: video.title,
                                          videoURLString: video.videoURLString) { [weak self] success, reason in
                Task { @MainActor in
                    guard let self else { return }
                    if success {
                        self.testNotificationMessage = "已用「\(channelTitle)」的最新视频发送测试通知，并放入收件箱。\n若右上角未见横幅或没有声音，请检查：系统设置 → 通知 → Soluna（开启「允许通知」，样式选「横幅/提醒」，勾选「播放声音」），并关闭「勿扰/专注」模式。"
                    } else {
                        self.testNotificationMessage = reason ?? "测试通知发送失败，请检查系统通知权限。"
                    }
                    self.showTestNotificationResult = true
                }
            }
        } catch {
            testNotificationMessage = "测试通知失败：\(error.localizedDescription)"
            showTestNotificationResult = true
        }
    }

    // MARK: - 复制 / 打开

    /// 中文注释：复制视频链接到剪贴板；按设置可顺带标记为已处理（一步到位）。
    func copyLinkAndMaybeMark(id: UUID, urlString: String) {
        copyLink(urlString)
        if SubscriptionSettings.copyThenMarkHandled {
            markHandled(id: id)
        }
    }

    func copyLink(_ urlString: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
    }

    func openLink(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 中文注释：在浏览器中打开某订阅博主的主页（点击头像/标题触发）。
    func openChannel(_ subscription: ChannelSubscriptionSnapshot) {
        openLink(subscription.channelURLString)
    }
}
