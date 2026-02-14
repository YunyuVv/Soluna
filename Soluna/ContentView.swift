//
//  ContentView.swift
//  Soluna
//
//  Created by 王鹏龙 on 2026/2/13.
//

import SwiftUI

struct ContentView: View {
    // 左侧菜单当前选中项。
    @State private var selectedMenu: AppMenuItem? = .downloads
    // 全局应用状态。
    @State private var appState = AppState()

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedMenu: $selectedMenu)
        } detail: {
            switch selectedMenu {
            case .downloads:
                DownloadPanelView(model: appState.downloadModel)
            case .settings:
                SettingsView(settings: appState.settings)
            case .logs:
                LogView(store: appState.logStore)
            case .none:
                DownloadPanelView(model: appState.downloadModel)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    ContentView()
}
