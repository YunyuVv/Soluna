//
//  LogView.swift
//  Soluna
//

import SwiftUI

/// 系统关键步骤日志。
struct LogView: View {
    @Bindable var store: LogStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("关键步骤日志")
                    .font(.headline)
                ScrollView {
                    Text(store.systemLog.isEmpty ? "暂无日志" : store.systemLog)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 320)
                .padding(12)
                .background(Color.gray.opacity(0.08))
                .clipShape(.rect(cornerRadius: 12))

                HStack(spacing: 12) {
                    Button("清空日志") {
                        store.clear(channel: .system)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("日志")
    }
}
