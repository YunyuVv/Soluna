//
//  MediaDownloadHistoryFilters.swift
//  Soluna
//
//  Created by Codex on 2026/5/28.
//

import Foundation

/// `MediaDownloadHistoryFilter` 的作用：定义下载历史列表的状态筛选项。
enum MediaDownloadHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case failed
    case stopped
    case interrupted
    case running
    case pending

    var id: String { rawValue }

    /// 中文注释：返回状态筛选项的展示标题。
    var title: String {
        switch self {
        case .all: return "全部状态"
        case .success: return "已完成"
        case .failed: return "失败"
        case .stopped: return "已停止"
        case .interrupted: return "已中断"
        case .running: return "下载中"
        case .pending: return "待下载"
        }
    }

    /// 中文注释：判断筛选项是否命中指定历史状态。
    func matches(_ status: MediaDownloadHistoryStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .success:
            return status == .success
        case .failed:
            return status == .failed
        case .stopped:
            return status == .stopped
        case .interrupted:
            return status == .interrupted
        case .running:
            return status == .running
        case .pending:
            return status == .pending
        }
    }
}

/// `MediaDownloadHistoryTimeRangeFilter` 的作用：定义下载历史的时间范围筛选项。
enum MediaDownloadHistoryTimeRangeFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case last7Days
    case last30Days
    case last90Days

    var id: String { rawValue }

    /// 中文注释：返回时间范围筛选项的展示标题。
    var title: String {
        switch self {
        case .all: return "全部时间"
        case .today: return "今天"
        case .last7Days: return "近 7 天"
        case .last30Days: return "近 30 天"
        case .last90Days: return "近 90 天"
        }
    }

    /// 中文注释：判断指定时间是否命中当前时间范围筛选。
    func matches(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(date)
        case .last7Days:
            return matchesRecentDays(date, days: 7, now: now, calendar: calendar)
        case .last30Days:
            return matchesRecentDays(date, days: 30, now: now, calendar: calendar)
        case .last90Days:
            return matchesRecentDays(date, days: 90, now: now, calendar: calendar)
        }
    }

    /// 中文注释：判断指定时间是否落在最近若干天内，包含今天。
    private func matchesRecentDays(_ date: Date, days: Int, now: Date, calendar: Calendar) -> Bool {
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else {
            return true
        }
        return date >= startDate
    }
}

/// `MediaDownloadHistorySiteOption` 的作用：承载下载历史站点筛选的可选项。
struct MediaDownloadHistorySiteOption: Identifiable, Hashable {
    static let all = MediaDownloadHistorySiteOption(id: "__all__", title: "全部站点")

    let id: String
    let title: String
}
