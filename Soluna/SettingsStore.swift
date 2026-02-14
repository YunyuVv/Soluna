//
//  SettingsStore.swift
//  Soluna
//

import Observation

/// Cookie 选项。
enum CookieMode: String, CaseIterable, Identifiable {
    case none
    case file
    case browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不使用"
        case .file: return "Cookie 文件"
        case .browser: return "浏览器"
        }
    }
}

/// 支持的浏览器。
enum BrowserType: String, CaseIterable, Identifiable {
    case chrome
    case safari
    case firefox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chrome: return "Chrome"
        case .safari: return "Safari"
        case .firefox: return "Firefox"
        }
    }

    var ytDlpValue: String {
        switch self {
        case .chrome: return "chrome"
        case .safari: return "safari"
        case .firefox: return "firefox"
        }
    }
}

/// 应用设置。
@MainActor
@Observable
final class SettingsStore {
    // 默认下载目录。
    var downloadDirectory: String = "/Users/wangpenglong/Downloads"
    // Cookie 选择模式。
    var cookieMode: CookieMode = .none
    // Cookie 文件路径（当 cookieMode = .file）。
    var cookieFilePath: String = ""
    // 浏览器类型（当 cookieMode = .browser）。
    var browserType: BrowserType = .chrome
}
