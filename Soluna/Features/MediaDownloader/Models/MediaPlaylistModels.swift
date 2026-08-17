//
//  MediaPlaylistModels.swift
//  Soluna
//
//  Created by Codex on 2026/5/28.
//

import Foundation

/// `MediaPlaylistType` 的作用：定义列表链接解析后的播放列表类型。
enum MediaPlaylistType: String, CaseIterable, Identifiable {
    case none
    case playlist
    case videoInPlaylist
    case mix

    var id: String { rawValue }

    /// 中文注释：返回列表类型的展示标题。
    var title: String {
        switch self {
        case .none: return "普通视频"
        case .playlist: return "播放列表"
        case .videoInPlaylist: return "列表中的视频"
        case .mix: return "自动推荐列表"
        }
    }
}

/// `MediaPlaylistDownloadMode` 的作用：定义列表链接的下载模式。
enum MediaPlaylistDownloadMode: String, CaseIterable, Identifiable {
    case singleVideo
    case fullPlaylist
    case selectedEntries

    var id: String { rawValue }

    /// 中文注释：返回下载模式的展示标题。
    var title: String {
        switch self {
        case .singleVideo: return "仅下载当前视频"
        case .fullPlaylist: return "下载整个列表"
        case .selectedEntries: return "手动勾选要下载的视频"
        }
    }

    /// 中文注释：返回界面中给用户看的简短说明。
    var subtitle: String {
        switch self {
        case .singleVideo: return "适合只下载当前这一个视频"
        case .fullPlaylist: return "适合完整下载整个播放列表"
        case .selectedEntries: return "可以自行选择要下载的条目"
        }
    }
}

/// `MediaPlaylistEntry` 的作用：承载单个列表条目的基础信息与勾选状态。
struct MediaPlaylistEntry: Identifiable, Hashable, Sendable {
    let id: String
    let index: Int
    let videoID: String?
    let title: String
    let durationText: String?
    let uploader: String?
    let webpageURL: String?
    let thumbnailURL: URL?
    var isSelected: Bool

    /// 中文注释：返回条目的展示标题，缺失时回退为默认占位文案。
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名视频" : trimmed
    }
}

/// `MediaPlaylistResolutionResult` 的作用：承载一次列表链接解析后的完整结果。
struct MediaPlaylistResolutionResult: Identifiable, Sendable {
    let id = UUID()
    let sourceURL: String
    let title: String
    let extractorKey: String
    let playlistID: String?
    let playlistType: MediaPlaylistType
    let entries: [MediaPlaylistEntry]
    let currentVideoID: String?

    /// 中文注释：返回解析结果是否属于列表类链接。
    var isPlaylistLike: Bool {
        playlistType != .none
    }

    /// 中文注释：返回列表展示标题，缺失时回退为原始链接。
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sourceURL : trimmed
    }
}
