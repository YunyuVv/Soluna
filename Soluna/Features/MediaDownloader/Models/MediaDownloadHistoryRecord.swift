//
//  MediaDownloadHistoryRecord.swift
//  Soluna
//
//  Created by Codex on 2026/5/28.
//

import Foundation
import SwiftData
import SwiftUI

/// `MediaDownloadHistoryStatus` 的作用：定义媒体下载历史记录的持久化状态。
enum MediaDownloadHistoryStatus: String, CaseIterable, Identifiable {
    case pending
    case running
    case success
    case failed
    case stopped
    case interrupted

    var id: String { rawValue }

    /// 中文注释：返回历史状态在界面中的展示标题。
    var title: String {
        switch self {
        case .pending: return "待下载"
        case .running: return "下载中"
        case .success: return "已完成"
        case .failed: return "失败"
        case .stopped: return "已停止"
        case .interrupted: return "已中断"
        }
    }

    /// 中文注释：返回历史状态对应的颜色样式。
    var color: Color {
        switch self {
        case .pending: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        case .stopped: return .gray
        case .interrupted: return .orange
        }
    }
}

@Model
/// `MediaDownloadHistoryRecord` 的作用：保存单次媒体下载的历史快照，用于跨次启动展示下载记录。
final class MediaDownloadHistoryRecord {
    @Attribute(.unique) var id: UUID
    var sourceURL: String
    var title: String
    var statusRawValue: String
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var outputFolderPath: String
    var outputFilePath: String?
    var thumbnailURLString: String?
    var extractorKey: String
    var fileExists: Bool
    var qualityRawValue: String
    var containerRawValue: String
    var audioOnly: Bool
    var useCustomFormat: Bool
    var customFormat: String
    var downloadSubtitles: Bool
    var downloadThumbnail: Bool
    var downloadMetadata: Bool
    var useBrowserCookies: Bool
    var browserCookieSourceRawValue: String
    var codecPreferenceRawValue: String
    var startTimecode: String?
    var endTimecode: String?
    var outputTemplate: String
    var useSiteSubfolder: Bool
    var finalProgress: Double
    var lastDownloadSpeed: String
    var errorSummary: String?
    var commandPreview: String?

    /// 中文注释：初始化一条完整的下载历史记录快照。
    init(
        id: UUID = UUID(),
        sourceURL: String,
        title: String,
        status: MediaDownloadHistoryStatus,
        createdAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        outputFolderPath: String,
        outputFilePath: String? = nil,
        thumbnailURLString: String? = nil,
        extractorKey: String,
        fileExists: Bool = false,
        qualityRawValue: String,
        containerRawValue: String,
        audioOnly: Bool,
        useCustomFormat: Bool,
        customFormat: String,
        downloadSubtitles: Bool,
        downloadThumbnail: Bool,
        downloadMetadata: Bool,
        useBrowserCookies: Bool,
        browserCookieSourceRawValue: String,
        codecPreferenceRawValue: String,
        startTimecode: String? = nil,
        endTimecode: String? = nil,
        outputTemplate: String,
        useSiteSubfolder: Bool,
        finalProgress: Double = 0,
        lastDownloadSpeed: String = "",
        errorSummary: String? = nil,
        commandPreview: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outputFolderPath = outputFolderPath
        self.outputFilePath = outputFilePath
        self.thumbnailURLString = thumbnailURLString
        self.extractorKey = extractorKey
        self.fileExists = fileExists
        self.qualityRawValue = qualityRawValue
        self.containerRawValue = containerRawValue
        self.audioOnly = audioOnly
        self.useCustomFormat = useCustomFormat
        self.customFormat = customFormat
        self.downloadSubtitles = downloadSubtitles
        self.downloadThumbnail = downloadThumbnail
        self.downloadMetadata = downloadMetadata
        self.useBrowserCookies = useBrowserCookies
        self.browserCookieSourceRawValue = browserCookieSourceRawValue
        self.codecPreferenceRawValue = codecPreferenceRawValue
        self.startTimecode = startTimecode
        self.endTimecode = endTimecode
        self.outputTemplate = outputTemplate
        self.useSiteSubfolder = useSiteSubfolder
        self.finalProgress = finalProgress
        self.lastDownloadSpeed = lastDownloadSpeed
        self.errorSummary = errorSummary
        self.commandPreview = commandPreview
    }

    /// 中文注释：把原始状态字符串转换为强类型状态，异常值时回退到失败。
    var status: MediaDownloadHistoryStatus {
        get { MediaDownloadHistoryStatus(rawValue: statusRawValue) ?? .failed }
        set { statusRawValue = newValue.rawValue }
    }

    /// 中文注释：返回历史记录用于展示的标题，缺失时回退为原始链接。
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sourceURL : trimmed
    }

    /// 中文注释：把缩略图字符串转换为 `URL` 供界面直接使用。
    var thumbnailURL: URL? {
        guard let thumbnailURLString else { return nil }
        return URL(string: thumbnailURLString)
    }

    /// 中文注释：把输出文件路径转换为文件 URL。
    var outputFileURL: URL? {
        guard let outputFilePath, outputFilePath.isEmpty == false else { return nil }
        return URL(fileURLWithPath: outputFilePath)
    }

    /// 中文注释：把输出目录路径转换为目录 URL。
    var outputFolderURL: URL? {
        guard outputFolderPath.isEmpty == false else { return nil }
        return URL(fileURLWithPath: outputFolderPath)
    }

    /// 中文注释：返回解析后的清晰度选项，异常值时回退为最佳画质。
    var qualityOption: VideoQualityOption {
        VideoQualityOption(rawValue: qualityRawValue) ?? .best
    }

    /// 中文注释：返回解析后的容器选项，异常值时回退为自动。
    var containerOption: VideoContainerOption {
        VideoContainerOption(rawValue: containerRawValue) ?? .auto
    }

    /// 中文注释：返回解析后的浏览器 Cookie 来源，异常值时回退为 Safari。
    var browserCookieSource: BrowserCookieSource {
        BrowserCookieSource(rawValue: browserCookieSourceRawValue) ?? .safari
    }

    /// 中文注释：返回解析后的视频编码偏好，异常值时回退为源格式。
    var codecPreference: VideoCodecPreference {
        VideoCodecPreference(rawValue: codecPreferenceRawValue) ?? .source
    }
}
