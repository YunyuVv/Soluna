//
//  SubscriptionSettingsView.swift
//  Soluna
//

import SwiftUI

/// `SubscriptionSettingsView` 的作用：可复用的订阅设置面板，订阅管理页与统一设置窗口共用。
struct SubscriptionSettingsView: View {
    @State private var pollInterval = SubscriptionSettings.pollIntervalMinutes
    @State private var maxConcurrent = SubscriptionSettings.maxConcurrentFetches
    @State private var notifyEnabled = SubscriptionSettings.notifyEnabled
    @State private var ignoreShorts = SubscriptionSettings.ignoreShorts
    @State private var ignoreLive = SubscriptionSettings.ignoreLive
    @State private var copyThenMark = SubscriptionSettings.copyThenMarkHandled

    var body: some View {
        Form {
            Section("检测") {
                Picker("轮询间隔", selection: $pollInterval) {
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("60 分钟").tag(60)
                    Text("120 分钟").tag(120)
                }
                .pickerStyle(.menu)
                Picker("并发检查数", selection: $maxConcurrent) {
                    ForEach([1, 2, 3, 4], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                Toggle("发送系统通知", isOn: $notifyEnabled)
            }
            Section("过滤") {
                Toggle("忽略 Shorts（短视频）", isOn: $ignoreShorts)
                Toggle("忽略直播 / 首播", isOn: $ignoreLive)
            }
            Section("收件箱") {
                Toggle("复制链接后自动标记已处理", isOn: $copyThenMark)
            }
        }
        .formStyle(.grouped)
        .onChange(of: pollInterval) { SubscriptionSettings.pollIntervalMinutes = $0 }
        .onChange(of: maxConcurrent) { SubscriptionSettings.maxConcurrentFetches = $0 }
        .onChange(of: notifyEnabled) { SubscriptionSettings.notifyEnabled = $0 }
        .onChange(of: ignoreShorts) { SubscriptionSettings.ignoreShorts = $0 }
        .onChange(of: ignoreLive) { SubscriptionSettings.ignoreLive = $0 }
        .onChange(of: copyThenMark) { SubscriptionSettings.copyThenMarkHandled = $0 }
    }
}
