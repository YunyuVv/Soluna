//
//  SidebarView.swift
//  Soluna
//

import SwiftUI

/// 左侧菜单栏。
struct SidebarView: View {
    @Binding var selectedMenu: AppMenuItem?

    var body: some View {
        List(selection: $selectedMenu) {
            Section("菜单") {
                ForEach(AppMenuItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .padding(.vertical, 6)
                        .tag(item)
                }
            }
        }
        .navigationTitle("ytdlp")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

/// 左侧菜单项。
enum AppMenuItem: String, CaseIterable, Identifiable {
    case downloads
    case settings
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: return "下载"
        case .settings: return "设置"
        case .logs: return "日志"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .logs: return "doc.text.magnifyingglass"
        }
    }
}
