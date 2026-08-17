//
//  SubscriptionPollingService.swift
//  Soluna
//

import Foundation
import os

/// 中文注释：检查结果里的单条视频，携带标题与链接，供 UI 复制/浏览器打开。
struct CheckedVideo: Sendable, Identifiable {
    let id = UUID()
    let title: String
    let videoURLString: String
    /// 中文注释：是否为本次新发现（此前收件箱没见过）。
    let isNew: Bool
}

/// 中文注释：单个频道一次检查的结果，供「立即检查」把检查内容反馈给 UI。
struct ChannelCheckOutcome: Sendable, Identifiable {
    let id = UUID()
    let subscriptionID: UUID
    let channelTitle: String
    /// 中文注释：本次从 RSS 抓到的视频总数。
    let fetchedCount: Int
    /// 中文注释：其中此前未见过、本次新增的视频数（会产生通知）。
    let newCount: Int
    /// 中文注释：抓到的最新若干视频（标题+链接+是否新），用于结果里直接展示与操作。
    let latestVideos: [CheckedVideo]
    /// 中文注释：出错信息，nil 表示成功。
    let errorMessage: String?
}

@MainActor
/// `SubscriptionPollingService` 的作用：按固定间隔在前台轮询所有订阅频道，发现新视频即建通知并可选发系统通知。
/// v1 仅前台轮询：App 退出即停止（符合桌面工具定位），后台常驻列入后续增强。
final class SubscriptionPollingService {
    private let store: SubscriptionStore
    private let notifier: SystemNotificationService
    private let logger = Logger(subsystem: "Soluna", category: "Polling")

    private var timer: Timer?
    private(set) var isPolling = false
    private(set) var lastPolledAt: Date?

    init(store: SubscriptionStore, notifier: SystemNotificationService) {
        self.store = store
        self.notifier = notifier
    }

    func start() {
        guard !isPolling else { return }
        isPolling = true
        scheduleNext(firstRun: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isPolling = false
    }

    /// 中文注释：错峰启动——首次延迟一个随机 0~30 秒，避免所有频道与多实例同时请求。
    private func scheduleNext(firstRun: Bool) {
        let interval = TimeInterval(max(1, SubscriptionSettings.pollIntervalMinutes) * 60)
        let delay = firstRun ? Double.random(in: 0...30) : interval
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.runOnce()
                self?.scheduleNext(firstRun: false)
            }
        }
    }

    /// 中文注释：手动触发一次轮询（立即检查按钮）。
    func runOnce() async {
        lastPolledAt = Date()
        let subscriptions = store.loadSubscriptions().filter { $0.isEnabled }
        guard !subscriptions.isEmpty else { return }

        let maxConcurrent = max(1, SubscriptionSettings.maxConcurrentFetches)
        var index = 0
        while index < subscriptions.count {
            let end = min(index + maxConcurrent, subscriptions.count)
            let batch = Array(subscriptions[index..<end])
            index = end

            // 中文注释：@Sendable 闭包只能捕获 Sendable 值；提取基础值并把 self 弱引用，避免捕获非 Sendable 的 @Model 实例。
            await withTaskGroup(of: Void.self) { group in
                for sub in batch {
                    let subscriptionID = sub.id
                    let channelId = sub.channelId
                    let title = sub.title
                    group.addTask { [weak self] in
                        await self?.pollSubscription(subscriptionID: subscriptionID, channelId: channelId, title: title)
                    }
                }
            }
            // 中文注释：批间短暂间隔，进一步降低触发限流的可能。
            if index < subscriptions.count {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// 中文注释：手动检测单个订阅（卡片上的「立即检查」按钮），返回检查结果供 UI 展示。
    @discardableResult
    func runOnce(subscriptionID: UUID) async -> ChannelCheckOutcome? {
        lastPolledAt = Date()
        guard let sub = store.loadSubscriptions().first(where: { $0.id == subscriptionID }) else { return nil }
        return await pollSubscription(subscriptionID: sub.id, channelId: sub.channelId, title: sub.title)
    }

    @discardableResult
    private func pollSubscription(subscriptionID: UUID, channelId: String, title: String) async -> ChannelCheckOutcome {
        do {
            let provider = RSSFeedProvider()
            let videos = try await provider.fetchLatestVideos(channelId: channelId, maxCount: 15)

            // 中文注释：RSS 官方源直接以抓取到的视频为准（已在上层按 Shorts/直播过滤），无需增量去重。
            let effectiveVideos = videos

            var newCount = 0
            var newVideoIds: Set<String> = []
            for video in effectiveVideos {
                // 中文注释：任意状态都已存在则跳过，保证同一视频只通知一次。
                if store.notificationExists(subscriptionID: subscriptionID, videoId: video.videoId) { continue }
                let notification = VideoNotification(
                    subscriptionID: subscriptionID,
                    channelTitle: title,
                    videoId: video.videoId,
                    title: video.title,
                    publishedAt: video.publishedAt,
                    thumbnailURLString: video.thumbnailURLString,
                    videoURLString: video.videoURLString
                )
                store.addNotification(notification)
                newCount += 1
                newVideoIds.insert(video.videoId)
                if SubscriptionSettings.notifyEnabled {
                    notifier.notifyNewVideo(channelTitle: title, videoTitle: video.title,
                                            videoURLString: video.videoURLString)
                }
            }
            store.updateSubscriptionChecked(id: subscriptionID, lastVideoId: videos.first?.videoId, errorMessage: nil)
            if newCount > 0 {
                logger.info("频道 \(title, privacy: .public) 发现 \(newCount) 条新视频")
            }
            // 中文注释：把抓到的最新若干条视频（标题+链接+是否新）返回给 UI，供直接查看/复制/打开。
            let latest = effectiveVideos.prefix(8).map { video in
                CheckedVideo(title: video.title,
                             videoURLString: video.videoURLString,
                             isNew: newVideoIds.contains(video.videoId))
            }
            return ChannelCheckOutcome(
                subscriptionID: subscriptionID,
                channelTitle: title,
                fetchedCount: videos.count,
                newCount: newCount,
                latestVideos: Array(latest),
                errorMessage: nil
            )
        } catch {
            store.updateSubscriptionChecked(id: subscriptionID, lastVideoId: nil, errorMessage: error.localizedDescription)
            logger.error("轮询频道失败 \(title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return ChannelCheckOutcome(
                subscriptionID: subscriptionID,
                channelTitle: title,
                fetchedCount: 0,
                newCount: 0,
                latestVideos: [],
                errorMessage: error.localizedDescription
            )
        }
    }
}
