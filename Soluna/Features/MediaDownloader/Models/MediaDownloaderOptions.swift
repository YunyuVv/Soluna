//
//  MediaDownloaderOptions.swift
//  Soluna
//
//  Created by Codex on 2026/3/15.
//

import Foundation

/// `BrowserCookieSource` 的作用：定义可选的浏览器 Cookie 来源。
enum BrowserCookieSource: String, CaseIterable, Identifiable {
    case safari
    case chrome
    case edge

    var id: String { rawValue }

    /// 中文注释：返回浏览器名称，用于界面展示。
    var title: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .edge: return "Edge"
        }
    }

    /// 中文注释：返回传递给 yt-dlp 的浏览器参数值。
    var argumentValue: String {
        switch self {
        case .safari: return "safari"
        case .chrome: return "chrome"
        case .edge: return "edge"
        }
    }
}

/// `VideoQualityOption` 的作用：定义可选的视频清晰度档位。
enum VideoQualityOption: String, CaseIterable, Identifiable {
    case best
    case q8k
    case q4k
    case q1440
    case q1080
    case q720
    case q480
    case q360
    case q240

    var id: String { rawValue }

    /// 中文注释：返回清晰度展示名称。
    var title: String {
        switch self {
        case .best: return "最佳画质"
        case .q8k: return "8K"
        case .q4k: return "4K"
        case .q1440: return "2K"
        case .q1080: return "1080p"
        case .q720: return "720p"
        case .q480: return "480p"
        case .q360: return "360p"
        case .q240: return "240p"
        }
    }

    /// 中文注释：返回清晰度对应的最大高度限制。
    var maxHeight: Int? {
        switch self {
        case .best: return nil
        case .q8k: return 4320
        case .q4k: return 2160
        case .q1440: return 1440
        case .q1080: return 1080
        case .q720: return 720
        case .q480: return 480
        case .q360: return 360
        case .q240: return 240
        }
    }
}

/// `VideoContainerOption` 的作用：定义可选的视频封装格式。
enum VideoContainerOption: String, CaseIterable, Identifiable {
    case auto
    case mp4
    case mkv
    case webm
    case mp3

    var id: String { rawValue }

    /// 中文注释：返回封装格式展示名称。
    var title: String {
        switch self {
        case .auto: return "自动"
        case .mp4: return "MP4"
        case .mkv: return "MKV"
        case .webm: return "WEBM"
        case .mp3: return "MP3"
        }
    }
}

/// `VideoCodecPreference` 的作用：定义视频编码偏好选项。
enum VideoCodecPreference: String, CaseIterable, Identifiable {
    case source
    case h264

    var id: String { rawValue }

    /// 中文注释：返回编码偏好展示名称。
    var title: String {
        switch self {
        case .source: return "原画质"
        case .h264: return "H.264 兼容"
        }
    }
}

/// `MediaDownloaderSettings` 的作用：集中管理下载功能的 UserDefaults 配置项。
enum MediaDownloaderSettings {
    static let downloadNotifyKey = "yt_downloader_notify_enabled"

    /// 中文注释：下载完成/失败时是否发送系统通知，默认开启。
    static var downloadNotifyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: downloadNotifyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: downloadNotifyKey) }
    }
}
