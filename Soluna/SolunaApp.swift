//
//  SolunaApp.swift
//  Soluna
//
//  Created by Codex on 2026/6/9.
//

import SwiftUI
import SwiftData

@main
/// `SolunaApp` 的作用：作为 Soluna 应用入口，初始化媒体下载历史存储并展示主窗口。
struct SolunaApp: App {
    var sharedModelContainer: ModelContainer = {
        // 中文注释：主 schema 包含全部持久化类型。
        let schema = Schema([
            MediaDownloadHistoryRecord.self,
            ChannelSubscription.self,
            VideoNotification.self,
        ])
        // 中文注释：下载历史与订阅数据分别落到独立 store，避免相互迁移影响。
        let historyConfig = ModelConfiguration(
            "MediaDownloadHistory",
            schema: Schema([MediaDownloadHistoryRecord.self]),
            url: Self.mediaDownloadHistoryStoreURL()
        )
        let subscriptionConfig = ModelConfiguration(
            "Subscription",
            schema: Schema([ChannelSubscription.self, VideoNotification.self]),
            url: Self.subscriptionStoreURL()
        )

        do {
            return try ModelContainer(for: schema, configurations: [historyConfig, subscriptionConfig])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// 中文注释：返回下载历史数据库的稳定存储路径，避免开发调试时隐式容器位置变化。
    private static func mediaDownloadHistoryStoreURL() -> URL {
        let fileManager = FileManager.default
        do {
            let supportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appDirectoryURL = supportURL.appendingPathComponent("Soluna", isDirectory: true)
            try fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true)
            return appDirectoryURL.appendingPathComponent("MediaDownloadHistory.store")
        } catch {
            return fileManager.temporaryDirectory.appendingPathComponent("MediaDownloadHistory.store")
        }
    }

    /// 中文注释：返回订阅数据库的存储路径，与下载历史库位于同一 Application Support 目录但独立文件。
    private static func subscriptionStoreURL() -> URL {
        let fileManager = FileManager.default
        do {
            let supportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appDirectoryURL = supportURL.appendingPathComponent("Soluna", isDirectory: true)
            try fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true)
            return appDirectoryURL.appendingPathComponent("Subscription.store")
        } catch {
            return fileManager.temporaryDirectory.appendingPathComponent("Subscription.store")
        }
    }

    /// 中文注释：构建 Soluna 的单窗口媒体下载应用场景。
    var body: some Scene {
        WindowGroup("媒体下载") {
            MediaDownloaderWindow()
        }
        .defaultSize(width: 1_200, height: 760)
        .windowResizability(.contentMinSize)
        .modelContainer(sharedModelContainer)

        // 中文注释：统一设置窗口，⌘, 打开；整合订阅与下载配置。
        Settings {
            AppSettingsView()
        }
    }
}
