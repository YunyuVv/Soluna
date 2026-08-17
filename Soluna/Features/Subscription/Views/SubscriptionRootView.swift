//
//  SubscriptionRootView.swift
//  Soluna
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// `SubscriptionTab` 的作用：订阅分区内的两个标签页。
enum SubscriptionTab: String, CaseIterable, Identifiable {
    case manage
    case inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manage: return "订阅管理"
        case .inbox: return "通知收件箱"
        }
    }
}

/// `SubscriptionRootView` 的作用：订阅功能的唯一入口，顶部用分段控件切换「订阅管理 / 通知收件箱」。
struct SubscriptionRootView: View {
    @Bindable var viewModel: SubscriptionViewModel
    /// 中文注释：把视频加入本项目下载队列并跳转下载页的回调（由主窗口注入）。
    var onDownload: (_ urlString: String, _ title: String?, _ thumbnailURLString: String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 中文注释：自绘分段控件——收件箱标签在有待处理通知时显示红点数量角标。
            SubscriptionTabPicker(
                selection: $viewModel.selectedTab,
                pendingCount: viewModel.pendingNotifications.count
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            switch viewModel.selectedTab {
            case .manage:
                SubscriptionManagePane(viewModel: viewModel)
            case .inbox:
                NotificationInboxPane(viewModel: viewModel, onDownload: onDownload)
            }
        }
        .navigationTitle("订阅")
        .frame(minWidth: 760, minHeight: 600)
        // 中文注释：立即检查/全部检查的结果弹窗——列出每条视频标题+链接，支持下载/浏览器打开。
        .sheet(isPresented: $viewModel.showCheckResult) {
            CheckResultSheet(viewModel: viewModel, onDownload: onDownload)
        }
        // 中文注释：测试通知的结果反馈。
        .alert("测试通知", isPresented: $viewModel.showTestNotificationResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.testNotificationMessage ?? "")
        }
    }

}

// MARK: - 自绘分段控件（支持红点角标）

/// `SubscriptionTabPicker` 的作用：仿 macOS 分段控件的两标签切换器，收件箱标签可显示红色数量角标。
private struct SubscriptionTabPicker: View {
    @Binding var selection: SubscriptionTab
    /// 中文注释：待处理通知数量，>0 时在收件箱标签上显示红点角标。
    let pendingCount: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SubscriptionTab.allCases) { tab in
                segment(for: tab)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        )
    }

    /// 中文注释：单个分段按钮，选中态填充白底+阴影，收件箱带红点角标。
    private func segment(for tab: SubscriptionTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selection = tab }
        } label: {
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                if tab == .inbox && pendingCount > 0 {
                    Text(pendingCount > 99 ? "99+" : "\(pendingCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18)
                        .frame(height: 16)
                        .background(Capsule().fill(Color.red))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : .clear)
                    .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 检查结果弹窗

/// `CheckResultSheet` 的作用：展示「立即检查/全部检查」的详细结果，每条视频可复制链接或用浏览器打开。
private struct CheckResultSheet: View {
    @Bindable var viewModel: SubscriptionViewModel
    var onDownload: (_ urlString: String, _ title: String?, _ thumbnailURLString: String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("检查结果")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(viewModel.lastCheckHeadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if viewModel.lastCheckOutcomes.isEmpty {
                        Text("没有可展示的检查内容。")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.lastCheckOutcomes) { outcome in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(outcome.channelTitle)
                                    .font(.headline)
                                if let error = outcome.errorMessage {
                                    Text("检查失败")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(.red))
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                } else {
                                    Text(outcome.newCount > 0 ? "\(outcome.newCount) 条新视频" : "暂无新视频")
                                        .font(.caption)
                                        .foregroundStyle(outcome.newCount > 0 ? .green : .secondary)
                                }
                            }

                            if outcome.errorMessage == nil {
                                ForEach(outcome.latestVideos) { video in
                                    CheckResultVideoRow(
                                        video: video,
                                        onDownload: {
                                            onDownload(video.videoURLString, video.title, nil)
                                            dismiss()
                                        },
                                        onCopy: { viewModel.copyLink(video.videoURLString) },
                                        onOpen: { viewModel.openLink(video.videoURLString) }
                                    )
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                    }

                    if viewModel.lastCheckOutcomes.contains(where: { $0.newCount == 0 && $0.errorMessage == nil }) {
                        Text("提示：首次订阅时的当前视频会作为基线标记为已处理，因此不会重复通知；只有订阅之后博主新发布的视频才会进入收件箱并提醒。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}

/// `CheckResultVideoRow` 的作用：检查结果里的单条视频行——标题 + 链接 + 复制/打开按钮。
private struct CheckResultVideoRow: View {
    let video: CheckedVideo
    let onDownload: () -> Void
    let onCopy: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if video.isNew {
                        Text("新")
                            .font(.caption2).bold()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                    }
                    Text(video.title)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                Text(video.videoURLString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button(action: onDownload) {
                    Label("下载", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("加入下载队列并跳转到下载页")

                Button { onCopy() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("复制链接")
                Button { onOpen() } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("用浏览器打开")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 订阅管理

private struct SubscriptionManagePane: View {
    @Bindable var viewModel: SubscriptionViewModel
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var showExport = false
    @State private var exportDocument: SubscriptionBackupDocument?
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    var body: some View {
        manageContent
        .sheet(isPresented: $showAdd) {
            AddSubscriptionSheet(viewModel: viewModel)
        }
        .fileExporter(
            isPresented: $showExport,
            document: exportDocument ?? SubscriptionBackupDocument(data: Data()),
            contentType: .json,
            defaultFilename: "soluna-subscriptions-\(Self.exportFilenameDate())"
        ) { result in
            if case .failure(let error) = result {
                viewModel.reportError("导出失败：\(error.localizedDescription)")
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else {
                    viewModel.reportError("导入失败：无法访问所选文件")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    if let imported = viewModel.importBackup(from: data) {
                        importMessage = "已导入 \(imported.subscriptions) 个频道、\(imported.notifications) 条通知"
                    } else {
                        importMessage = viewModel.errorMessage ?? "导入失败"
                    }
                } catch {
                    importMessage = "导入失败：\(error.localizedDescription)"
                }
                showImportAlert = true
            case .failure(let error):
                viewModel.reportError("导入失败：\(error.localizedDescription)")
            }
        }
        .alert("导入结果", isPresented: $showImportAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(importMessage ?? "")
        }
    }

    /// 中文注释：订阅管理面板的顶部工具栏（按钮栏）。抽出为独立属性以降低单个视图体的类型检查复杂度。
    @ViewBuilder
    private var manageToolbar: some View {
        HStack {
            Text("已订阅 \(viewModel.subscriptions.count) 个频道")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            // 中文注释：订阅设置（轮询间隔、过滤 Shorts/直播等）。
            Button {
                showSettings = true
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showSettings) {
                SubscriptionSettingsView()
                    .frame(width: 360)
                    .padding(8)
            }
            // 中文注释：测试通知按钮——用第一个博主的最新视频发真实通知并进收件箱；无订阅时隐藏。
            if !viewModel.subscriptions.isEmpty {
                Button {
                    Task { await viewModel.sendTestNotification() }
                } label: {
                    Label("测试通知", systemImage: "bell.badge")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await viewModel.pollNow() }
                } label: {
                    if viewModel.isCheckingAll {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("检查中")
                        }
                    } else {
                        Label("全部检查", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCheckingAll)

                Button {
                    Task { await viewModel.refreshAllChannelInfo() }
                } label: {
                    if viewModel.isRefreshingAll {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("更新中")
                        }
                    } else {
                        Label("更新全部", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRefreshingAll)
            }
            // 中文注释：备份导入/导出，避免重装或换机后丢失订阅。
            Button {
                showImport = true
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .help("从 JSON 备份文件恢复订阅与通知")

            Button {
                if let backup = viewModel.exportBackup(),
                   let data = try? JSONEncoder().encode(backup) {
                    exportDocument = SubscriptionBackupDocument(data: data)
                    showExport = true
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .help("把当前订阅与通知导出为 JSON 备份")
            .disabled(viewModel.subscriptions.isEmpty)

            Button {
                showAdd = true
            } label: {
                Label("添加订阅", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// 中文注释：订阅管理面板主内容（工具栏 + 状态条 + 列表）。抽出为独立属性以降低单个视图体的类型检查复杂度。
    @ViewBuilder
    private var manageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            manageToolbar
            manageList
        }
    }

    /// 中文注释：订阅列表（含空态）。抽出为独立属性避免单个视图体过大触发类型检查超时。
    @ViewBuilder
    private var manageList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.subscriptions) { sub in
                    subscriptionCard(for: sub)
                }
                if viewModel.subscriptions.isEmpty {
                    ContentUnavailableView(
                        "还没有订阅",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("点击右上角添加 YouTube 频道，更新会进入收件箱")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(16)
        }
    }

    /// 中文注释：为单个订阅构建卡片视图。抽成独立函数以隔离类型推断，避免 ForEach 内联闭包触发类型检查超时。
    private func subscriptionCard(for sub: ChannelSubscriptionSnapshot) -> some View {
        SubscriptionCardView(
            subscription: sub,
            isChecking: viewModel.checkingIDs.contains(sub.id),
            isRefreshing: viewModel.refreshingIDs.contains(sub.id),
            onCheckNow: { Task { await viewModel.checkNow(subscriptionID: sub.id) } },
            onRefreshInfo: { Task { await viewModel.refreshChannelInfo(id: sub.id) } },
            onRemove: { viewModel.removeSubscription(id: sub.id) },
            onOpenChannel: { viewModel.openChannel(sub) }
        )
    }

    /// 中文注释：生成导出文件名的日期后缀（yyyyMMdd）。
    private static func exportFilenameDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

}

// MARK: - 通知收件箱

private struct NotificationInboxPane: View {
    @Bindable var viewModel: SubscriptionViewModel
    var onDownload: (_ urlString: String, _ title: String?, _ thumbnailURLString: String?) -> Void
    @State private var showClearHandled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("待处理 \(viewModel.pendingNotifications.count) 条")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                // 中文注释：测试通知（真实数据+进收件箱）；无订阅时隐藏。
                if !viewModel.subscriptions.isEmpty {
                    Button {
                        Task { await viewModel.sendTestNotification() }
                    } label: {
                        Label("测试通知", systemImage: "bell.badge")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await viewModel.pollNow() }
                    } label: {
                        if viewModel.isCheckingAll {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("检查中")
                            }
                        } else {
                            Label("立即检查", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCheckingAll)
                }

                if !viewModel.pendingNotifications.isEmpty {
                    Button {
                        viewModel.markAllHandled()
                    } label: {
                        Label("全部标记已处理", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderless)
                }

                if viewModel.handledCount > 0 {
                    Button {
                        showClearHandled = true
                    } label: {
                        Label("清空已处理", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .confirmationDialog(
                        "清空已处理通知？",
                        isPresented: $showClearHandled,
                        titleVisibility: .visible
                    ) {
                        Button("清空 \(viewModel.handledCount) 条", role: .destructive) {
                            viewModel.clearHandled()
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("将删除所有已处理（已下载/已标记）的通知记录，此操作不可撤销。")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.pendingNotifications) { n in
                        NotificationCardView(
                            notification: n,
                            onDownload: {
                                onDownload(n.videoURLString, n.title, n.thumbnailURLString)
                                // 中文注释：下载后按设置可顺带标记为已处理，避免收件箱重复堆积。
                                if SubscriptionSettings.copyThenMarkHandled {
                                    viewModel.markHandled(id: n.id)
                                }
                            },
                            onOpen: { viewModel.openLink(n.videoURLString) },
                            onMarkHandled: { viewModel.markHandled(id: n.id) },
                            onDelete: { viewModel.removeNotification(id: n.id) }
                        )
                    }
                    if viewModel.pendingNotifications.isEmpty {
                        ContentUnavailableView(
                            "收件箱为空",
                            systemImage: "tray",
                            description: Text("订阅频道更新后，新视频会出现在这里，需手动处理或删除")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(16)
            }
        }
    }
}
