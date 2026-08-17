//
//  MediaDownloaderViewModel.swift
//  Soluna
//
//  Created by Codex on 2026/3/15.
//

import Foundation
import Observation
import AppKit
import os
import SwiftData

/// `CommandLogEntry` 的作用：记录单条 yt-dlp 命令日志。
struct CommandLogEntry: Identifiable, Equatable {
    let id: UUID = UUID()
    let timestamp: Date
    let type: String
    let message: String
}

@MainActor
@Observable
/// `MediaDownloaderViewModel` 的作用：管理媒体下载窗口的状态、yt-dlp 检测与下载流程。
final class MediaDownloaderViewModel: @unchecked Sendable {
    private let logger = Logger(subsystem: "Soluna", category: "MediaDownloader")
    var urlText: String = ""
    var outputFolderURL: URL?
    var outputFolderDisplay: String = ""
    var isYtDlpAvailable: Bool = false
    var ytDlpPath: String?
    var ytDlpVersion: String = "未检测"
    var statusMessage: String = ""
    var isError: Bool = false

    var selectedQuality: VideoQualityOption {
        didSet {
            UserDefaults.standard.set(selectedQuality.rawValue, forKey: selectedQualityKey)
        }
    }

    var selectedContainer: VideoContainerOption {
        didSet {
            UserDefaults.standard.set(selectedContainer.rawValue, forKey: selectedContainerKey)
        }
    }

    /// 中文注释：视频编码偏好设置。
    var codecPreference: VideoCodecPreference {
        didSet {
            UserDefaults.standard.set(codecPreference.rawValue, forKey: codecPreferenceKey)
        }
    }

    var audioOnly: Bool {
        didSet {
            UserDefaults.standard.set(audioOnly, forKey: audioOnlyKey)
        }
    }

    var useBrowserCookies: Bool {
        didSet {
            UserDefaults.standard.set(useBrowserCookies, forKey: useBrowserCookiesKey)
        }
    }

    /// 中文注释：下载起始时间输入（自动格式化为 HH:MM:SS）。
    var startTimeInput: String = ""

    /// 中文注释：下载结束时间输入（自动格式化为 HH:MM:SS）。
    var endTimeInput: String = ""

    var browserCookieSource: BrowserCookieSource {
        didSet {
            UserDefaults.standard.set(browserCookieSource.rawValue, forKey: browserCookieSourceKey)
        }
    }

    var downloadSubtitles: Bool {
        didSet {
            UserDefaults.standard.set(downloadSubtitles, forKey: downloadSubtitlesKey)
        }
    }

    var downloadThumbnail: Bool {
        didSet {
            UserDefaults.standard.set(downloadThumbnail, forKey: downloadThumbnailKey)
        }
    }

    var downloadMetadata: Bool {
        didSet {
            UserDefaults.standard.set(downloadMetadata, forKey: downloadMetadataKey)
        }
    }

    var useSiteSubfolder: Bool {
        didSet {
            UserDefaults.standard.set(useSiteSubfolder, forKey: useSiteSubfolderKey)
        }
    }

    var outputTemplate: String {
        didSet {
            UserDefaults.standard.set(outputTemplate, forKey: outputTemplateKey)
        }
    }

    var customFormat: String {
        didSet {
            UserDefaults.standard.set(customFormat, forKey: customFormatKey)
        }
    }

    var useCustomFormat: Bool {
        didSet {
            UserDefaults.standard.set(useCustomFormat, forKey: useCustomFormatKey)
        }
    }

    var tasks: [MediaDownloaderTask] = []
    /// 中文注释：持久化后的下载历史记录列表，按时间倒序展示。
    var historyRecords: [MediaDownloadHistorySnapshot] = []
    /// 中文注释：下载历史搜索关键字，支持按标题、链接和站点名模糊匹配。
    var historySearchText: String = ""
    /// 中文注释：下载历史的状态筛选条件。
    var historyStatusFilter: MediaDownloadHistoryFilter = .all
    /// 中文注释：下载历史的时间范围筛选条件。
    var historyTimeRangeFilter: MediaDownloadHistoryTimeRangeFilter = .all
    /// 中文注释：下载历史的站点快速筛选条件，默认展示全部站点。
    var historySiteFilterID: String = MediaDownloadHistorySiteOption.all.id

    // MARK: - 分页相关
    /// 中文注释：当前已加载到的页码（从 0 开始），配合分页加载使用。
    var historyCurrentPage: Int = 0
    /// 中文注释：每页加载的历史记录条数。
    var historyPageSize: Int = 50
    /// 中文注释：是否还有更多历史记录可加载。
    var historyHasMore: Bool = false
    /// 中文注释：是否正在加载更多历史记录（显示加载指示器）。
    var historyIsLoadingMore: Bool = false
    /// 中文注释：历史记录总条数。
    var historyTotalCount: Int = 0

    // MARK: - 批量操作相关
    /// 中文注释：批量模式下已选中的历史记录 ID 集合。
    var selectedHistoryIDs: Set<UUID> = []
    /// 中文注释：是否处于批量操作模式，切换后自动清空已选集合。
    var isHistoryBatchMode: Bool = false {
        didSet {
            if isHistoryBatchMode == false {
                selectedHistoryIDs.removeAll()
            }
        }
    }
    var selectedTaskID: UUID?
    var isQueueRunning: Bool = false
    /// 中文注释：yt-dlp 命令日志（最多保留 1000 行）。
    var commandLogs: [CommandLogEntry] = []
    /// 中文注释：控制命令日志最大条数。
    private let commandLogLimit: Int = 1000
    /// 中文注释：控制任务日志最大条数（不包含命令行）。
    private let taskLogLimit: Int = 2000
    /// 中文注释：任务日志的命令头部文本。
    private let logCommandPrefix = "[命令]"
    /// 中文注释：每次更新日志行的批量上限。
    private let logAppendBatchLimit: Int = 50
    /// 中文注释：任务日志按行缓存（用于增量渲染）。
    var taskLogLinesCache: [UUID: [String]] = [:]

    private var runningProcesses: [UUID: Process] = [:]
    private var didRequestStopTaskIDs: Set<UUID> = []
    private let maxConcurrentDownloads: Int = 3
    private var speedSampleTasks: [UUID: Task<Void, Never>] = [:]
    private var speedSampleStates: [UUID: SpeedSampleState] = [:]
    private var historyStore: MediaDownloadHistoryStore?
    /// 中文注释：复用订阅侧封装的本地通知服务，下载完成/失败时发送系统通知。
    private let notifier = SystemNotificationService()
    /// 中文注释：记录当前队列任务与历史记录主键的映射，保证一次下载对应一条历史快照。
    private var taskHistoryRecordIDs: [UUID: UUID] = [:]

    private let audioOnlyKey = "media_downloader_audio_only"
    private let useBrowserCookiesKey = "media_downloader_use_browser_cookies"
    private let browserCookieSourceKey = "media_downloader_browser_cookie_source"
    private let downloadSubtitlesKey = "media_downloader_download_subtitles"
    private let downloadThumbnailKey = "media_downloader_download_thumbnail"
    private let downloadMetadataKey = "media_downloader_download_metadata"
    private let useSiteSubfolderKey = "media_downloader_use_site_subfolder"
    private let outputTemplateKey = "media_downloader_output_template"
    private let customFormatKey = "media_downloader_custom_format"
    private let useCustomFormatKey = "media_downloader_use_custom_format"
    private let selectedQualityKey = "media_downloader_selected_quality"
    private let selectedContainerKey = "media_downloader_selected_container"
    private let codecPreferenceKey = "media_downloader_codec_preference"
    private let outputFolderPathKey = "media_downloader_output_folder_path"

    /// `SpeedSampleState` 的作用：记录上一次采样的文件大小与时间。
    private struct SpeedSampleState {
        let url: URL
        let lastBytes: Int64
        let lastTime: Date
        let recentSpeeds: [Double]
        let stallCount: Int
    }

    /// 中文注释：初始化默认输出目录并进行 yt-dlp 检测。
    init() {
        let defaults = UserDefaults.standard
        audioOnly = defaults.bool(forKey: audioOnlyKey)
        useBrowserCookies = defaults.bool(forKey: useBrowserCookiesKey)
        if let raw = defaults.string(forKey: browserCookieSourceKey), let source = BrowserCookieSource(rawValue: raw) {
            browserCookieSource = source
        } else {
            browserCookieSource = .safari
        }
        downloadSubtitles = defaults.bool(forKey: downloadSubtitlesKey)
        downloadThumbnail = defaults.bool(forKey: downloadThumbnailKey)
        downloadMetadata = defaults.bool(forKey: downloadMetadataKey)
        useSiteSubfolder = defaults.bool(forKey: useSiteSubfolderKey)
        outputTemplate = defaults.string(forKey: outputTemplateKey) ?? "%(title)s.%(ext)s"
        customFormat = defaults.string(forKey: customFormatKey) ?? ""
        useCustomFormat = defaults.bool(forKey: useCustomFormatKey)
        if let raw = defaults.string(forKey: selectedQualityKey), let quality = VideoQualityOption(rawValue: raw) {
            selectedQuality = quality
        } else {
            selectedQuality = .best
        }
        if let raw = defaults.string(forKey: selectedContainerKey), let container = VideoContainerOption(rawValue: raw) {
            selectedContainer = container
        } else {
            selectedContainer = .auto
        }
        if let raw = defaults.string(forKey: codecPreferenceKey), let preference = VideoCodecPreference(rawValue: raw) {
            codecPreference = preference
        } else {
            codecPreference = .source
        }

        // 中文注释：初始化时设置默认输出目录并检测 yt-dlp。
        prepareDefaultOutputFolder()
        refreshYtDlpStatus()
    }

    /// 中文注释：刷新 yt-dlp 可用性检测结果并更新展示状态。
    func refreshYtDlpStatus() {
        ytDlpPath = ExecutableLocator.find(named: "yt-dlp")
        isYtDlpAvailable = ytDlpPath != nil
        if ytDlpPath != nil {
            publishStatus("已检测到 yt-dlp", isError: false)
            refreshYtDlpVersion()
        } else {
            ytDlpVersion = "未检测"
            publishStatus("未检测到 yt-dlp", isError: true)
        }
    }

    /// 中文注释：刷新 yt-dlp 版本信息。
    func refreshYtDlpVersion() {
        guard let ytDlpPath else {
            ytDlpVersion = "未检测"
            return
        }
        ytDlpVersion = ExecutableLocator.version(of: ytDlpPath) ?? "检测失败"
    }

    /// 中文注释：注入 `SwiftData` 上下文并初始化下载历史数据。
    func configurePersistence(modelContext: ModelContext) {
        if historyStore == nil {
            historyStore = MediaDownloadHistoryStore(modelContext: modelContext)
            historyStore?.markInterruptedRecordsIfNeeded()
        }
        reloadHistory()
    }

    /// 中文注释：从持久化存储中重新加载下载历史列表（重置到第 0 页，清空已有数据）。
    func reloadHistory() {
        historyCurrentPage = 0
        historyIsLoadingMore = false
        guard let store = historyStore else { return }
        historyRecords = store.loadRecords(page: 0, pageSize: historyPageSize)
        let total = store.totalRecordCount()
        historyTotalCount = total
        historyHasMore = historyRecords.count < total
    }

    /// 中文注释：加载下一页历史记录，追加到当前列表末尾。
    func loadMoreHistory() {
        guard historyHasMore, historyIsLoadingMore == false, let store = historyStore else { return }
        historyIsLoadingMore = true
        let nextPage = historyCurrentPage + 1
        let more = store.loadRecords(page: nextPage, pageSize: historyPageSize)
        if more.isEmpty {
            historyHasMore = false
        } else {
            historyRecords.append(contentsOf: more)
            historyCurrentPage = nextPage
            let total = store.totalRecordCount()
            historyTotalCount = total
            historyHasMore = historyRecords.count < total
        }
        historyIsLoadingMore = false
    }

    /// 中文注释：返回应用搜索和状态筛选后的历史记录列表。
    var filteredHistoryRecords: [MediaDownloadHistorySnapshot] {
        let keyword = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return historyRecords.filter { record in
            guard historyStatusFilter.matches(record.status) else { return false }
            guard historyTimeRangeFilter.matches(record.createdAt) else { return false }
            guard historySiteFilterID == MediaDownloadHistorySiteOption.all.id || record.extractorKey == historySiteFilterID else { return false }
            guard keyword.isEmpty == false else { return true }
            return record.displayTitle.lowercased().contains(keyword)
                || record.sourceURL.lowercased().contains(keyword)
                || record.extractorKey.lowercased().contains(keyword)
        }
    }

    /// 中文注释：返回历史记录中可用的站点筛选选项，首项固定为“全部站点”。
    var historySiteOptions: [MediaDownloadHistorySiteOption] {
        let siteIDs = Set(historyRecords.map(\.extractorKey))
        let sortedOptions = siteIDs
            .sorted()
            .map { MediaDownloadHistorySiteOption(id: $0, title: $0) }
        return [MediaDownloadHistorySiteOption.all] + sortedOptions
    }

    /// 中文注释：返回当前已启用的筛选标签标题列表，供界面显示统计标签。
    var activeHistoryFilterTags: [String] {
        var tags: [String] = []
        if historyStatusFilter != .all {
            tags.append(historyStatusFilter.title)
        }
        if historyTimeRangeFilter != .all {
            tags.append(historyTimeRangeFilter.title)
        }
        if historySiteFilterID != MediaDownloadHistorySiteOption.all.id,
           let siteOption = historySiteOptions.first(where: { $0.id == historySiteFilterID }) {
            tags.append(siteOption.title)
        }
        let keyword = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty == false {
            tags.append("关键词: \(keyword)")
        }
        return tags
    }

    /// 中文注释：更新输出目录并同步展示文本。
    func updateOutputFolder(_ url: URL?) {
        outputFolderURL = url
        outputFolderDisplay = url?.path ?? ""
        if let url {
            UserDefaults.standard.set(url.path, forKey: outputFolderPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: outputFolderPathKey)
        }
    }

    /// 中文注释：打开当前输出目录。
    func openOutputFolder() {
        guard let url = outputFolderURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 中文注释：打开指定任务对应文件所在目录，优先定位到真实文件，其次回退到推断目录。
    func openFolder(for task: MediaDownloaderTask) {
        if let fileURL = resolveDeleteFileURL(for: task) {
            let resolvedURL = fileURL.hasDirectoryPath ? fileURL : fileURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                return
            }
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                NSWorkspace.shared.open(resolvedURL)
                return
            }
        }

        if let inferredFileURL = inferOutputFileURL(for: task) {
            let folderURL = inferredFileURL.deletingLastPathComponent()
            NSWorkspace.shared.open(folderURL)
            return
        }

        openOutputFolder()
    }

    /// 中文注释：打开指定历史记录对应文件所在目录，优先定位到真实文件，其次回退到输出目录。
    func openFolder(for historyRecord: MediaDownloadHistorySnapshot) {
        if let fileURL = historyRecord.outputFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return
        }

        if let outputFolderURL = historyRecord.outputFolderURL, FileManager.default.fileExists(atPath: outputFolderURL.path) {
            NSWorkspace.shared.open(outputFolderURL)
            return
        }

        openOutputFolder()
    }

    /// 中文注释：返回队列任务可用于播放的本地媒体文件路径，排除仍在下载的临时文件。
    func playableFileURL(for task: MediaDownloaderTask) -> URL? {
        if let fileURL = existingPlayableFileURL(task.outputFileURL) {
            return fileURL
        }
        if let inferredFileURL = inferOutputFileURL(for: task),
           let fileURL = existingPlayableFileURL(inferredFileURL) {
            return fileURL
        }
        publishStatus("未找到可播放的本地文件", isError: true)
        return nil
    }

    /// 中文注释：返回历史记录可用于播放的本地媒体文件路径。
    func playableFileURL(for historyRecord: MediaDownloadHistorySnapshot) -> URL? {
        if let fileURL = existingPlayableFileURL(historyRecord.outputFileURL) {
            return fileURL
        }
        publishStatus("历史记录关联的本地文件不存在，无法播放", isError: true)
        return nil
    }

    // MARK: - 播放兼容性处理（WebM 等 AVFoundation 不支持的格式）

    /// 中文注释：播放路由——决定某个本地文件应如何播放。
    enum MediaPlaybackRoute {
        case inApp(URL)                     // 应用内 AVPlayer 直接播放
        case external(appURL: URL, fileURL: URL) // 调用外部播放器（IINA/VLC）
        case unsupported                    // 无任何可用播放途径，需提示安装播放器
    }

    /// 中文注释：返回该文件应走哪条播放路径。原生格式应用内播放；不支持的格式若有第三方
    /// 播放器（IINA/VLC）则调用之；否则提示安装播放器（不在应用内转码，避免转码耗时）。
    func playbackRoute(for fileURL: URL) -> MediaPlaybackRoute {
        if avFoundationCanPlay(fileURL) {
            return .inApp(fileURL)
        }
        if let appURL = ExternalPlayerLocator.find() {
            return .external(appURL: appURL, fileURL: fileURL)
        }
        return .unsupported
    }

    /// 中文注释：AVFoundation 在 macOS 原生可解码的容器/编码（WebM/VP8/VP9 不在其中）。
    private static let avFoundationPlayableExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mp3", "m4a", "aac", "wav", "caf", "aiff", "aif"
    ]

    /// 中文注释：判断文件是否可由系统 AVPlayer 直接播放。
    func avFoundationCanPlay(_ url: URL) -> Bool {
        Self.avFoundationPlayableExtensions.contains(url.pathExtension.lowercased())
    }

    /// 中文注释：打开历史记录关联的原始下载网址。
    func openSourceURL(for historyRecord: MediaDownloadHistorySnapshot) {
        guard let url = URL(string: historyRecord.sourceURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 中文注释：复制历史记录的原始下载网址到剪贴板。
    func copySourceURL(for historyRecord: MediaDownloadHistorySnapshot) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(historyRecord.sourceURL, forType: .string)
    }

    /// 中文注释：下载当前队列任务的封面图片，优先使用已解析的缩略图地址。
    /// 封面保存目录与视频下载目录保持一致，复用共同的输出路径配置（含「按站点分目录」）。
    func downloadCover(for task: MediaDownloaderTask) {
        Task { [weak self] in
            guard let self else { return }
            await self.downloadCover(
                sourceURL: task.url,
                existingThumbnailURL: task.thumbnailURL,
                preferredTitle: task.title,
                outputDirectory: self.coverOutputDirectory(for: task),
                useBrowserCookies: task.useBrowserCookies,
                browserCookieSource: task.browserCookieSource,
                taskID: task.id
            )
        }
    }

    /// 中文注释：下载历史记录对应的封面图片，保存到视频实际所在的输出目录（复用共同配置）。
    func downloadCover(for historyRecord: MediaDownloadHistorySnapshot) {
        Task { [weak self] in
            guard let self else { return }
            await self.downloadCover(
                sourceURL: historyRecord.sourceURL,
                existingThumbnailURL: historyRecord.thumbnailURL,
                preferredTitle: historyRecord.displayTitle,
                outputDirectory: self.coverOutputDirectory(for: historyRecord),
                useBrowserCookies: historyRecord.useBrowserCookies,
                browserCookieSource: historyRecord.browserCookieSource,
                taskID: nil
            )
        }
    }

    /// 中文注释：解析队列任务封面的保存目录，确保与视频下载路径一致，复用共同的输出路径配置。
    /// 优先使用已解析出的视频实际目录；否则按「按站点分目录」设置推算同一目录。
    private func coverOutputDirectory(for task: MediaDownloaderTask) -> URL {
        if let fileURL = task.outputFileURL {
            return fileURL.deletingLastPathComponent()
        }
        return (inferOutputFileURL(for: task) ?? resolveOutputFolder()).deletingLastPathComponent()
    }

    /// 中文注释：解析历史记录封面的保存目录，确保与视频下载路径一致，复用共同的输出路径配置。
    /// 优先取视频实际目录；否则按历史记录保存的输出路径与「按站点分目录」设置推算同一目录。
    private func coverOutputDirectory(for historyRecord: MediaDownloadHistorySnapshot) -> URL {
        if let fileURL = historyRecord.outputFileURL {
            return fileURL.deletingLastPathComponent()
        }
        let base = historyRecord.outputFolderURL ?? resolveOutputFolder()
        var folder = base
        if historyRecord.useSiteSubfolder, historyRecord.extractorKey.isEmpty == false {
            folder = folder.appendingPathComponent(historyRecord.extractorKey)
        }
        return folder
    }

    /// 中文注释：把单个外部链接直接加入下载队列并开始下载（供订阅收件箱「下载」按钮调用）。
    /// - Parameters:
    ///   - urlString: 视频链接。
    ///   - title: 可选的展示标题（订阅通知里已有博主视频标题，先占位，yt-dlp 解析后会覆盖）。
    ///   - thumbnailURL: 可选的封面地址（订阅通知里已有缩略图，避免再次解析）。
    @discardableResult
    func enqueueDownload(urlString: String, title: String? = nil, thumbnailURL: URL? = nil) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            publishStatus("下载链接为空", isError: true)
            return false
        }
        // 中文注释：已在队列中则不重复添加，但仍然启动队列并给出提示。
        if let existing = tasks.first(where: { $0.url == trimmed }) {
            selectedTaskID = existing.id
            publishStatus("该链接已在下载队列中", isError: false)
            startQueue()
            return true
        }

        var newTask = MediaDownloaderTask(
            url: trimmed,
            quality: selectedQuality,
            container: selectedContainer,
            audioOnly: audioOnly,
            useCustomFormat: useCustomFormat,
            customFormat: customFormat,
            downloadSubtitles: downloadSubtitles,
            downloadThumbnail: downloadThumbnail,
            downloadMetadata: downloadMetadata,
            useBrowserCookies: useBrowserCookies,
            browserCookieSource: browserCookieSource,
            codecPreference: codecPreference,
            startTimecode: MediaDownloaderViewModel.normalizeTimecodeInput(startTimeInput),
            endTimecode: MediaDownloaderViewModel.normalizeTimecodeInput(endTimeInput),
            downloadSpeed: "",
            outputFileURL: nil,
            thumbnailURL: thumbnailURL
        )
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            newTask.title = title
        }
        tasks.insert(newTask, at: 0)
        if newTask.thumbnailURL == nil {
            startThumbnailFetchIfNeeded(for: newTask)
        }
        selectedTaskID = newTask.id
        publishStatus("已加入下载队列", isError: false)
        startQueue()
        return true
    }

    /// 中文注释：把播放列表解析出的多个条目批量加入下载队列（倒序入队以保留列表原有顺序）。
    /// - Parameter entries: 需要下载的列表条目。
    func enqueuePlaylistEntries(_ entries: [MediaPlaylistEntry]) {
        guard entries.isEmpty == false else {
            publishStatus("没有可下载的列表条目", isError: true)
            return
        }
        var added = 0
        // 中文注释：enqueueDownload 会把任务插到队列头部，这里倒序遍历使最终顺序与列表一致。
        for entry in entries.reversed() {
            guard let url = entry.webpageURL, url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { continue }
            if enqueueDownload(urlString: url, title: entry.displayTitle, thumbnailURL: entry.thumbnailURL) {
                added += 1
            }
        }
        if added > 0 {
            publishStatus("已加入 \(added) 个视频到下载队列", isError: false)
        } else {
            publishStatus("列表中的链接均已存在于队列中", isError: false)
        }
    }

    /// 中文注释：根据历史记录重新创建任务并加入当前下载队列。
    func enqueueHistoryRecord(_ historyRecord: MediaDownloadHistorySnapshot) {
        let newTask = MediaDownloaderTask(
            url: historyRecord.sourceURL,
            quality: historyRecord.qualityOption,
            container: historyRecord.containerOption,
            audioOnly: historyRecord.audioOnly,
            useCustomFormat: historyRecord.useCustomFormat,
            customFormat: historyRecord.customFormat,
            downloadSubtitles: historyRecord.downloadSubtitles,
            downloadThumbnail: historyRecord.downloadThumbnail,
            downloadMetadata: historyRecord.downloadMetadata,
            useBrowserCookies: historyRecord.useBrowserCookies,
            browserCookieSource: historyRecord.browserCookieSource,
            codecPreference: historyRecord.codecPreference,
            startTimecode: historyRecord.startTimecode,
            endTimecode: historyRecord.endTimecode,
            downloadSpeed: "",
            outputFileURL: nil,
            thumbnailURL: historyRecord.thumbnailURL
        )
        tasks.insert(newTask, at: 0)
        if selectedTaskID == nil {
            selectedTaskID = newTask.id
        }
        if let outputFolderURL = historyRecord.outputFolderURL {
            updateOutputFolder(outputFolderURL)
        }
        outputTemplate = historyRecord.outputTemplate
        useSiteSubfolder = historyRecord.useSiteSubfolder
        publishStatus("已根据历史记录重新加入下载队列", isError: false)
        if isQueueRunning {
            startPendingTasksIfNeeded()
        }
    }

    /// 中文注释：删除一条历史记录，但不影响已经下载好的本地文件。
    func deleteHistoryRecord(_ id: UUID) {
        historyStore?.deleteRecord(id: id)
        reloadHistory()
    }

    /// 中文注释：删除历史记录并尝试同时删除磁盘中的下载文件。
    func deleteHistoryRecordAndFile(_ id: UUID) {
        guard let record = historyStore?.record(for: id) else { return }
        removeFileIfNeeded(record.outputFileURL)
        historyStore?.deleteRecord(id: id)
        reloadHistory()
    }

    // MARK: - 批量操作

    /// 中文注释：切换单条历史记录的选中状态（仅在批量模式下生效）。
    func toggleHistorySelection(_ id: UUID) {
        guard isHistoryBatchMode else { return }
        if selectedHistoryIDs.contains(id) {
            selectedHistoryIDs.remove(id)
        } else {
            selectedHistoryIDs.insert(id)
        }
    }

    /// 中文注释：全选当前筛选后的所有历史记录。
    func selectAllFilteredHistory() {
        selectedHistoryIDs = Set(filteredHistoryRecords.map(\.id))
    }

    /// 中文注释：取消全选。
    func deselectAllHistory() {
        selectedHistoryIDs.removeAll()
    }

    /// 中文注释：批量删除选中的历史记录（仅删记录，不删文件）。
    func batchDeleteHistory() {
        let ids = selectedHistoryIDs
        guard ids.isEmpty == false else { return }
        historyStore?.deleteRecords(ids: ids)
        selectedHistoryIDs.removeAll()
        isHistoryBatchMode = false
        reloadHistory()
    }

    /// 中文注释：批量删除选中的历史记录及其关联的磁盘文件。
    func batchDeleteHistoryAndFiles() {
        let ids = selectedHistoryIDs
        guard ids.isEmpty == false else { return }
        for id in ids {
            if let record = historyStore?.record(for: id) {
                removeFileIfNeeded(record.outputFileURL)
            }
        }
        historyStore?.deleteRecords(ids: ids)
        selectedHistoryIDs.removeAll()
        isHistoryBatchMode = false
        reloadHistory()
    }

    /// 中文注释：批量重新下载选中的历史记录。
    func batchRetryHistory() {
        let ids = selectedHistoryIDs
        guard ids.isEmpty == false else { return }
        // 倒序入队以保持原有顺序
        for id in ids.sorted().reversed() {
            if let record = historyRecords.first(where: { $0.id == id }) {
                let newTask = MediaDownloaderTask(
                    url: record.sourceURL,
                    quality: record.qualityOption,
                    container: record.containerOption,
                    audioOnly: record.audioOnly,
                    useCustomFormat: record.useCustomFormat,
                    customFormat: record.customFormat,
                    downloadSubtitles: record.downloadSubtitles,
                    downloadThumbnail: record.downloadThumbnail,
                    downloadMetadata: record.downloadMetadata,
                    useBrowserCookies: record.useBrowserCookies,
                    browserCookieSource: record.browserCookieSource,
                    codecPreference: record.codecPreference,
                    startTimecode: record.startTimecode,
                    endTimecode: record.endTimecode,
                    downloadSpeed: "",
                    outputFileURL: nil,
                    thumbnailURL: record.thumbnailURL
                )
                tasks.insert(newTask, at: 0)
                if let outputFolderURL = record.outputFolderURL {
                    updateOutputFolder(outputFolderURL)
                }
                outputTemplate = record.outputTemplate
                useSiteSubfolder = record.useSiteSubfolder
            }
        }
        selectedHistoryIDs.removeAll()
        isHistoryBatchMode = false
        publishStatus("已批量加入 \(ids.count) 个任务到下载队列", isError: false)
        if isQueueRunning {
            startPendingTasksIfNeeded()
        }
    }

    /// 中文注释：当前筛选结果中被选中的条数。
    var selectedHistoryCount: Int {
        selectedHistoryIDs.count
    }

    /// 中文注释：批量操作是否可用（至少选中一条）。
    var canBatchOperate: Bool {
        selectedHistoryIDs.isEmpty == false
    }

    /// 中文注释：把输入框中的链接解析为任务并加入队列。
    func addTasksFromInput() {
        let urls = parseUrls(from: urlText)
        guard urls.isEmpty == false else {
            publishStatus("请输入有效的下载链接", isError: true)
            return
        }
        let existing = Set(tasks.map { $0.url })
        let newTasks = urls.filter { existing.contains($0) == false }.map {
            MediaDownloaderTask(
                url: $0,
                quality: selectedQuality,
                container: selectedContainer,
                audioOnly: audioOnly,
                useCustomFormat: useCustomFormat,
                customFormat: customFormat,
                downloadSubtitles: downloadSubtitles,
                downloadThumbnail: downloadThumbnail,
                downloadMetadata: downloadMetadata,
                useBrowserCookies: useBrowserCookies,
                browserCookieSource: browserCookieSource,
                codecPreference: codecPreference,
                startTimecode: MediaDownloaderViewModel.normalizeTimecodeInput(startTimeInput),
                endTimecode: MediaDownloaderViewModel.normalizeTimecodeInput(endTimeInput)
            )
        }
        tasks.append(contentsOf: newTasks)
        newTasks.forEach { startThumbnailFetchIfNeeded(for: $0) }
        if selectedTaskID == nil {
            selectedTaskID = newTasks.first?.id
        }
        urlText = ""
        publishStatus("已加入 \(newTasks.count) 个任务", isError: false)
        if isQueueRunning {
            startPendingTasksIfNeeded()
        }
    }

    /// 中文注释：启动队列下载。
    func startQueue() {
        if isQueueRunning { return }
        isQueueRunning = true
        startPendingTasksIfNeeded()
    }

    /// 中文注释：停止当前下载任务。
    func stopCurrentTask() {
        guard let taskID = runningProcesses.keys.first else { return }
        stopTask(taskID)
    }

    /// 中文注释：停止指定任务（若处于等待状态则直接标记停止）。
    func stopTask(_ id: UUID) {
        if let process = runningProcesses[id] {
            didRequestStopTaskIDs.insert(id)
            process.terminate()
            stopSpeedSampling(taskID: id)
            return
        }
        updateTask(id) { task in
            if task.status == .pending {
                task.status = .stopped
            }
        }
    }

    /// 中文注释：重新开始指定任务。
    func restartTask(_ id: UUID) {
        updateTask(id) { task in
            task.status = .pending
            task.progress = 0
            task.logText = ""
        }
        if isQueueRunning == false {
            startQueue()
        } else {
            startPendingTasksIfNeeded()
        }
    }

    /// 中文注释：移除指定任务。
    func removeTask(_ id: UUID) {
        guard runningProcesses[id] == nil else {
            publishStatus("运行中的任务无法删除", isError: true)
            return
        }
        tasks.removeAll { $0.id == id }
        taskLogLinesCache[id] = nil
        taskHistoryRecordIDs[id] = nil
        if selectedTaskID == id {
            selectedTaskID = tasks.first?.id
        }
    }

    /// 中文注释：清除已完成或已停止的任务。
    func clearFinishedTasks() {
        let removedIDs = tasks
            .filter { [.success, .failed, .stopped].contains($0.status) }
            .map(\.id)
        tasks.removeAll { [.success, .failed, .stopped].contains($0.status) }
        removedIDs.forEach {
            taskLogLinesCache[$0] = nil
            taskHistoryRecordIDs[$0] = nil
        }
        if let selected = selectedTaskID, tasks.contains(where: { $0.id == selected }) == false {
            selectedTaskID = tasks.first?.id
        }
    }

    /// 中文注释：返回当前需要展示的日志内容。
    func logTextForDisplay() -> String {
        if let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) {
            return task.logText
        }
        if let runningTaskID = runningProcesses.keys.first, let task = tasks.first(where: { $0.id == runningTaskID }) {
            return task.logText
        }
        return ""
    }

    /// 中文注释：返回指定任务的日志内容。
    func logText(for id: UUID) -> String {
        tasks.first(where: { $0.id == id })?.logText ?? ""
    }

    /// 中文注释：返回指定任务的日志行数组（用于分页渲染）。
    func logLines(for id: UUID) -> [String] {
        taskLogLinesCache[id] ?? []
    }

    /// 中文注释：返回指定任务的标题。
    func taskTitle(for id: UUID) -> String {
        tasks.first(where: { $0.id == id })?.title ?? "下载日志"
    }

    /// 中文注释：生成指定任务的 yt-dlp 执行命令字符串。
    func commandString(for task: MediaDownloaderTask) -> String {
        let executable = ytDlpPath ?? "yt-dlp"
        let outputFolder = resolveOutputFolder()
        let args = buildArguments(for: task, outputFolder: outputFolder)
        return ([executable] + args).map { shellEscape($0) }.joined(separator: " ")
    }

    /// 中文注释：追加一条 yt-dlp 命令日志，并限制最大条数。
    func appendCommandLog(_ message: String, type: String = "yt-dlp命令") {
        let entry = CommandLogEntry(timestamp: Date(), type: type, message: message)
        commandLogs.append(entry)
        if commandLogs.count > commandLogLimit {
            commandLogs.removeFirst(commandLogs.count - commandLogLimit)
        }
    }

    /// 中文注释：清空命令日志。
    func clearCommandLogs() {
        commandLogs.removeAll()
    }

    /// 中文注释：删除指定任务并更新选择状态。
    func deleteTask(_ id: UUID) {
        if runningProcesses[id] != nil {
            stopTask(id)
        }
        tasks.removeAll { $0.id == id }
        taskLogLinesCache[id] = nil
        taskHistoryRecordIDs[id] = nil
        if let selected = selectedTaskID, tasks.contains(where: { $0.id == selected }) == false {
            selectedTaskID = tasks.first?.id
        }
    }

    /// 中文注释：删除任务并尝试删除已下载文件。
    func deleteTaskAndFile(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let url = resolveDeleteFileURL(for: task)
        removeFileIfNeeded(url)
        deleteTask(id)
    }

    /// 中文注释：删除任务并支持外部传入文件路径。
    func deleteTaskAndFile(_ id: UUID, fileURLOverride: URL?) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let url = fileURLOverride ?? resolveDeleteFileURL(for: task)
        removeFileIfNeeded(url)
        deleteTask(id)
    }

    /// 中文注释：生成删除文件的信息（路径与是否为推断）。
    func deleteFileInfo(for task: MediaDownloaderTask) -> (url: URL?, isInferred: Bool) {
        if let url = resolveDeleteFileURL(for: task) {
            let isInferred = task.outputFileURL == nil
            return (url, isInferred)
        }
        if let inferred = inferOutputFileURL(for: task) {
            return (inferred, true)
        }
        return (nil, true)
    }

    /// 中文注释：准备默认输出目录为下载文件夹。
    private func prepareDefaultOutputFolder() {
        if let savedPath = UserDefaults.standard.string(forKey: outputFolderPathKey),
           savedPath.isEmpty == false,
           FileManager.default.fileExists(atPath: savedPath) {
            outputFolderURL = URL(fileURLWithPath: savedPath)
            outputFolderDisplay = savedPath
            return
        }

        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            outputFolderURL = downloads
            outputFolderDisplay = downloads.path
        }
    }

    /// 中文注释：按并发上限启动待下载任务。
    private func startPendingTasksIfNeeded() {
        while runningProcesses.count < maxConcurrentDownloads {
            guard let nextTask = tasks.first(where: { $0.status == .pending }) else {
                if runningProcesses.isEmpty {
                    isQueueRunning = false
                }
                return
            }
            startTask(nextTask)
        }
    }

    /// 中文注释：实际执行指定任务的下载逻辑。
    private func startTask(_ task: MediaDownloaderTask) {
        guard let ytDlpPath else {
            publishStatus("未检测到 yt-dlp", isError: true)
            isQueueRunning = false
            return
        }

        let outputFolder = resolveOutputFolder()
        if outputFolderDisplay.isEmpty {
            outputFolderDisplay = outputFolder.path
        }

        updateTask(task.id) { task in
            task.status = .running
            task.progress = 0
            task.logText = ""
            task.downloadSpeed = ""
        }

        let commandLine = commandString(for: task)
        createHistoryRecordIfNeeded(for: task, outputFolder: outputFolder, commandLine: commandLine)
        appendCommandLog(commandLine)
        appendLog("[命令] \(commandLine)\n", to: task.id)
        taskLogLinesCache[task.id] = ["[命令] \(commandLine)"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = buildArguments(for: task, outputFolder: outputFolder)
        process.environment = buildEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let taskID = task.id
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.appendLog(text, to: taskID)
            }
        }

        do {
            try process.run()
            runningProcesses[task.id] = process
            startSpeedSampling(taskID: task.id)
            Task.detached { [process, taskID] in
                process.waitUntilExit()
                await MainActor.run { [weak self] in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    self?.handleTermination(process, taskID: taskID)
                }
            }
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            appendLog("[错误] 无法启动 yt-dlp: \(error.localizedDescription)\n", to: task.id)
            updateTask(task.id) { task in
                task.status = .failed
            }
            persistFailure(for: task.id, explicitMessage: "无法启动 yt-dlp: \(error.localizedDescription)")
            runningProcesses[task.id] = nil
            isQueueRunning = runningProcesses.isEmpty == false
            stopSpeedSampling(taskID: task.id)
            publishStatus("无法启动 yt-dlp: \(error.localizedDescription)", isError: true)
        }
    }

    /// 中文注释：处理下载进程结束后的状态更新并自动衔接队列。
    private func handleTermination(_ process: Process, taskID: UUID) {
        let exitCode = process.terminationStatus
        runningProcesses[taskID] = nil
        stopSpeedSampling(taskID: taskID)

        if didRequestStopTaskIDs.contains(taskID) {
            updateTask(taskID) { task in
                task.status = .stopped
            }
            persistStopped(for: taskID)
            publishStatus("已停止下载", isError: false)
            didRequestStopTaskIDs.remove(taskID)
            startPendingTasksIfNeeded()
            return
        }

        if exitCode == 0 {
            updateTask(taskID) { task in
                task.status = .success
                task.progress = 1
            }
            persistSuccess(for: taskID)
            publishStatus("下载完成", isError: false)
            if MediaDownloaderSettings.downloadNotifyEnabled,
               let finished = tasks.first(where: { $0.id == taskID }) {
                notifier.notifyDownloadFinished(title: finished.title, fileURL: finished.outputFileURL)
            }
        } else {
            updateTask(taskID) { task in
                task.status = .failed
            }
            persistFailure(for: taskID, explicitMessage: "下载失败，退出码 \(exitCode)")
            publishStatus("下载失败，退出码 \(exitCode)", isError: true)
            if MediaDownloaderSettings.downloadNotifyEnabled,
               let finished = tasks.first(where: { $0.id == taskID }) {
                notifier.notifyDownloadFailed(title: finished.title, reason: "退出码 \(exitCode)")
            }
        }

        startPendingTasksIfNeeded()
    }

    /// 中文注释：解析输入文本中的链接。
    private func parseUrls(from text: String) -> [String] {
        let parts = text
            .split { $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == " " }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return parts
    }

    /// 中文注释：解析最终可用的输出目录。
    private func resolveOutputFolder() -> URL {
        if let outputFolderURL {
            return outputFolderURL
        }
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads
        }
        return FileManager.default.temporaryDirectory
    }

    /// 中文注释：构建 yt-dlp 执行参数。
    private func buildArguments(for task: MediaDownloaderTask, outputFolder: URL) -> [String] {
        var arguments: [String] = [
            "--newline",
            "-P", outputFolder.path,
            "-o", buildOutputTemplate()
        ]
        if task.audioOnly {
            arguments.append(contentsOf: ["-f", "bestaudio", "--extract-audio", "--audio-format", "mp3"])
        } else if task.useCustomFormat, task.customFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            arguments.append(contentsOf: ["-f", task.customFormat])
        } else if let qualityFormat = qualityFormatArgument(for: task.quality) {
            arguments.append(contentsOf: ["-f", qualityFormat])
        }
        if task.container != .auto, task.audioOnly == false {
            arguments.append(contentsOf: ["--merge-output-format", task.container.rawValue])
        }
        if task.audioOnly == false, task.codecPreference == .h264 {
            arguments.append(contentsOf: ["-S", "vcodec:h264"])
        }
        if task.useBrowserCookies {
            arguments.append(contentsOf: ["--cookies-from-browser", task.browserCookieSource.argumentValue])
        }
        if task.downloadSubtitles {
            arguments.append("--write-subs")
        }
        if task.downloadThumbnail {
            arguments.append(contentsOf: ["--write-thumbnail", "--convert-thumbnails", "jpg"])
        }
        if task.downloadMetadata {
            arguments.append("--write-info-json")
        }
        if let start = task.startTimecode, let end = task.endTimecode {
            let startValue = start.trimmingCharacters(in: .whitespacesAndNewlines)
            let endValue = end.trimmingCharacters(in: .whitespacesAndNewlines)
            if startValue.isEmpty == false, endValue.isEmpty == false {
                arguments.append(contentsOf: ["--download-sections", "*\(startValue)-\(endValue)"])
                arguments.append(contentsOf: ["--progress-template", "download:progress:%(progress.downloaded_bytes)s/%(progress.total_bytes_estimate)s:%(progress.speed_str)s"])
            }
        }
        arguments.append(task.url)
        return arguments
    }

    /// 中文注释：把用户输入的时间内容规范化为 HH:MM:SS。
    static func normalizeTimecodeInput(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map { String($0.filter(\.isNumber)) }
            let hasLongPart = parts.contains { $0.count > 2 }
            if hasLongPart == false {
                let lastParts = Array(parts.suffix(3))
                if lastParts.count == 2 {
                    let minutes = min(Int(lastParts[0]) ?? 0, 59)
                    let seconds = min(Int(lastParts[1]) ?? 0, 59)
                    return String(format: "%02d:%02d:%02d", 0, minutes, seconds)
                }
                if lastParts.count == 3 {
                    let hours = min(Int(lastParts[0]) ?? 0, 99)
                    let minutes = min(Int(lastParts[1]) ?? 0, 59)
                    let seconds = min(Int(lastParts[2]) ?? 0, 59)
                    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                }
            }
        }
        let digits = trimmed.filter { $0.isNumber }
        if digits.isEmpty { return nil }
        let limited = String(digits.suffix(6))
        let secondsPart = limited.suffix(2)
        let minutesPart = limited.dropLast(min(2, limited.count)).suffix(2)
        let hoursPart = limited.dropLast(min(4, limited.count))
        let seconds = min(Int(secondsPart) ?? 0, 59)
        let minutes = min(Int(minutesPart) ?? 0, 59)
        let hours = min(Int(hoursPart) ?? 0, 99)
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// 中文注释：构建输出文件命名模板。
    private func buildOutputTemplate() -> String {
        let base = outputTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = base.isEmpty ? "%(title)s.%(ext)s" : base
        if useSiteSubfolder {
            return "%(extractor)s/\(normalized)"
        }
        return normalized
    }

    /// 中文注释：对命令参数进行简单的 Shell 转义。
    private func shellEscape(_ value: String) -> String {
        let needsQuote = value.contains { char in
            switch char {
            case " ", "\"", "'", "?", "&", "*", "(", ")", "[", "]", "{", "}", "$", "!", ";", "|", "<", ">", "\\", "`":
                return true
            default:
                return false
            }
        }
        if needsQuote {
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return value
    }

    /// 中文注释：按需异步获取缩略图 URL，不阻塞下载线程。
    private func startThumbnailFetchIfNeeded(for task: MediaDownloaderTask) {
        guard task.thumbnailURL == nil else { return }
        let taskID = task.id
        let executable = ytDlpPath ?? "yt-dlp"
        let arguments = buildThumbnailArguments(for: task)
        let thumbnailCommand = ([executable] + arguments).map { shellEscape($0) }.joined(separator: " ")
        appendCommandLog(thumbnailCommand, type: "yt-dlp缩略图")
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let result = Self.fetchThumbnailInfo(executable: executable, arguments: arguments)
            guard let urlText = result.urlText, let url = Self.normalizeThumbnailURL(urlText) else {
                await MainActor.run {
                    self.logger.warning("缩略图解析失败(退出码 \(result.exitCode))：\(result.rawOutput, privacy: .public)")
                }
                return
            }
            await MainActor.run {
                self.updateTask(taskID) { item in
                    if item.thumbnailURL == nil {
                        item.thumbnailURL = url
                    }
                }
                self.syncHistoryThumbnail(for: taskID, thumbnailURL: url)
            }
        }
    }

    /// 中文注释：规范化缩略图 URL，优先使用 https 以避免 ATS 阻断。
    nonisolated private static func normalizeThumbnailURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") {
            let httpsText = "https://" + trimmed.dropFirst("http://".count)
            return URL(string: httpsText) ?? URL(string: trimmed)
        }
        return URL(string: trimmed)
    }

    /// `ThumbnailFetchResult` 的作用：封装缩略图获取结果与原始输出。
    private struct ThumbnailFetchResult {
        let urlText: String?
        let rawOutput: String
        let exitCode: Int32
    }

    /// 中文注释：构建缩略图获取参数。
    private func buildThumbnailArguments(for task: MediaDownloaderTask) -> [String] {
        buildThumbnailArguments(
            sourceURL: task.url,
            useBrowserCookies: task.useBrowserCookies,
            browserCookieSource: task.browserCookieSource
        )
    }

    /// 中文注释：构建封面地址解析参数，供队列任务和历史记录复用。
    private func buildThumbnailArguments(
        sourceURL: String,
        useBrowserCookies: Bool,
        browserCookieSource: BrowserCookieSource
    ) -> [String] {
        var arguments: [String] = ["--print", "thumbnail"]
        if useBrowserCookies {
            arguments.append(contentsOf: ["--cookies-from-browser", browserCookieSource.argumentValue])
        }
        arguments.append(sourceURL)
        return arguments
    }

    /// 中文注释：解析封面地址并把封面文件写入本地输出目录。
    private func downloadCover(
        sourceURL: String,
        existingThumbnailURL: URL?,
        preferredTitle: String,
        outputDirectory: URL,
        useBrowserCookies: Bool,
        browserCookieSource: BrowserCookieSource,
        taskID: UUID?
    ) async {
        publishStatus("正在准备下载封面...", isError: false)
        let thumbnailURL: URL?
        if let existingThumbnailURL {
            thumbnailURL = existingThumbnailURL
        } else {
            thumbnailURL = await resolveThumbnailURL(
                sourceURL: sourceURL,
                useBrowserCookies: useBrowserCookies,
                browserCookieSource: browserCookieSource,
                taskID: taskID
            )
        }

        guard let thumbnailURL else {
            publishStatus("未解析到可下载的封面地址", isError: true)
            return
        }

        do {
            let fileURL = try await downloadThumbnailFile(from: thumbnailURL, title: preferredTitle, directory: outputDirectory)
            publishStatus("封面已下载: \(fileURL.path)", isError: false)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } catch {
            publishStatus("封面下载失败: \(error.localizedDescription)", isError: true)
        }
    }

    /// 中文注释：在缺少封面地址时调用 yt-dlp 解析，并同步回当前任务与历史记录。
    private func resolveThumbnailURL(
        sourceURL: String,
        useBrowserCookies: Bool,
        browserCookieSource: BrowserCookieSource,
        taskID: UUID?
    ) async -> URL? {
        let executable = ytDlpPath ?? "yt-dlp"
        let arguments = buildThumbnailArguments(
            sourceURL: sourceURL,
            useBrowserCookies: useBrowserCookies,
            browserCookieSource: browserCookieSource
        )
        let thumbnailCommand = ([executable] + arguments).map { shellEscape($0) }.joined(separator: " ")
        appendCommandLog(thumbnailCommand, type: "yt-dlp封面")
        let result = await Task.detached(priority: .utility) {
            Self.fetchThumbnailInfo(executable: executable, arguments: arguments)
        }.value
        guard let urlText = result.urlText, let url = Self.normalizeThumbnailURL(urlText) else {
            logger.warning("封面解析失败(退出码 \(result.exitCode))：\(result.rawOutput, privacy: .public)")
            return nil
        }

        if let taskID {
            updateTask(taskID) { item in
                item.thumbnailURL = url
            }
            syncHistoryThumbnail(for: taskID, thumbnailURL: url)
        }
        return url
    }

    /// 中文注释：下载封面图片数据，统一转码为 JPEG 后保存到目标目录（与 --convert-thumbnails jpg 一致）。
    private func downloadThumbnailFile(from url: URL, title: String, directory: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw URLError(.badServerResponse)
        }

        guard let jpegData = convertToJPEG(data) else {
            throw URLError(.cannotDecodeContentData)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = coverBaseName(from: title, fallbackURL: url)
        let fileURL = uniqueFileURL(directory: directory, baseName: baseName, fileExtension: "jpg")
        try jpegData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// 中文注释：将任意图片格式数据转码为 JPEG，供封面统一输出使用。
    private func convertToJPEG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let jpegData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            jpegData, "public.jpeg" as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination, cgImage,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return jpegData as Data
    }

    /// 中文注释：根据视频标题生成封面文件基础名称，标题无效时回退为固定前缀。
    private func coverBaseName(from title: String, fallbackURL: URL) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName: String
        if trimmedTitle.isEmpty || trimmedTitle.lowercased().hasPrefix("http") {
            rawName = fallbackURL.deletingPathExtension().lastPathComponent.isEmpty ? "video-cover" : fallbackURL.deletingPathExtension().lastPathComponent
        } else {
            rawName = "\(trimmedTitle)-cover"
        }
        return sanitizeFilename(rawName)
    }

    /// 中文注释：生成不覆盖已有文件的保存路径，存在重名时自动追加序号。
    private func uniqueFileURL(directory: URL, baseName: String, fileExtension: String) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension(fileExtension)
            index += 1
        }
        return candidate
    }

    /// 中文注释：通过 yt-dlp 获取缩略图 URL。
    nonisolated private static func fetchThumbnailInfo(executable: String, arguments: [String]) -> ThumbnailFetchResult {
        let process = Process()
        let executableURL = URL(fileURLWithPath: executable)
        let isAbsolute = executableURL.isFileURL && executable.hasPrefix("/")
        if isAbsolute {
            process.executableURL = executableURL
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["yt-dlp"] + arguments
        }

        var environment = ProcessInfo.processInfo.environment
        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let envPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }
        let merged = Array(NSOrderedSet(array: envPaths + defaults)) as? [String] ?? defaults
        environment["PATH"] = merged.joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ThumbnailFetchResult(urlText: nil, rawOutput: "启动失败：\(error.localizedDescription)", exitCode: -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(whereSeparator: \.isNewline).map { String($0) }
        let candidates = lines.filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        let urlText = candidates.last ?? (trimmed.hasPrefix("http") ? trimmed : nil)
        return ThumbnailFetchResult(urlText: urlText, rawOutput: trimmed, exitCode: process.terminationStatus)
    }

    /// 中文注释：根据清晰度构建 yt-dlp 的格式表达式。
    private func qualityFormatArgument(for quality: VideoQualityOption) -> String? {
        guard let maxHeight = quality.maxHeight else {
            return "bestvideo+bestaudio/best"
        }
        return "bestvideo[height<=\(maxHeight)]+bestaudio/best[height<=\(maxHeight)]"
    }

    /// 中文注释：构建包含常见二进制目录的环境变量。
    private func buildEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ExecutableLocator.searchPaths().joined(separator: ":")
        return environment
    }

    /// 中文注释：追加日志文本并更新进度。
    private func appendLog(_ text: String, to taskID: UUID) {
        updateTask(taskID) { task in
            let cleaned = text.replacingOccurrences(of: "\r", with: "")
            let lines = cleaned.split(whereSeparator: \.isNewline).map(String.init)
            let batchLines = Array(lines.suffix(logAppendBatchLimit))
            var cache = taskLogLinesCache[taskID] ?? []
            if batchLines.isEmpty == false {
                cache.append(contentsOf: batchLines)
            }
            let commandLine = cache.first(where: { $0.hasPrefix(logCommandPrefix) })
            if cache.count > taskLogLimit {
                let overflow = cache.count - taskLogLimit
                cache.removeFirst(overflow)
            }
            if let commandLine {
                cache.removeAll(where: { $0.hasPrefix(logCommandPrefix) })
                cache.insert(commandLine, at: 0)
            }
            taskLogLinesCache[taskID] = cache
            task.logText = cache.joined(separator: "\n")
            let timeRangeProgress = extractTimeRangeProgress(from: cleaned, task: task)
            let templateProgress = extractTemplateProgress(from: cleaned)
            if let progress = timeRangeProgress ?? templateProgress.progress ?? extractProgress(from: cleaned) {
                let clamped = max(0, min(progress, 1.0))
                task.progress = (task.status == .running && clamped >= 1) ? 0.99 : clamped
            }
            let isTimeRangeTask = task.startTimecode != nil && task.endTimecode != nil
            let parsedSpeed = templateProgress.speedText ?? extractSpeed(from: cleaned)
            let fallbackSpeed = isTimeRangeTask ? nil : extractProcessingSpeed(from: cleaned)
            if let speedText = parsedSpeed ?? fallbackSpeed {
                task.downloadSpeed = speedText
            }
            if let fileURL = extractOutputFileURL(from: cleaned) {
                task.outputFileURL = fileURL
            }
        }
    }

    /// 中文注释：解析日志中的下载进度百分比。
    private func extractProgress(from text: String) -> Double? {
        let pattern = "(\\d{1,3}(?:\\.\\d+)?)%"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let match = matches.last else { return nil }
        guard let percentRange = Range(match.range(at: 1), in: text) else { return nil }
        let value = Double(text[percentRange]) ?? 0
        return max(0, min(value / 100.0, 1.0))
    }

    /// 中文注释：解析自定义进度模板中的下载进度与速度。
    private func extractTemplateProgress(from text: String) -> (progress: Double?, speedText: String?) {
        let pattern = "progress:(\\d+)/(\\d+)(?::([^\\s]+))?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (nil, nil)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let match = matches.last else { return (nil, nil) }
        guard let downloadedRange = Range(match.range(at: 1), in: text),
              let totalRange = Range(match.range(at: 2), in: text) else {
            return (nil, nil)
        }
        let downloaded = Double(text[downloadedRange]) ?? 0
        let total = Double(text[totalRange]) ?? 0
        let progress = total > 0 ? max(0, min(downloaded / total, 1.0)) : nil
        var speedText: String?
        if let speedRange = Range(match.range(at: 3), in: text) {
            let rawSpeed = String(text[speedRange])
            if rawSpeed.contains("/s") {
                speedText = rawSpeed
            } else if let speedValue = Double(rawSpeed), speedValue > 0 {
                speedText = formatSpeed(bytesPerSecond: speedValue)
            }
        }
        return (progress, speedText)
    }

    /// 中文注释：根据时间范围与 ffmpeg 日志中的 time= 推算下载进度。
    private func extractTimeRangeProgress(from text: String, task: MediaDownloaderTask) -> Double? {
        guard let start = task.startTimecode,
              let end = task.endTimecode,
              let duration = timecodeDuration(start: start, end: end),
              duration > 0 else {
            return nil
        }
        guard let current = extractFfmpegTime(from: text) else { return nil }
        return current / duration
    }

    /// 中文注释：解析 ffmpeg 输出中的 time=HH:MM:SS.xx。
    private func extractFfmpegTime(from text: String) -> Double? {
        let pattern = "time=(\\d{2}):(\\d{2}):(\\d{2})(?:\\.(\\d+))?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        guard let hRange = Range(match.range(at: 1), in: text),
              let mRange = Range(match.range(at: 2), in: text),
              let sRange = Range(match.range(at: 3), in: text) else { return nil }
        let hours = Double(text[hRange]) ?? 0
        let minutes = Double(text[mRange]) ?? 0
        let seconds = Double(text[sRange]) ?? 0
        var value = hours * 3600 + minutes * 60 + seconds
        if match.range(at: 4).location != NSNotFound,
           let fracRange = Range(match.range(at: 4), in: text) {
            let fracText = "0." + text[fracRange]
            value += Double(fracText) ?? 0
        }
        return value
    }

    /// 中文注释：根据起止时间码计算持续时长（秒）。
    private func timecodeDuration(start: String, end: String) -> Double? {
        guard let startValue = parseTimecodeToSeconds(start),
              let endValue = parseTimecodeToSeconds(end),
              endValue > startValue else {
            return nil
        }
        return endValue - startValue
    }

    /// 中文注释：把 HH:MM:SS 或 MM:SS 或 SS 解析为秒。
    private func parseTimecodeToSeconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let parts = trimmed.split(separator: ":").map { String($0) }
        if parts.count == 1 {
            return Double(parts[0])
        }
        if parts.count == 2 {
            let minutes = Double(parts[0]) ?? 0
            let seconds = Double(parts[1]) ?? 0
            return minutes * 60 + seconds
        }
        if parts.count >= 3 {
            let hours = Double(parts[parts.count - 3]) ?? 0
            let minutes = Double(parts[parts.count - 2]) ?? 0
            let seconds = Double(parts[parts.count - 1]) ?? 0
            return hours * 3600 + minutes * 60 + seconds
        }
        return nil
    }

    /// 中文注释：从默认日志中提取网速文本。
    private func extractSpeed(from text: String) -> String? {
        let pattern = "([0-9.]+\\s*(?:KiB|MiB|GiB|B|KB|MB|GB)/s)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let match = matches.last else { return nil }
        guard let speedRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[speedRange]).replacingOccurrences(of: " ", with: "")
    }

    /// 中文注释：解析 ffmpeg 输出中的处理速度（例如 speed=1.42x）。
    private func extractProcessingSpeed(from text: String) -> String? {
        let pattern = "speed=([0-9.]+)x"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let match = matches.last else { return nil }
        guard let speedRange = Range(match.range(at: 1), in: text) else { return nil }
        return "处理速度 \(text[speedRange])x"
    }

    /// 中文注释：从日志中提取输出文件路径。
    private func extractOutputFileURL(from text: String) -> URL? {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        for line in lines {
            if let destination = extractPath(after: "Destination:", in: line) {
                return urlFromPath(destination)
            }
            if let output = extractOutputPath(from: line) {
                return urlFromPath(output)
            }
            if let merged = extractMergedPath(from: line) {
                return urlFromPath(merged)
            }
        }
        return nil
    }

    /// 中文注释：解析“Destination:”后面的路径。
    private func extractPath(after keyword: String, in line: String) -> String? {
        guard let range = line.range(of: keyword) else { return nil }
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// 中文注释：解析合并输出路径。
    private func extractMergedPath(from line: String) -> String? {
        let pattern = "Merging formats into\\s+\"(.+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        guard let pathRange = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[pathRange])
    }

    /// 中文注释：解析输出路径（例如 to 'file:/path/file.mp4.part'）。
    private func extractOutputPath(from line: String) -> String? {
        let pattern = "to\\s+'([^']+)'"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        guard let pathRange = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[pathRange])
    }

    /// 中文注释：把文本路径转换为文件 URL。
    private func urlFromPath(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url
        }
        if trimmed.hasPrefix("file:/") {
            let normalized = trimmed.replacingOccurrences(of: "file:", with: "", options: [.anchored])
            return URL(fileURLWithPath: normalized)
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return nil
    }

    /// 中文注释：按规则推断输出文件路径。
    private func inferOutputFileURL(for task: MediaDownloaderTask) -> URL? {
        let extractor = ExtractorKey.infer(from: task.url)
        let rawTemplate = outputTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = rawTemplate.isEmpty ? "%(title)s.%(ext)s" : rawTemplate
        let title = inferTitle(from: task)
        let ext = inferExtension(for: task)
        let includesExtractor = template.contains("%(extractor)s")
        var filePath = template
            .replacingOccurrences(of: "%(title)s", with: title)
            .replacingOccurrences(of: "%(ext)s", with: ext)
            .replacingOccurrences(of: "%(extractor)s", with: extractor)
        if filePath.contains("%(") {
            filePath = "\(title).\(ext)"
        }
        var baseFolder = resolveOutputFolder()
        if useSiteSubfolder && includesExtractor == false {
            baseFolder = baseFolder.appendingPathComponent(extractor)
        }
        return baseFolder.appendingPathComponent(filePath)
    }

    /// 中文注释：推断文件名标题。
    private func inferTitle(from task: MediaDownloaderTask) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.lowercased().hasPrefix("http") {
            return "download-\(task.id.uuidString.prefix(8))"
        }
        return sanitizeFilename(title)
    }

    /// 中文注释：推断输出文件扩展名。
    private func inferExtension(for task: MediaDownloaderTask) -> String {
        if task.audioOnly { return "mp3" }
        if task.container != .auto { return task.container.rawValue }
        return "mp4"
    }

    /// 中文注释：清理文件名中的非法字符。
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "download" : cleaned
    }

    /// 中文注释：根据任务解析删除路径，优先日志记录，其次推断。
    private func resolveDeleteFileURL(for task: MediaDownloaderTask) -> URL? {
        if let url = normalizedDeleteURL(task.outputFileURL) {
            return url
        }
        if let inferred = inferOutputFileURL(for: task) {
            return normalizedDeleteURL(inferred)
        }
        return nil
    }

    /// 中文注释：校正可删除的文件路径（含 .part）。
    private func normalizedDeleteURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if url.pathExtension != "part" {
            let partURL = url.appendingPathExtension("part")
            if FileManager.default.fileExists(atPath: partURL.path) {
                return partURL
            }
        } else {
            let baseURL = url.deletingPathExtension()
            if FileManager.default.fileExists(atPath: baseURL.path) {
                return baseURL
            }
        }
        return url
    }

    /// 中文注释：校验文件真实存在并排除 yt-dlp 下载中的 `.part` 临时文件。
    private func existingPlayableFileURL(_ url: URL?) -> URL? {
        guard let url, url.pathExtension != "part" else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// 中文注释：删除文件并处理错误提示。
    private func removeFileIfNeeded(_ url: URL?) {
        guard let url else {
            publishStatus("未找到下载文件路径，无法删除源文件", isError: true)
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            publishStatus("删除文件失败: \(error.localizedDescription)", isError: true)
        }
    }

    /// 中文注释：启动文件大小采样以计算实时下载速度。
    private func startSpeedSampling(taskID: UUID) {
        stopSpeedSampling(taskID: taskID)
        let task = Task { [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { [weak self] in
                    self?.updateSpeedSample(taskID)
                }
            }
        }
        speedSampleTasks[taskID] = task
    }

    /// 中文注释：停止速度采样任务。
    private func stopSpeedSampling(taskID: UUID) {
        speedSampleTasks[taskID]?.cancel()
        speedSampleTasks[taskID] = nil
        speedSampleStates[taskID] = nil
    }

    /// 中文注释：根据文件增长计算下载速度。
    private func updateSpeedSample(_ taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        guard task.status == .running else { return }
        guard let url = existingDownloadFileURL(for: task) else { return }
        let now = Date()
        let currentSize = fileSize(at: url)
        if let state = speedSampleStates[taskID], state.url == url {
            let deltaBytes = currentSize - state.lastBytes
            let deltaTime = now.timeIntervalSince(state.lastTime)
            guard deltaTime > 0 else { return }
            var recent = state.recentSpeeds
            var stallCount = state.stallCount
            if deltaBytes > 0 {
                stallCount = 0
                let speed = Double(deltaBytes) / deltaTime
                recent.append(speed)
                if recent.count > 5 {
                    recent.removeFirst(recent.count - 5)
                }
                let average = recent.reduce(0, +) / Double(recent.count)
                updateTask(taskID) { item in
                    item.downloadSpeed = formatSpeed(bytesPerSecond: average)
                }
            } else {
                stallCount += 1
                if stallCount >= 3 {
                    updateTask(taskID) { item in
                        item.downloadSpeed = "等待网络..."
                    }
                } else if recent.isEmpty == false {
                    let average = recent.reduce(0, +) / Double(recent.count)
                    updateTask(taskID) { item in
                        item.downloadSpeed = formatSpeed(bytesPerSecond: average)
                    }
                }
            }
            speedSampleStates[taskID] = SpeedSampleState(
                url: url,
                lastBytes: currentSize,
                lastTime: now,
                recentSpeeds: recent,
                stallCount: stallCount
            )
        } else {
            speedSampleStates[taskID] = SpeedSampleState(
                url: url,
                lastBytes: currentSize,
                lastTime: now,
                recentSpeeds: [],
                stallCount: 0
            )
        }
    }

    /// 中文注释：尝试获取正在写入的输出文件路径。
    private func existingDownloadFileURL(for task: MediaDownloaderTask) -> URL? {
        guard let url = task.outputFileURL else { return nil }
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if url.pathExtension != "part" {
            let partURL = url.appendingPathExtension("part")
            if FileManager.default.fileExists(atPath: partURL.path) {
                return partURL
            }
        } else {
            let baseURL = url.deletingPathExtension()
            if FileManager.default.fileExists(atPath: baseURL.path) {
                return baseURL
            }
        }
        return nil
    }

    /// 中文注释：读取文件大小（字节）。
    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// 中文注释：把字节每秒转换为可读网速文本。
    private func formatSpeed(bytesPerSecond: Double) -> String {
        let units = ["B/s", "KiB/s", "MiB/s", "GiB/s"]
        var value = bytesPerSecond
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.2f%@", value, units[index])
    }

    /// 中文注释：统一更新状态信息与错误标记。
    func publishStatus(_ message: String, isError: Bool) {
        statusMessage = message
        self.isError = isError
    }

    /// 中文注释：开启下载通知时申请一次通知授权，确保下载完成能弹出系统通知。
    func requestNotificationAuthorizationIfNeeded() {
        notifier.requestAuthorizationIfNeeded()
    }

    /// 中文注释：更新指定任务的可变属性。
    private func updateTask(_ id: UUID, _ transform: (inout MediaDownloaderTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = tasks[index]
        transform(&task)
        tasks[index] = task
    }

    /// 中文注释：为真正开始下载的任务创建一条历史快照记录。
    private func createHistoryRecordIfNeeded(for task: MediaDownloaderTask, outputFolder: URL, commandLine: String) {
        guard let historyStore else {
            publishStatus("下载历史存储尚未初始化，本次任务不会写入历史", isError: true)
            return
        }
        let historyID = UUID()
        let didSave = historyStore.createRunningRecord(
            historyID: historyID,
            task: task,
            outputFolderURL: outputFolder,
            outputTemplate: outputTemplate,
            useSiteSubfolder: useSiteSubfolder,
            commandPreview: commandLine
        )
        guard didSave else {
            publishStatus("下载历史保存失败，下载任务会继续执行", isError: true)
            return
        }
        taskHistoryRecordIDs[task.id] = historyID
        reloadHistory()
    }

    /// 中文注释：把任务成功结果同步回对应历史记录。
    private func persistSuccess(for taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let historyID = taskHistoryRecordIDs[taskID] else { return }
        historyStore?.markSuccess(
            historyID: historyID,
            task: task,
            outputFolderURL: resolveOutputFolder(),
            outputTemplate: outputTemplate,
            useSiteSubfolder: useSiteSubfolder
        )
        reloadHistory()
    }

    /// 中文注释：把任务失败结果同步回对应历史记录，并提取可读失败摘要。
    private func persistFailure(for taskID: UUID, explicitMessage: String? = nil) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let historyID = taskHistoryRecordIDs[taskID] else { return }
        historyStore?.markFailure(
            historyID: historyID,
            task: task,
            outputFolderURL: resolveOutputFolder(),
            outputTemplate: outputTemplate,
            useSiteSubfolder: useSiteSubfolder,
            errorSummary: explicitMessage ?? errorSummary(for: task)
        )
        reloadHistory()
    }

    /// 中文注释：把任务停止结果同步回对应历史记录。
    private func persistStopped(for taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let historyID = taskHistoryRecordIDs[taskID] else { return }
        historyStore?.markStopped(
            historyID: historyID,
            task: task,
            outputFolderURL: resolveOutputFolder(),
            outputTemplate: outputTemplate,
            useSiteSubfolder: useSiteSubfolder,
            errorSummary: "用户手动停止下载"
        )
        reloadHistory()
    }

    /// 中文注释：在缩略图异步解析完成后，同步历史记录中的缩略图字段。
    private func syncHistoryThumbnail(for taskID: UUID, thumbnailURL: URL?) {
        guard let historyID = taskHistoryRecordIDs[taskID] else { return }
        historyStore?.updateThumbnail(for: historyID, thumbnailURL: thumbnailURL)
        reloadHistory()
    }

    /// 中文注释：从任务日志末尾提取失败摘要，避免把整段日志写入数据库。
    private func errorSummary(for task: MediaDownloaderTask) -> String {
        let lines = task.logText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        let summary = lines.suffix(6).joined(separator: "\n")
        return summary.isEmpty ? "下载失败" : summary
    }
}
