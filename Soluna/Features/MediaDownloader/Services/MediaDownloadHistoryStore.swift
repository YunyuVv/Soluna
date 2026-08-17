//
//  MediaDownloadHistoryStore.swift
//  Soluna
//
//  Created by Codex on 2026/5/28.
//

import Foundation
import SwiftData
import os

@MainActor
/// `MediaDownloadHistoryStore` 的作用：封装媒体下载历史记录的 SwiftData 读写逻辑。
final class MediaDownloadHistoryStore {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "Soluna", category: "MediaDownloadHistoryStore")

    /// 中文注释：初始化历史存储服务，并允许注入 `FileManager` 方便测试。
    init(modelContext: ModelContext, fileManager: FileManager = .default) {
        self.modelContext = modelContext
        self.fileManager = fileManager
    }

    /// 中文注释：按时间倒序读取历史记录，并在读取时同步文件存在状态（兼容旧接口，无分页）。
    func loadRecords(limit: Int? = nil) -> [MediaDownloadHistorySnapshot] {
        var descriptor = FetchDescriptor<MediaDownloadHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }

        let records = (try? modelContext.fetch(descriptor)) ?? []
        refreshFileExistence(for: records)
        return records.map(MediaDownloadHistorySnapshot.init(record:))
    }

    /// 中文注释：分页加载历史记录，按时间倒序。返回指定页的快照数组。
    /// - Parameter page: 页码（从 0 开始）。
    /// - Parameter pageSize: 每页条数。
    func loadRecords(page: Int, pageSize: Int) -> [MediaDownloadHistorySnapshot] {
        var descriptor = FetchDescriptor<MediaDownloadHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchOffset = page * pageSize
        descriptor.fetchLimit = pageSize

        let records = (try? modelContext.fetch(descriptor)) ?? []
        refreshFileExistence(for: records)
        return records.map(MediaDownloadHistorySnapshot.init(record:))
    }

    /// 中文注释：返回历史记录总条数，用于分页判断"是否有更多"。
    func totalRecordCount() -> Int {
        let descriptor = FetchDescriptor<MediaDownloadHistoryRecord>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// 中文注释：把上次异常退出时仍处于下载中的记录修正为中断状态。
    func markInterruptedRecordsIfNeeded() {
        let descriptor = FetchDescriptor<MediaDownloadHistoryRecord>()
        guard let records = try? modelContext.fetch(descriptor) else { return }

        var didChange = false
        for record in records where record.status == .running {
            record.status = .interrupted
            record.finishedAt = record.finishedAt ?? Date()
            record.errorSummary = record.errorSummary ?? "应用关闭或窗口退出时任务被中断"
            didChange = true
        }

        if didChange {
            _ = saveContext()
        }
    }

    /// 中文注释：创建一条“正在下载”的历史记录，并保存本次任务参数快照。
    func createRunningRecord(
        historyID: UUID,
        task: MediaDownloaderTask,
        outputFolderURL: URL,
        outputTemplate: String,
        useSiteSubfolder: Bool,
        commandPreview: String?
    ) -> Bool {
        let record = MediaDownloadHistoryRecord(
            id: historyID,
            sourceURL: task.url,
            title: task.title,
            status: .running,
            createdAt: task.createdAt,
            startedAt: Date(),
            outputFolderPath: outputFolderURL.path,
            outputFilePath: task.outputFileURL?.path,
            thumbnailURLString: task.thumbnailURL?.absoluteString,
            extractorKey: ExtractorKey.infer(from: task.url),
            fileExists: fileExists(at: task.outputFileURL),
            qualityRawValue: task.quality.rawValue,
            containerRawValue: task.container.rawValue,
            audioOnly: task.audioOnly,
            useCustomFormat: task.useCustomFormat,
            customFormat: task.customFormat,
            downloadSubtitles: task.downloadSubtitles,
            downloadThumbnail: task.downloadThumbnail,
            downloadMetadata: task.downloadMetadata,
            useBrowserCookies: task.useBrowserCookies,
            browserCookieSourceRawValue: task.browserCookieSource.rawValue,
            codecPreferenceRawValue: task.codecPreference.rawValue,
            startTimecode: task.startTimecode,
            endTimecode: task.endTimecode,
            outputTemplate: outputTemplate,
            useSiteSubfolder: useSiteSubfolder,
            finalProgress: task.progress,
            lastDownloadSpeed: task.downloadSpeed,
            commandPreview: commandPreview
        )
        modelContext.insert(record)
        return saveContext()
    }

    /// 中文注释：更新历史记录中的缩略图地址，确保历史卡片可展示封面。
    func updateThumbnail(for historyID: UUID, thumbnailURL: URL?) {
        guard let record = fetchRecord(id: historyID) else { return }
        record.thumbnailURLString = thumbnailURL?.absoluteString
        _ = saveContext()
    }

    /// 中文注释：把一条记录更新为下载成功，并写入最终文件路径等结果信息。
    func markSuccess(
        historyID: UUID,
        task: MediaDownloaderTask,
        outputFolderURL: URL,
        outputTemplate: String,
        useSiteSubfolder: Bool
    ) {
        guard let record = fetchRecord(id: historyID) else { return }
        update(record: record, from: task, outputFolderURL: outputFolderURL, outputTemplate: outputTemplate, useSiteSubfolder: useSiteSubfolder)
        record.status = .success
        record.finishedAt = Date()
        record.finalProgress = 1
        record.errorSummary = nil
        _ = saveContext()
    }

    /// 中文注释：把一条记录更新为下载失败，并保存失败摘要方便下次查看。
    func markFailure(
        historyID: UUID,
        task: MediaDownloaderTask,
        outputFolderURL: URL,
        outputTemplate: String,
        useSiteSubfolder: Bool,
        errorSummary: String?
    ) {
        guard let record = fetchRecord(id: historyID) else { return }
        update(record: record, from: task, outputFolderURL: outputFolderURL, outputTemplate: outputTemplate, useSiteSubfolder: useSiteSubfolder)
        record.status = .failed
        record.finishedAt = Date()
        record.errorSummary = errorSummary
        _ = saveContext()
    }

    /// 中文注释：把一条记录更新为已停止，用于用户主动终止下载的场景。
    func markStopped(
        historyID: UUID,
        task: MediaDownloaderTask,
        outputFolderURL: URL,
        outputTemplate: String,
        useSiteSubfolder: Bool,
        errorSummary: String? = nil
    ) {
        guard let record = fetchRecord(id: historyID) else { return }
        update(record: record, from: task, outputFolderURL: outputFolderURL, outputTemplate: outputTemplate, useSiteSubfolder: useSiteSubfolder)
        record.status = .stopped
        record.finishedAt = Date()
        if let errorSummary, errorSummary.isEmpty == false {
            record.errorSummary = errorSummary
        }
        _ = saveContext()
    }

    /// 中文注释：删除指定历史记录。
    func deleteRecord(id: UUID) {
        guard let record = fetchRecord(id: id) else { return }
        modelContext.delete(record)
        _ = saveContext()
    }

    /// 中文注释：批量删除历史记录，返回实际删除的条数。
    @discardableResult
    func deleteRecords(ids: Set<UUID>) -> Int {
        guard ids.isEmpty == false else { return 0 }
        let records = fetchRecords(ids: ids)
        for record in records {
            modelContext.delete(record)
        }
        let saved = saveContext()
        return saved ? records.count : 0
    }

    /// 中文注释：按标识读取单条历史记录，供界面操作时回查原始数据。
    func record(for id: UUID) -> MediaDownloadHistoryRecord? {
        fetchRecord(id: id)
    }

    /// 中文注释：根据文件路径刷新记录的文件存在状态，避免展示过期结果。
    private func refreshFileExistence(for records: [MediaDownloadHistoryRecord]) {
        var didChange = false
        for record in records {
            let exists = fileExists(atPath: record.outputFilePath)
            if record.fileExists != exists {
                record.fileExists = exists
                didChange = true
            }
        }

        if didChange {
            _ = saveContext()
        }
    }

    /// 中文注释：统一把任务快照回写到历史记录，避免多处分散赋值。
    private func update(
        record: MediaDownloadHistoryRecord,
        from task: MediaDownloaderTask,
        outputFolderURL: URL,
        outputTemplate: String,
        useSiteSubfolder: Bool
    ) {
        record.sourceURL = task.url
        record.title = task.title
        record.outputFolderPath = outputFolderURL.path
        record.outputFilePath = task.outputFileURL?.path
        record.thumbnailURLString = task.thumbnailURL?.absoluteString
        record.extractorKey = ExtractorKey.infer(from: task.url)
        record.fileExists = fileExists(at: task.outputFileURL)
        record.qualityRawValue = task.quality.rawValue
        record.containerRawValue = task.container.rawValue
        record.audioOnly = task.audioOnly
        record.useCustomFormat = task.useCustomFormat
        record.customFormat = task.customFormat
        record.downloadSubtitles = task.downloadSubtitles
        record.downloadThumbnail = task.downloadThumbnail
        record.downloadMetadata = task.downloadMetadata
        record.useBrowserCookies = task.useBrowserCookies
        record.browserCookieSourceRawValue = task.browserCookieSource.rawValue
        record.codecPreferenceRawValue = task.codecPreference.rawValue
        record.startTimecode = task.startTimecode
        record.endTimecode = task.endTimecode
        record.outputTemplate = outputTemplate
        record.useSiteSubfolder = useSiteSubfolder
        record.finalProgress = task.progress
        record.lastDownloadSpeed = task.downloadSpeed
    }

    /// 中文注释：按唯一标识获取单条历史记录（使用 Predicate 过滤，避免全表扫描）。
    private func fetchRecord(id: UUID) -> MediaDownloadHistoryRecord? {
        var descriptor = FetchDescriptor<MediaDownloadHistoryRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// 中文注释：批量按标识获取历史记录，供批量删除使用。
    private func fetchRecords(ids: Set<UUID>) -> [MediaDownloadHistoryRecord] {
        let descriptor = FetchDescriptor<MediaDownloadHistoryRecord>()
        guard let allRecords = try? modelContext.fetch(descriptor) else { return [] }
        return allRecords.filter { ids.contains($0.id) }
    }

    /// 中文注释：判断某个文件 URL 是否真实存在于磁盘。
    private func fileExists(at url: URL?) -> Bool {
        guard let url else { return false }
        return fileExists(atPath: url.path)
    }

    /// 中文注释：判断某个路径是否真实存在于磁盘。
    private func fileExists(atPath path: String?) -> Bool {
        guard let path, path.isEmpty == false else { return false }
        return fileManager.fileExists(atPath: path)
    }

    /// 中文注释：统一保存 `ModelContext`，避免调用方重复处理保存异常。
    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            logger.error("保存媒体下载历史失败: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
            return false
        }
    }
}
