//
//  MediaDownloaderTask.swift
//  Soluna
//
//  Created by Codex on 2026/3/15.
//

import Foundation
import SwiftUI

/// `MediaDownloaderTaskStatus` 的作用：定义下载任务的生命周期状态。
enum MediaDownloaderTaskStatus: String, CaseIterable, Identifiable {
    case pending
    case running
    case success
    case failed
    case stopped

    var id: String { rawValue }

    /// 中文注释：返回状态展示名称。
    var title: String {
        switch self {
        case .pending: return "待下载"
        case .running: return "下载中"
        case .success: return "已完成"
        case .failed: return "失败"
        case .stopped: return "已停止"
        }
    }

    /// 中文注释：返回状态对应的颜色样式。
    var color: Color {
        switch self {
        case .pending: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        case .stopped: return .gray
        }
    }
}

/// `MediaDownloaderTask` 的作用：承载单个下载任务的基础信息与状态。
struct MediaDownloaderTask: Identifiable, Equatable {
    let id: UUID
    var url: String
    var title: String
    var status: MediaDownloaderTaskStatus
    var progress: Double
    var logText: String
    var createdAt: Date
    var quality: VideoQualityOption
    var container: VideoContainerOption
    var audioOnly: Bool
    var useCustomFormat: Bool
    var customFormat: String
    var downloadSubtitles: Bool
    var downloadThumbnail: Bool
    var downloadMetadata: Bool
    var useBrowserCookies: Bool
    var browserCookieSource: BrowserCookieSource
    var codecPreference: VideoCodecPreference
    var startTimecode: String?
    var endTimecode: String?
    var downloadSpeed: String
    var outputFileURL: URL?
    var thumbnailURL: URL?

    /// 中文注释：初始化任务并注入默认状态。
    init(
        url: String,
        quality: VideoQualityOption,
        container: VideoContainerOption,
        audioOnly: Bool,
        useCustomFormat: Bool,
        customFormat: String,
        downloadSubtitles: Bool,
        downloadThumbnail: Bool,
        downloadMetadata: Bool,
        useBrowserCookies: Bool,
        browserCookieSource: BrowserCookieSource,
        codecPreference: VideoCodecPreference,
        startTimecode: String? = nil,
        endTimecode: String? = nil,
        downloadSpeed: String = "",
        outputFileURL: URL? = nil,
        thumbnailURL: URL? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.title = url
        self.status = .pending
        self.progress = 0
        self.logText = ""
        self.createdAt = Date()
        self.quality = quality
        self.container = container
        self.audioOnly = audioOnly
        self.useCustomFormat = useCustomFormat
        self.customFormat = customFormat
        self.downloadSubtitles = downloadSubtitles
        self.downloadThumbnail = downloadThumbnail
        self.downloadMetadata = downloadMetadata
        self.useBrowserCookies = useBrowserCookies
        self.browserCookieSource = browserCookieSource
        self.codecPreference = codecPreference
        self.startTimecode = startTimecode
        self.endTimecode = endTimecode
        self.downloadSpeed = downloadSpeed
        self.outputFileURL = outputFileURL
        self.thumbnailURL = thumbnailURL
    }
}
