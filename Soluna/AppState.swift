//
//  AppState.swift
//  Soluna
//

import Observation

/// 应用级状态，聚合模型与日志。
@MainActor
@Observable
final class AppState {
    let logStore: LogStore
    let settings: SettingsStore
    let downloadModel: DownloadViewModel

    init() {
        let log = LogStore()
        let settings = SettingsStore()
        self.logStore = log
        self.settings = settings
        self.downloadModel = DownloadViewModel(logStore: log, settings: settings)
    }
}
