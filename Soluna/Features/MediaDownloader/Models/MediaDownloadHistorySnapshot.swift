//
//  MediaDownloadHistorySnapshot.swift
//  Soluna
//
//  Created by Codex on 2026/6/7.
//

import Foundation

/// `MediaDownloadHistorySnapshot` 的作用：把 SwiftData 历史记录转换为稳定值类型，供界面展示和交互使用。
struct MediaDownloadHistorySnapshot: Identifiable, Hashable {
    let id: UUID
    let sourceURL: String
    let title: String
    let statusRawValue: String
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let outputFolderPath: String
    let outputFilePath: String?
    let thumbnailURLString: String?
    let extractorKey: String
    let fileExists: Bool
    let qualityRawValue: String
    let containerRawValue: String
    let audioOnly: Bool
    let useCustomFormat: Bool
    let customFormat: String
    let downloadSubtitles: Bool
    let downloadThumbnail: Bool
    let downloadMetadata: Bool
    let useBrowserCookies: Bool
    let browserCookieSourceRawValue: String
    let codecPreferenceRawValue: String
    let startTimecode: String?
    let endTimecode: String?
    let outputTemplate: String
    let useSiteSubfolder: Bool
    let finalProgress: Double
    let lastDownloadSpeed: String
    let errorSummary: String?
    let commandPreview: String?

    /// 中文注释：从 SwiftData 模型创建展示快照，避免界面层长期持有持久化对象。
    init(record: MediaDownloadHistoryRecord) {
        self.id = record.id
        self.sourceURL = record.sourceURL
        self.title = record.title
        self.statusRawValue = record.statusRawValue
        self.createdAt = record.createdAt
        self.startedAt = record.startedAt
        self.finishedAt = record.finishedAt
        self.outputFolderPath = record.outputFolderPath
        self.outputFilePath = record.outputFilePath
        self.thumbnailURLString = record.thumbnailURLString
        self.extractorKey = record.extractorKey
        self.fileExists = record.fileExists
        self.qualityRawValue = record.qualityRawValue
        self.containerRawValue = record.containerRawValue
        self.audioOnly = record.audioOnly
        self.useCustomFormat = record.useCustomFormat
        self.customFormat = record.customFormat
        self.downloadSubtitles = record.downloadSubtitles
        self.downloadThumbnail = record.downloadThumbnail
        self.downloadMetadata = record.downloadMetadata
        self.useBrowserCookies = record.useBrowserCookies
        self.browserCookieSourceRawValue = record.browserCookieSourceRawValue
        self.codecPreferenceRawValue = record.codecPreferenceRawValue
        self.startTimecode = record.startTimecode
        self.endTimecode = record.endTimecode
        self.outputTemplate = record.outputTemplate
        self.useSiteSubfolder = record.useSiteSubfolder
        self.finalProgress = record.finalProgress
        self.lastDownloadSpeed = record.lastDownloadSpeed
        self.errorSummary = record.errorSummary
        self.commandPreview = record.commandPreview
    }

    /// 中文注释：把原始状态字符串转换为强类型状态，异常值时回退到失败。
    var status: MediaDownloadHistoryStatus {
        MediaDownloadHistoryStatus(rawValue: statusRawValue) ?? .failed
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
