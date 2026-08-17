//
//  SubscriptionSettings.swift
//  Soluna
//

import Foundation

/// `SubscriptionSettings` 的作用：集中管理 YouTube 订阅功能的 UserDefaults 配置项。
enum SubscriptionSettings {
    static let pollIntervalKey = "yt_subscription_poll_interval_minutes"
    static let maxConcurrentKey = "yt_subscription_max_concurrent"
    static let notifyEnabledKey = "yt_subscription_notify_enabled"
    static let copyThenMarkKey = "yt_subscription_copy_then_mark"
    static let ignoreShortsKey = "yt_subscription_ignore_shorts"
    static let ignoreLiveKey = "yt_subscription_ignore_live"

    /// 中文注释：轮询间隔（分钟），默认 30 分钟，兼顾及时性与低频防限流。
    static var pollIntervalMinutes: Int {
        get { UserDefaults.standard.object(forKey: pollIntervalKey) as? Int ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: pollIntervalKey) }
    }

    /// 中文注释：并发检查频道数，默认 3，避免一次性请求过多触发限流。
    static var maxConcurrentFetches: Int {
        get { UserDefaults.standard.object(forKey: maxConcurrentKey) as? Int ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: maxConcurrentKey) }
    }

    /// 中文注释：是否发送系统通知，默认开启。
    static var notifyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: notifyEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifyEnabledKey) }
    }

    /// 中文注释：复制下载链接后是否自动标记为已处理，默认开启（一步到位）。
    static var copyThenMarkHandled: Bool {
        get { UserDefaults.standard.object(forKey: copyThenMarkKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: copyThenMarkKey) }
    }

    /// 中文注释：是否忽略 Shorts（短视频），默认开启——RSS 常混入 Shorts，多数用户不关心。
    static var ignoreShorts: Bool {
        get { UserDefaults.standard.object(forKey: ignoreShortsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: ignoreShortsKey) }
    }

    /// 中文注释：是否忽略直播/首播，默认关闭——按标题特征尽力识别。
    static var ignoreLive: Bool {
        get { UserDefaults.standard.object(forKey: ignoreLiveKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: ignoreLiveKey) }
    }
}
