//
//  DownloadPanelView.swift
//  Soluna
//

import SwiftUI

/// 右侧下载页面（单个下载）。
struct DownloadPanelView: View {
    @Bindable var model: DownloadViewModel
    @State private var showRemoveConfirm = false
    @State private var pendingRemoveTaskID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                inputSection
                qualitySection
                renameSection
                clipSection
                actionSection
                taskListSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("下载")
        .sheet(isPresented: $model.showTaskLog) {
            if let task = selectedTask {
                TaskLogView(task: task)
            }
        }
        .confirmationDialog("移除任务", isPresented: $showRemoveConfirm) {
            Button("仅移除记录", role: .destructive) {
                if let id = pendingRemoveTaskID {
                    model.removeTask(id: id, deleteFile: false)
                }
            }
            Button("删除文件并移除", role: .destructive) {
                if let id = pendingRemoveTaskID {
                    model.removeTask(id: id, deleteFile: true)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("是否同时删除已下载的文件？")
        }
    }

    private var headerSection: some View {
        HStack {
            Text("YouTube")
                .font(.title3)
                .bold()
            Spacer()
            Button {
                // 预留主题/皮肤按钮。
            } label: {
                Image(systemName: "paintpalette")
            }
            .buttonStyle(.plain)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("单个下载")
                .font(.headline)

            TextField("在此粘贴 YouTube 链接…", text: $model.url)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit {
                    model.startDownload()
                }
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("清晰度")
                .font(.headline)
            Picker("清晰度", selection: $model.quality) {
                ForEach(VideoQuality.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text("输出格式")
                .font(.headline)
            Picker("输出格式", selection: $model.outputFormat) {
                ForEach(OutputFormat.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var renameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件名（可选）")
                .font(.headline)
            TextField("不填则使用原始名称", text: $model.outputName)
                .textFieldStyle(.roundedBorder)
            Text("仅填写名称，不含扩展名。实际保存为 <名称>.%(ext)s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var clipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选段下载（可选）")
                .font(.headline)
            HStack(spacing: 12) {
                TextField("开始时间 例如 01:00(分:秒)", text: $model.clipStart)
                    .textFieldStyle(.roundedBorder)
                TextField("结束时间 例如 11:00(分:秒)", text: $model.clipEnd)
                    .textFieldStyle(.roundedBorder)
            }
            Text("不填写则下载完整视频。支持 MM:SS 或 HH:MM:SS。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            Button {
                model.startDownload()
            } label: {
                Label(model.isDownloading ? "下载中…" : "开始下载", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.borderedProminent)
            .disabled(false)

            Button(model.isPaused ? "继续" : "暂停") {
                if model.isPaused {
                    model.resumeDownload()
                } else {
                    model.pauseDownload()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!model.isDownloading)

            Button("取消") {
                model.cancelDownload()
            }
            .buttonStyle(.bordered)
            .disabled(!model.isDownloading)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.status)
                    .foregroundStyle(.secondary)
                if !model.ytDlpPath.isEmpty {
                    Text(model.ytDlpPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var taskListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("下载队列")
                .font(.headline)
            if model.tasks.isEmpty {
                Text("暂无任务")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.tasks) { task in
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            ThumbnailView(urlString: task.thumbnailURL, isLoading: task.isThumbnailLoading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Text(task.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.currentTaskID == task.id && task.status == "下载中…" {
                                Button(model.isPaused ? "继续" : "暂停") {
                                    if model.isPaused {
                                        model.resumeTask(id: task.id)
                                    } else {
                                        model.pauseTask(id: task.id)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            Button("取消") {
                                model.cancelTask(id: task.id)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.currentTaskID == task.id && !model.isDownloading)
                            Button("详细日志") {
                                model.selectedTaskID = task.id
                                model.showTaskLog = true
                            }
                            .buttonStyle(.bordered)
                            Button("移除") {
                                pendingRemoveTaskID = task.id
                                showRemoveConfirm = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.currentTaskID == task.id)
                        }
                        ProgressView(value: task.progress)
                        HStack {
                            Text("\(Int(task.progress * 100))%")
                            if !task.speedText.isEmpty {
                                Text(task.speedText)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
    }

    private var selectedTask: DownloadTask? {
        guard let id = model.selectedTaskID else { return nil }
        return model.tasks.first(where: { $0.id == id })
    }
}

private struct ThumbnailView: View {
    let urlString: String
    let isLoading: Bool

    var body: some View {
        Group {
            if let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 64, height: 36)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
