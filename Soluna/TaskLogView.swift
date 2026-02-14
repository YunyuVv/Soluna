//
//  TaskLogView.swift
//  Soluna
//

import SwiftUI

/// 任务日志详情页。
struct TaskLogView: View {
    let task: DownloadTask

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(task.title)
                        .font(.headline)
                    Text("状态：\(task.status)")
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(task.log.isEmpty ? "暂无日志" : task.log)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 320)
                    .padding(12)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 12))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("日志详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
