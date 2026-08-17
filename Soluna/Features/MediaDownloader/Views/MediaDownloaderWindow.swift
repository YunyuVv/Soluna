//
//  MediaDownloaderWindow.swift
//  Soluna
//
//  Created by Codex on 2026/3/15.
//

import SwiftUI
import AppKit
import SwiftData
import AVKit

/// `MediaDownloaderSection` 的作用：定义媒体下载窗口的左侧导航分区。
enum MediaDownloaderSection: String, CaseIterable, Identifiable {
    case download
    case history
    case settings
    case status
    case subscription

    var id: String { rawValue }

    /// 中文注释：返回左侧菜单展示标题。
    var title: String {
        switch self {
        case .download: return "下载"
        case .history: return "下载历史"
        case .settings: return "yt-dlp 设置"
        case .status: return "运行状态"
        case .subscription: return "订阅"
        }
    }

    /// 中文注释：返回菜单图标。
    var icon: String {
        switch self {
        case .download: return "arrow.down.circle"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        case .status: return "checkmark.seal"
        case .subscription: return "bell"
        }
    }
}

/// `MediaDownloaderWindow` 的作用：提供 yt-dlp 媒体下载的主窗口与分区布局。
struct MediaDownloaderWindow: View {
    @Environment(\.modelContext) private var modelContext
    @State var viewModel = MediaDownloaderViewModel()
    @State private var subscriptionViewModel = SubscriptionViewModel()
    @State var selectedSection: MediaDownloaderSection = .download
    @State private var queueLayout: MediaQueueLayout = .grid
    @State private var logTarget: MediaLogTarget?
    @State private var showCommandLogSheet: Bool = false
    @State private var deleteTarget: MediaDeleteTarget?
    @State var historyDeleteTarget: MediaHistoryDeleteTarget?
    @State var mediaPlayTarget: MediaPlayTarget?
    /// 中文注释：播放列表解析结果，用于驱动「选择下载条目」弹窗。
    @State var playlistTarget: MediaPlaylistResolutionResult?
    /// 中文注释：是否正在解析播放列表（yt-dlp 进程调用中）。
    @State var isResolvingPlaylist = false
    /// 中文注释：批量操作类型，用于驱动确认对话框。
    @State var historyBatchAction: MediaHistoryBatchAction?
    @ScaledMetric private var panelPadding: CGFloat = 16
    @ScaledMetric private var cardPadding: CGFloat = 14

    /// 中文注释：构建媒体下载窗口的主布局。
    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationSplitView {
            sidebar(viewModel: viewModel)
        } detail: {
            detailContent(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1_200, minHeight: 760)
        .background(WindowIdentifierSetter(identifier: "media-downloader"))
        .onAppear {
            viewModel.configurePersistence(modelContext: modelContext)
            subscriptionViewModel.configure(modelContext: modelContext)
        }
        .sheet(item: $logTarget) { target in
            MediaDownloadLogSheet(viewModel: viewModel, taskID: target.id)
        }
        .sheet(isPresented: $showCommandLogSheet) {
            CommandLogSheet(viewModel: viewModel)
        }
        .sheet(item: $mediaPlayTarget) { target in
            MediaPlayerSheet(target: target)
        }
        .sheet(item: $playlistTarget) { result in
            PlaylistResolveSheet(result: result) { entries, _ in
                viewModel.enqueuePlaylistEntries(entries)
                playlistTarget = nil
                selectedSection = .download
            }
        }
        .confirmationDialog(
            "确认删除下载文件？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if $0 == false { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { target in
            Button("删除", role: .destructive) {
                viewModel.deleteTaskAndFile(target.id, fileURLOverride: target.fileURL)
                deleteTarget = nil
            }
            Button("取消", role: .cancel) {
                deleteTarget = nil
            }
        } message: { target in
            Text(deleteMessage(for: target))
        }
        .confirmationDialog(
            "确认删除历史记录关联文件？",
            isPresented: Binding(
                get: { historyDeleteTarget != nil },
                set: { if $0 == false { historyDeleteTarget = nil } }
            ),
            presenting: historyDeleteTarget
        ) { target in
            Button("删除", role: .destructive) {
                viewModel.deleteHistoryRecordAndFile(target.id)
                historyDeleteTarget = nil
            }
            Button("取消", role: .cancel) {
                historyDeleteTarget = nil
            }
        } message: { target in
            Text(historyDeleteMessage(for: target))
        }
    }

    /// 中文注释：渲染左侧菜单栏。
    @ViewBuilder
    private func sidebar(viewModel: MediaDownloaderViewModel) -> some View {
        List(selection: $selectedSection) {
            sidebarHeaderRow

            Section("下载") {
                sidebarRow(.download)
                sidebarRow(.history)
            }

            Section("设置") {
                sidebarRow(.settings)
            }

            Section("订阅") {
                subscriptionSidebarRow
            }

            Section("状态") {
                sidebarRow(.status)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    }

    /// 中文注释：渲染侧边栏顶部产品名称。
    private var sidebarHeaderRow: some View {
        HStack {
            Text("媒体下载")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.26, green: 0.55, blue: 0.98),
                                 Color(red: 0.35, green: 0.82, blue: 0.56),
                                 Color(red: 0.96, green: 0.70, blue: 0.24)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 4, trailing: 8))
        .listRowBackground(Color.clear)
    }

    /// 中文注释：渲染侧边栏单行。
    @ViewBuilder
    private func sidebarRow(_ section: MediaDownloaderSection) -> some View {
        Label(section.title, systemImage: section.icon)
            .tag(section)
    }

    /// 中文注释：渲染订阅分区行，待处理数量超过 0 时显示红色角标。
    private var subscriptionSidebarRow: some View {
        HStack {
            Label(MediaDownloaderSection.subscription.title, systemImage: MediaDownloaderSection.subscription.icon)
            Spacer(minLength: 0)
            if subscriptionViewModel.pendingCount > 0 {
                Text("\(subscriptionViewModel.pendingCount)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                    .foregroundStyle(.white)
            }
        }
        .tag(MediaDownloaderSection.subscription)
    }

    /// 中文注释：根据选中菜单渲染右侧内容区域。
    @ViewBuilder
    private func detailContent(viewModel: MediaDownloaderViewModel) -> some View {
        switch selectedSection {
        case .download:
            downloadPanel(viewModel: viewModel)
                .navigationTitle("下载")
        case .history:
            historyPanel(viewModel: viewModel)
                .navigationTitle("下载历史")
        case .settings:
            settingsPanel(viewModel: viewModel)
                .navigationTitle("yt-dlp 设置")
        case .status:
            statusPanel(viewModel: viewModel)
                .navigationTitle("运行状态")
        case .subscription:
            SubscriptionRootView(viewModel: subscriptionViewModel) { urlString, title, thumbnailURLString in
                // 中文注释：把订阅视频加入下载队列并跳转到下载页，用户可在下载页查看下载状态。
                viewModel.enqueueDownload(
                    urlString: urlString,
                    title: title,
                    thumbnailURL: thumbnailURLString.flatMap { URL(string: $0) }
                )
                selectedSection = .download
            }
            .navigationTitle("订阅")
        }
    }

    /// 中文注释：渲染下载历史面板（支持分页加载与批量操作）。
    @ViewBuilder
    private func historyPanel(viewModel: MediaDownloaderViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HistoryHeaderView(
                historyCount: viewModel.historyTotalCount,
                filteredCount: viewModel.filteredHistoryRecords.count,
                searchText: Binding(
                    get: { viewModel.historySearchText },
                    set: { viewModel.historySearchText = $0 }
                ),
                statusFilter: Binding(
                    get: { viewModel.historyStatusFilter },
                    set: { viewModel.historyStatusFilter = $0 }
                ),
                timeRangeFilter: Binding(
                    get: { viewModel.historyTimeRangeFilter },
                    set: { viewModel.historyTimeRangeFilter = $0 }
                ),
                siteFilterID: Binding(
                    get: { viewModel.historySiteFilterID },
                    set: { viewModel.historySiteFilterID = $0 }
                ),
                siteOptions: viewModel.historySiteOptions,
                activeFilterTags: viewModel.activeHistoryFilterTags,
                onRefresh: { viewModel.reloadHistory() },
                isBatchMode: Binding(
                    get: { viewModel.isHistoryBatchMode },
                    set: { viewModel.isHistoryBatchMode = $0 }
                ),
                selectedCount: viewModel.selectedHistoryCount,
                filteredTotal: viewModel.filteredHistoryRecords.count,
                onToggleBatchMode: { viewModel.isHistoryBatchMode.toggle() },
                onSelectAll: { viewModel.selectAllFilteredHistory() },
                onDeselectAll: { viewModel.deselectAllHistory() },
                onBatchDelete: { historyBatchAction = .delete },
                onBatchDeleteAndFiles: { historyBatchAction = .deleteAndFiles },
                onBatchRetry: { viewModel.batchRetryHistory() }
            )

            if viewModel.historyRecords.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("暂无下载历史")
                        .font(.headline)
                    Text("开始下载后，历史记录会自动保存到本地。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredHistoryRecords.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("没有匹配的历史记录")
                        .font(.headline)
                    Text("可以尝试调整搜索关键字或切换状态筛选。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.filteredHistoryRecords) { record in
                            HistoryRecordCardView(
                                record: record,
                                keyword: viewModel.historySearchText,
                                isBatchMode: viewModel.isHistoryBatchMode,
                                isSelected: viewModel.selectedHistoryIDs.contains(record.id),
                                onToggleSelect: { viewModel.toggleHistorySelection(record.id) }
                            ) { action in
                                handleHistoryAction(action, record: record, viewModel: viewModel)
                            }
                        }

                        // 加载更多按钮
                        if viewModel.historyHasMore {
                            HStack {
                                Spacer()
                                if viewModel.historyIsLoadingMore {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("加载中…")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("加载更多 (\(viewModel.historyRecords.count)/\(viewModel.historyTotalCount))") {
                                        viewModel.loadMoreHistory()
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "确认批量删除",
            isPresented: Binding(
                get: { historyBatchAction != nil },
                set: { if $0 == false { historyBatchAction = nil } }
            )
        ) {
            if historyBatchAction == .delete {
                Button("批量删除 \(viewModel.selectedHistoryCount) 条历史记录", role: .destructive) {
                    viewModel.batchDeleteHistory()
                }
            } else if historyBatchAction == .deleteAndFiles {
                Button("批量删除 \(viewModel.selectedHistoryCount) 条历史记录及文件", role: .destructive) {
                    viewModel.batchDeleteHistoryAndFiles()
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            if historyBatchAction == .delete {
                Text("仅删除历史记录，不会删除已下载的本地文件。此操作不可撤销。")
            } else if historyBatchAction == .deleteAndFiles {
                Text("将同时删除历史记录和本地已下载的文件。此操作不可撤销。")
            }
        }
    }

    /// 中文注释：渲染下载任务面板。
    @ViewBuilder
    private func downloadPanel(viewModel: MediaDownloaderViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                Section {
                    QueueSectionView(
                        viewModel: viewModel,
                        queueLayout: $queueLayout,
                        onShowCommandLogs: { showCommandLogSheet = true },
                        onClearCommandLogs: { viewModel.clearCommandLogs() },
                        onAction: { action, task in
                            handleTaskAction(action, task: task, viewModel: viewModel)
                        }
                    )
                } header: {
                    TopActionView(
                        viewModel: viewModel,
                        onDownload: { addAndStart(viewModel: viewModel) },
                        onResolvePlaylist: { resolvePlaylist() },
                        isResolvingPlaylist: isResolvingPlaylist
                    )
                    .padding(.bottom, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .padding(panelPadding)
        }
    }

    /// 中文注释：渲染设置面板。
    @ViewBuilder
    private func settingsPanel(viewModel: MediaDownloaderViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("yt-dlp 设置")
                .font(.title3.weight(.semibold))

            Form {
                Section("输出目录") {
                    HStack(spacing: 8) {
                        Button("选择目录") {
                            chooseOutputFolder(viewModel: viewModel)
                        }
                        .buttonStyle(.bordered)

                        Button("打开目录") {
                            viewModel.openOutputFolder()
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.outputFolderURL == nil)
                    }

                    Text(viewModel.outputFolderDisplay.isEmpty ? "未选择目录，将使用默认下载文件夹" : viewModel.outputFolderDisplay)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Section("命名与目录") {
                    Toggle("按站点自动分目录", isOn: Binding(
                        get: { viewModel.useSiteSubfolder },
                        set: { viewModel.useSiteSubfolder = $0 }
                    ))

                    LabeledContent("命名模板") {
                        TextField("%(title)s.%(ext)s", text: Binding(
                            get: { viewModel.outputTemplate },
                            set: { viewModel.outputTemplate = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                    }

                    Text("支持 yt-dlp 模板变量，如 %(title)s、%(uploader)s。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("登录态") {
                    Toggle("使用浏览器 Cookies", isOn: Binding(
                        get: { viewModel.useBrowserCookies },
                        set: { viewModel.useBrowserCookies = $0 }
                    ))

                    if viewModel.useBrowserCookies {
                        Picker("浏览器", selection: Binding(
                            get: { viewModel.browserCookieSource },
                            set: { viewModel.browserCookieSource = $0 }
                        )) {
                            ForEach(BrowserCookieSource.allCases) { source in
                                Text(source.title).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200, alignment: .leading)
                        Text("部分站点需要登录态才能下载，启用后会读取本机浏览器 Cookies。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("附加资源") {
                    Toggle("下载字幕", isOn: Binding(
                        get: { viewModel.downloadSubtitles },
                        set: { viewModel.downloadSubtitles = $0 }
                    ))

                    Toggle("下载封面", isOn: Binding(
                        get: { viewModel.downloadThumbnail },
                        set: { viewModel.downloadThumbnail = $0 }
                    ))

                    Toggle("保存元数据", isOn: Binding(
                        get: { viewModel.downloadMetadata },
                        set: { viewModel.downloadMetadata = $0 }
                    ))
                }

                Section("通知") {
                    Toggle("下载完成/失败发送系统通知", isOn: Binding(
                        get: { MediaDownloaderSettings.downloadNotifyEnabled },
                        set: { newValue in
                            MediaDownloaderSettings.downloadNotifyEnabled = newValue
                            if newValue { viewModel.requestNotificationAuthorizationIfNeeded() }
                        }
                    ))
                    Text("下载结束（成功或失败）时弹出系统通知，点击可定位到下载文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("格式") {
                    Toggle("使用自定义格式", isOn: Binding(
                        get: { viewModel.useCustomFormat },
                        set: { viewModel.useCustomFormat = $0 }
                    ))

                    if viewModel.useCustomFormat {
                        LabeledContent("格式表达式") {
                            TextField("例如: bestvideo+bestaudio", text: Binding(
                                get: { viewModel.customFormat },
                                set: { viewModel.customFormat = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                        }
                        Text("将直接传递给 yt-dlp 的 -f 参数。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("订阅更新") {
                    Picker("检查间隔", selection: Binding(
                        get: { SubscriptionSettings.pollIntervalMinutes },
                        set: { UserDefaults.standard.set($0, forKey: SubscriptionSettings.pollIntervalKey) }
                    )) {
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("1 小时").tag(60)
                        Text("2 小时").tag(120)
                        Text("6 小时").tag(360)
                    }
                    .pickerStyle(.menu)

                    Toggle("发现新视频时通知", isOn: Binding(
                        get: { SubscriptionSettings.notifyEnabled },
                        set: { UserDefaults.standard.set($0, forKey: SubscriptionSettings.notifyEnabledKey) }
                    ))

                    Stepper("并发检查数：\(SubscriptionSettings.maxConcurrentFetches)", value: Binding(
                        get: { SubscriptionSettings.maxConcurrentFetches },
                        set: { UserDefaults.standard.set($0, forKey: SubscriptionSettings.maxConcurrentKey) }
                    ), in: 1...6)

                    Toggle("复制链接后自动标记已处理", isOn: Binding(
                        get: { SubscriptionSettings.copyThenMarkHandled },
                        set: { UserDefaults.standard.set($0, forKey: SubscriptionSettings.copyThenMarkKey) }
                    ))

                    Text("关闭 App 后停止检测；检查全部走公开 RSS，不读取任何账号 Cookies。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 中文注释：渲染运行状态面板。
    @ViewBuilder
    private func statusPanel(viewModel: MediaDownloaderViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("运行状态")
                .font(.title3.weight(.semibold))

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    statusBanner(viewModel: viewModel)

                    HStack(spacing: 8) {
                        Text("版本")
                            .foregroundStyle(.secondary)
                        Text(viewModel.ytDlpVersion)
                    }

                    if let path = viewModel.ytDlpPath {
                        Text(path)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("请使用 brew install yt-dlp 安装")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            if viewModel.statusMessage.isEmpty == false {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(viewModel.isError ? .red : .secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 中文注释：渲染下载页顶部输入区域。
    private struct TopActionView: View {
        @Bindable var viewModel: MediaDownloaderViewModel
        let onDownload: () -> Void
        let onResolvePlaylist: () -> Void
        let isResolvingPlaylist: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    TextField("在此粘贴视频链接...", text: $viewModel.urlText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled(true)
                        .onSubmit { onDownload() }
                    if isResolvingPlaylist {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            onResolvePlaylist()
                        } label: {
                            Label("列表", systemImage: "list.bullet.rectangle")
                        }
                        .help("解析播放列表并选择要下载的视频")
                    }
                    Button("下载") { onDownload() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                )

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("画质")
                        Picker("", selection: $viewModel.selectedQuality) {
                            Text("最佳画质").tag(VideoQualityOption.best)
                            Text("8K").tag(VideoQualityOption.q8k)
                            Text("4K").tag(VideoQualityOption.q4k)
                            Text("2K").tag(VideoQualityOption.q1440)
                            Text("1080p").tag(VideoQualityOption.q1080)
                            Text("720p").tag(VideoQualityOption.q720)
                            Text("480p").tag(VideoQualityOption.q480)
                            Text("360p").tag(VideoQualityOption.q360)
                            Text("240p").tag(VideoQualityOption.q240)
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 6) {
                        Text("格式")
                        Picker("", selection: $viewModel.selectedContainer) {
                            Text("自动").tag(VideoContainerOption.auto)
                            Text("mp4").tag(VideoContainerOption.mp4)
                            Text("mkv").tag(VideoContainerOption.mkv)
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle("仅下载音频", isOn: $viewModel.audioOnly)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("编码偏好")
                        Picker("", selection: $viewModel.codecPreference) {
                            Text(VideoCodecPreference.source.title).tag(VideoCodecPreference.source)
                            Text(VideoCodecPreference.h264.title).tag(VideoCodecPreference.h264)
                        }
                        .pickerStyle(.menu)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("时间范围")
                    TimecodeInputField(title: "起始", text: $viewModel.startTimeInput)
                    Text("到")
                        .foregroundStyle(.secondary)
                    TimecodeInputField(title: "结束", text: $viewModel.endTimeInput)
                    Text("输入数字自动格式化，例如 101 → 00:01:01")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    /// 中文注释：渲染下载队列区域。
    private struct QueueSectionView: View {
        @Bindable var viewModel: MediaDownloaderViewModel
        @Binding var queueLayout: MediaQueueLayout
        let onShowCommandLogs: () -> Void
        let onClearCommandLogs: () -> Void
        let onAction: (MediaTaskAction, MediaDownloaderTask) -> Void

        var body: some View {
            VStack(spacing: 12) {
                QueueHeaderView(
                    queueLayout: $queueLayout,
                    commandLogs: viewModel.commandLogs,
                    onShowCommandLogs: onShowCommandLogs,
                    onClearCommandLogs: onClearCommandLogs
                ) {
                    viewModel.clearFinishedTasks()
                }

                if viewModel.tasks.isEmpty {
                    emptyStateView
                } else {
                    if queueLayout == .list {
                        VStack(spacing: 10) {
                            ForEach(viewModel.tasks) { task in
                                DownloadItemView(task: task) { action in
                                    onAction(action, task)
                                }
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                            ForEach(viewModel.tasks) { task in
                                DownloadGridItemView(task: task) { action in
                                    onAction(action, task)
                                }
                            }
                        }
                    }
                }
            }
        }

        private var emptyStateView: some View {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("暂无下载任务")
                    .font(.headline)
                Text("在上方粘贴链接并开始下载")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    /// 中文注释：渲染队列头部。
    private struct QueueHeaderView: View {
        @Binding var queueLayout: MediaQueueLayout
        let commandLogs: [CommandLogEntry]
        let onShowCommandLogs: () -> Void
        let onClearCommandLogs: () -> Void
        let onClear: () -> Void
        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        var body: some View {
            HStack {
                Text("下载队列")
                    .font(.headline)
                Spacer()
                Button {
                    queueLayout = .list
                } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.plain)
                Button {
                    queueLayout = .grid
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                Menu {
                    Button("查看全部日志") {
                        onShowCommandLogs()
                    }
                    Button("清空日志") {
                        onClearCommandLogs()
                    }
                    .disabled(commandLogs.isEmpty)
                    Divider()
                    if commandLogs.isEmpty {
                        Text("暂无日志")
                    } else {
                        ForEach(commandLogs.suffix(20)) { entry in
                            Button(menuTitle(for: entry)) { }
                                .disabled(true)
                        }
                    }
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.plain)
                Button {
                    onClear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
        }

        /// 中文注释：拼接日志菜单行标题。
        private func menuTitle(for entry: CommandLogEntry) -> String {
            let time = Self.timeFormatter.string(from: entry.timestamp)
            let message = entry.message.count > 80 ? String(entry.message.prefix(80)) + "…" : entry.message
            return "\(time) [\(entry.type)] \(message)"
        }
    }

    /// 中文注释：处理任务操作菜单的具体行为。
    private func handleTaskAction(_ action: MediaTaskAction, task: MediaDownloaderTask, viewModel: MediaDownloaderViewModel) {
        switch action {
        case .toggleRun:
            if task.status == .running {
                viewModel.stopTask(task.id)
            } else {
                viewModel.restartTask(task.id)
            }
        case .openFolder:
            viewModel.openFolder(for: task)
        case .playFile:
            handlePlay(fileURL: viewModel.playableFileURL(for: task), title: task.title.isEmpty ? task.url : task.title)
        case .viewLog:
            logTarget = MediaLogTarget(id: task.id)
        case .copyURL:
            copyURL(task.url)
        case .retry:
            viewModel.restartTask(task.id)
        case .openURL:
            openURL(task.url)
        case .copyCommand:
            copyText(viewModel.commandString(for: task))
        case .downloadThumbnail:
            viewModel.downloadCover(for: task)
        case .deleteTask:
            viewModel.deleteTask(task.id)
        case .deleteTaskAndFile:
            let info = viewModel.deleteFileInfo(for: task)
            deleteTarget = MediaDeleteTarget(id: task.id, fileURL: info.url, isInferred: info.isInferred)
        }
    }

    /// 中文注释：生成删除确认提示文本。
    private func deleteMessage(for target: MediaDeleteTarget) -> String {
        let path = target.fileURL?.path ?? "未找到文件路径"
        if target.isInferred {
            return "将从队列删除并尝试删除本地文件（按规则推断）：\n\(path)"
        }
        return "将从队列删除并删除本地文件：\n\(path)"
    }

    /// 中文注释：生成历史记录删除文件确认提示文本。
    private func historyDeleteMessage(for target: MediaHistoryDeleteTarget) -> String {
        let path = target.fileURL?.path ?? "未找到文件路径"
        return "将删除历史记录，并尝试删除本地文件：\n\(path)"
    }

}

/// `HistoryHeaderView` 的作用：渲染下载历史页面的顶部标题、搜索筛选以及批量操作控件。
private struct HistoryHeaderView: View {
    let historyCount: Int
    let filteredCount: Int
    @Binding var searchText: String
    @Binding var statusFilter: MediaDownloadHistoryFilter
    @Binding var timeRangeFilter: MediaDownloadHistoryTimeRangeFilter
    @Binding var siteFilterID: String
    let siteOptions: [MediaDownloadHistorySiteOption]
    let activeFilterTags: [String]
    let onRefresh: () -> Void

    // 批量操作绑定
    @Binding var isBatchMode: Bool
    let selectedCount: Int
    let filteredTotal: Int
    let onToggleBatchMode: () -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onBatchDelete: () -> Void
    let onBatchDeleteAndFiles: () -> Void
    let onBatchRetry: () -> Void

    /// 中文注释：构建下载历史顶部栏布局。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下载历史")
                        .font(.title3.weight(.semibold))
                    Text(summaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if isBatchMode {
                    // 批量操作工具栏
                    HStack(spacing: 8) {
                        Text("已选 \(selectedCount) 条")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.accentColor)

                        Button(selectedCount == filteredTotal ? "取消全选" : "全选") {
                            if selectedCount == filteredTotal {
                                onDeselectAll()
                            } else {
                                onSelectAll()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Menu("批量操作") {
                            Button("批量重新下载") { onBatchRetry() }
                                .disabled(selectedCount == 0)
                            Divider()
                            Button("批量删除历史", role: .destructive) { onBatchDelete() }
                                .disabled(selectedCount == 0)
                            Button("批量删除历史及文件", role: .destructive) { onBatchDeleteAndFiles() }
                                .disabled(selectedCount == 0)
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(selectedCount == 0)

                        Button("完成") {
                            onToggleBatchMode()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("批量管理") {
                            onToggleBatchMode()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("刷新") {
                            onRefresh()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if isBatchMode == false {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索标题、链接或站点", text: $searchText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled(true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    )

                    Picker("状态", selection: $statusFilter) {
                        ForEach(MediaDownloadHistoryFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150, alignment: .leading)

                    Picker("时间", selection: $timeRangeFilter) {
                        ForEach(MediaDownloadHistoryTimeRangeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130, alignment: .leading)

                    Picker("站点", selection: $siteFilterID) {
                        ForEach(siteOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150, alignment: .leading)
                }

                if activeFilterTags.isEmpty == false {
                    HistoryFilterTagsView(tags: activeFilterTags)
                }
            }
        }
    }

    /// 中文注释：生成历史总数与筛选命中数的说明文本。
    private var summaryText: String {
        if historyCount == filteredCount {
            return "共 \(historyCount) 条记录"
        }
        return "共 \(historyCount) 条记录，当前筛选命中 \(filteredCount) 条"
    }
}

/// `HistoryFilterTagsView` 的作用：展示当前历史筛选条件的统计标签。
private struct HistoryFilterTagsView: View {
    let tags: [String]

    /// 中文注释：构建筛选标签的流式布局。
    var body: some View {
        HStack(spacing: 8) {
            Text("当前筛选")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// `MediaQueueLayout` 的作用：定义队列区域的展示布局类型。
private enum MediaQueueLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    /// 中文注释：返回布局图标名称。
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

/// `MediaLogTarget` 的作用：包装日志弹窗的目标任务标识。
private struct MediaLogTarget: Identifiable {
    let id: UUID
}

/// `MediaTaskAction` 的作用：定义任务操作菜单支持的动作。
private enum MediaTaskAction {
    case toggleRun
    case openFolder
    case playFile
    case viewLog
    case copyURL
    case retry
    case openURL
    case copyCommand
    case downloadThumbnail
    case deleteTask
    case deleteTaskAndFile
}

/// `MediaHistoryAction` 的作用：定义历史记录卡片支持的操作集合。
enum MediaHistoryAction {
    case openFolder
    case playFile
    case openSourceURL
    case copySourceURL
    case downloadThumbnail
    case retryDownload
    case deleteRecord
    case deleteRecordAndFile
}

/// `MediaHistoryBatchAction` 的作用：定义批量操作类型，用于驱动确认对话框。
enum MediaHistoryBatchAction: Equatable {
    case delete
    case deleteAndFiles
}

/// `HistoryRecordCardView` 的作用：展示单条下载历史记录及其常用操作（支持批量选择模式）。
private struct HistoryRecordCardView: View {
    let record: MediaDownloadHistorySnapshot
    let keyword: String
    var isBatchMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)?
    let onAction: (MediaHistoryAction) -> Void
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// 中文注释：构建历史记录卡片的整体布局。
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 批量模式下的选择复选框
            if isBatchMode {
                Button {
                    onToggleSelect?()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            HistoryThumbnailView(record: record)
                .frame(width: 160, height: 90)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        highlightedText(record.displayTitle, font: .headline, color: .primary, lineLimit: 2)

                        highlightedText(record.sourceURL, font: .caption, color: .secondary, lineLimit: 1)
                    }

                    Spacer(minLength: 0)

                    Text(record.status.title)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(record.status.color.opacity(0.12))
                        .foregroundStyle(record.status.color)
                        .clipShape(Capsule())
                }

                if isBatchMode == false {
                    HStack(spacing: 14) {
                        Label(record.qualityOption.title, systemImage: "sparkles.tv")
                        Label(record.audioOnly ? "仅音频" : record.containerOption.title, systemImage: "music.note")
                        Label {
                            highlightedText(record.extractorKey, font: .caption, color: .secondary, lineLimit: 1)
                        } icon: {
                            Image(systemName: "network")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        Label(createdAtText, systemImage: "calendar")
                        if let finishedAtText {
                            Label(finishedAtText, systemImage: "checkmark.circle")
                        }
                        Label(record.fileExists ? "文件仍在" : "文件不存在", systemImage: record.fileExists ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.xmark")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let outputPath = record.outputFilePath, outputPath.isEmpty == false {
                        Text(outputPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text(record.outputFolderPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let errorSummary = record.errorSummary, errorSummary.isEmpty == false, record.status == .failed || record.status == .interrupted {
                        Text(errorSummary)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }

                    HStack(spacing: 10) {
                        Button("播放") {
                            onAction(.playFile)
                        }
                        .buttonStyle(.bordered)
                        .disabled(record.fileExists == false)

                        Button("打开目录") {
                            onAction(.openFolder)
                        }
                        .buttonStyle(.bordered)

                        Button("重新下载") {
                            onAction(.retryDownload)
                        }
                        .buttonStyle(.borderedProminent)

                        Menu("更多") {
                            Button("打开原网址") { onAction(.openSourceURL) }
                            Button("复制原网址") { onAction(.copySourceURL) }
                            Button("下载封面") { onAction(.downloadThumbnail) }
                            Divider()
                            Button("删除历史", role: .destructive) { onAction(.deleteRecord) }
                            Button("删除历史及文件", role: .destructive) { onAction(.deleteRecordAndFile) }
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isBatchMode && isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isBatchMode && isSelected ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 1.5)
        )
    }

    /// 中文注释：格式化创建时间文本。
    private var createdAtText: String {
        "创建于 \(Self.dateFormatter.string(from: record.createdAt))"
    }

    /// 中文注释：格式化完成时间文本，未结束时返回空值。
    private var finishedAtText: String? {
        guard let finishedAt = record.finishedAt else { return nil }
        return "完成于 \(Self.dateFormatter.string(from: finishedAt))"
    }

    /// 中文注释：根据搜索关键字高亮显示文本中的匹配片段。
    @ViewBuilder
    private func highlightedText(_ text: String, font: Font, color: Color, lineLimit: Int) -> some View {
        Text(attributedText(for: text, color: color))
            .font(font)
            .lineLimit(lineLimit)
    }

    /// 中文注释：构建带高亮样式的富文本，未命中时保持原样。
    private func attributedText(for text: String, color: Color) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = color

        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKeyword.isEmpty == false else { return attributed }

        let lowercasedText = text.lowercased()
        let lowercasedKeyword = trimmedKeyword.lowercased()
        var searchStart = lowercasedText.startIndex

        while let range = lowercasedText.range(of: lowercasedKeyword, range: searchStart..<lowercasedText.endIndex) {
            let nsRange = NSRange(range, in: text)
            if let attributedRange = Range(nsRange, in: attributed) {
                attributed[attributedRange].backgroundColor = .yellow.opacity(0.28)
                attributed[attributedRange].foregroundColor = .primary
            }
            searchStart = range.upperBound
        }

        return attributed
    }
}

/// `DownloadItemView` 的作用：渲染下载队列中的单条任务卡片。
private struct DownloadItemView: View {
    let task: MediaDownloaderTask
    let onAction: (MediaTaskAction) -> Void

    /// 中文注释：构建单条任务卡片布局。
    var body: some View {
        HStack(spacing: 12) {
            DownloadThumbnailView(task: task)
                .frame(width: 80, height: 45)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title.isEmpty ? task.url : task.title)
                    .font(.headline)
                    .lineLimit(1)

                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 4)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    onAction(.playFile)
                } label: {
                    Image(systemName: "play.rectangle")
                }
                .buttonStyle(.plain)
                .disabled(task.status != .success)

                Button {
                    onAction(.openFolder)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)

                Button {
                    onAction(.toggleRun)
                } label: {
                    Image(systemName: task.status == .running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)

                Menu {
                    Button("查看日志") { onAction(.viewLog) }
                    Button("复制 URL") { onAction(.copyURL) }
                    Button("打开网址") { onAction(.openURL) }
                    Button("复制命令") { onAction(.copyCommand) }
                    Button("下载封面") { onAction(.downloadThumbnail) }
                    Button("重新下载") { onAction(.retry) }
                    Divider()
                    Button("从队列删除", role: .destructive) { onAction(.deleteTask) }
                    Button("删除队列及文件", role: .destructive) { onAction(.deleteTaskAndFile) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 中文注释：生成状态描述文本。
    private var statusText: String {
        let percent = formattedPercent(task.progress)
        switch task.status {
        case .running:
            let speed = task.downloadSpeed.isEmpty ? "" : " • \(task.downloadSpeed)"
            return "\(percent)% • 正在下载...\(speed) • \(task.quality.title)"
        case .success:
            return "100% • 已完成 • \(task.quality.title)"
        case .stopped:
            return "\(percent)% • 已暂停 • \(task.quality.title)"
        case .pending:
            return "等待中 • \(task.quality.title)"
        case .failed:
            return "失败 • \(task.quality.title)"
        }
    }

    /// 中文注释：格式化百分比进度文本，保留两位小数。
    private func formattedPercent(_ progress: Double) -> String {
        let value = max(0, min(progress, 1.0)) * 100
        return String(format: "%.2f", value)
    }
}

/// `SkeletonShimmerView` 的作用：提供缩略图加载中的骨架闪光效果。
private struct SkeletonShimmerView: View {
    let isAnimating: Bool

    /// 中文注释：构建骨架渐变的闪光层。
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let offset = isAnimating ? width * 1.4 : -width * 1.4
            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.35),
                    Color.white.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .rotationEffect(.degrees(20))
            .offset(x: offset)
        }
        .clipped()
        .allowsHitTesting(false)
        .opacity(0.8)
    }
}

/// `DownloadGridItemView` 的作用：渲染网格布局的下载任务卡片。
private struct DownloadGridItemView: View {
    let task: MediaDownloaderTask
    let onAction: (MediaTaskAction) -> Void

    /// 中文注释：构建网格卡片布局。
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GridThumbnailView(task: task)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title.isEmpty ? task.url : task.title)
                    .font(.headline)
                    .lineLimit(2)

                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 4)

                HStack {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    actionButtons
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 中文注释：渲染操作按钮组。
    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                onAction(.playFile)
            } label: {
                Image(systemName: "play.rectangle")
            }
            .buttonStyle(.plain)
            .disabled(task.status != .success)

            Button {
                onAction(.openFolder)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)

            Button {
                onAction(.toggleRun)
            } label: {
                Image(systemName: task.status == .running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)

            Menu {
                Button("查看日志") { onAction(.viewLog) }
                Button("复制 URL") { onAction(.copyURL) }
                Button("打开网址") { onAction(.openURL) }
                Button("复制命令") { onAction(.copyCommand) }
                Button("下载封面") { onAction(.downloadThumbnail) }
                Button("重新下载") { onAction(.retry) }
                Divider()
                Button("从队列删除", role: .destructive) { onAction(.deleteTask) }
                Button("删除队列及文件", role: .destructive) { onAction(.deleteTaskAndFile) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
    }

    /// 中文注释：生成网格状态文本。
    private var statusText: String {
        let percent = formattedPercent(task.progress)
        switch task.status {
        case .running:
            let speed = task.downloadSpeed.isEmpty ? "" : " • \(task.downloadSpeed)"
            return "\(percent)% • 正在下载...\(speed) • \(task.quality.title)"
        case .success:
            return "100% • 已完成 • \(task.quality.title)"
        case .stopped:
            return "\(percent)% • 已暂停 • \(task.quality.title)"
        case .pending:
            return "等待中 • \(task.quality.title)"
        case .failed:
            return "失败 • \(task.quality.title)"
        }
    }

    /// 中文注释：格式化百分比进度文本，保留两位小数。
    private func formattedPercent(_ progress: Double) -> String {
        let value = max(0, min(progress, 1.0)) * 100
        return String(format: "%.2f", value)
    }
}

/// `DownloadThumbnailView` 的作用：统一渲染缩略图及加载骨架效果。
private struct DownloadThumbnailView: View {
    let task: MediaDownloaderTask
    @State private var isSkeletonAnimating = false

    /// 中文注释：构建缩略图视图。
    var body: some View {
        ZStack {
            if let url = task.thumbnailURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        loadingThumbnail
                    }
                }
            } else {
                loadingThumbnail
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            if isSkeletonAnimating == false {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    isSkeletonAnimating = true
                }
            }
        }
    }

    /// 中文注释：渲染缩略图加载中的骨架/渐显效果。
    private var loadingThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
            SkeletonShimmerView(isAnimating: isSkeletonAnimating)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Image(systemName: "video.fill")
                .foregroundStyle(.secondary)
                .opacity(0.6)
        }
    }
}

/// `HistoryThumbnailView` 的作用：为历史记录卡片统一渲染封面与缺省占位图。
private struct HistoryThumbnailView: View {
    let record: MediaDownloadHistorySnapshot
    @State private var isSkeletonAnimating = false

    /// 中文注释：构建历史封面的显示内容。
    var body: some View {
        ZStack {
            if let url = record.thumbnailURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            if isSkeletonAnimating == false {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    isSkeletonAnimating = true
                }
            }
        }
    }

    /// 中文注释：渲染历史记录封面的占位骨架效果。
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
            SkeletonShimmerView(isAnimating: isSkeletonAnimating)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .opacity(0.6)
        }
    }
}

/// `GridThumbnailView` 的作用：在网格布局中展示完整封面并用模糊背景铺底。
private struct GridThumbnailView: View {
    let task: MediaDownloaderTask
    @State private var isSkeletonAnimating = false

    /// 中文注释：构建网格缩略图的布局。
    var body: some View {
        ZStack {
            if let url = task.thumbnailURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        ZStack {
                            image
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 14)
                                .opacity(0.6)
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(6)
                        }
                    } else {
                        loadingThumbnail
                    }
                }
            } else {
                loadingThumbnail
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            if isSkeletonAnimating == false {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    isSkeletonAnimating = true
                }
            }
        }
    }

    /// 中文注释：渲染网格缩略图加载中的骨架/渐显效果。
    private var loadingThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
            SkeletonShimmerView(isAnimating: isSkeletonAnimating)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Image(systemName: "video.fill")
                .foregroundStyle(.secondary)
                .opacity(0.6)
        }
    }
}

/// `TimecodeInputField` 的作用：提供便捷的起止时间输入与自动格式化。
private struct TimecodeInputField: View {
    let title: String
    @Binding var text: String

    /// 中文注释：构建时间输入框布局。
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            TextField("00:00:00", text: $text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                )
                .frame(width: 110)
                .onChange(of: text) { _, newValue in
                    let normalized = MediaDownloaderViewModel.normalizeTimecodeInput(newValue) ?? ""
                    if normalized != newValue {
                        text = normalized
                    }
                }
        }
    }
}

/// `MediaDownloadLogSheet` 的作用：展示单个任务的日志详情弹窗。
private struct MediaDownloadLogSheet: View {
    @Bindable var viewModel: MediaDownloaderViewModel
    let taskID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var pageSize: Int = 200

    /// 中文注释：构建日志弹窗的布局。
    var body: some View {
        let allLines = viewModel.logLines(for: taskID)
        let hasMore = pageSize < allLines.count
        let visibleLines = Array(allLines.suffix(pageSize))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.taskTitle(for: taskID))
                    .font(.headline)
                Spacer()
                if hasMore {
                    Button("加载更多") {
                        pageSize = min(pageSize + 200, allLines.count)
                    }
                    .buttonStyle(.bordered)
                }
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if visibleLines.isEmpty {
                        Text("暂无日志输出")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: 12))
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 360)
    }
}

/// `CommandLogSheet` 的作用：展示 yt-dlp 命令日志列表。
private struct CommandLogSheet: View {
    @Bindable var viewModel: MediaDownloaderViewModel
    @Environment(\.dismiss) private var dismiss
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// 中文注释：构建命令日志弹窗布局。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("yt-dlp 命令日志")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    viewModel.clearCommandLogs()
                }
                .disabled(viewModel.commandLogs.isEmpty)
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if viewModel.commandLogs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("暂无命令日志")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.commandLogs) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Self.timeFormatter.string(from: entry.timestamp)) • \(entry.type)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
    }
}

/// `WindowIdentifierSetter` 的作用：为窗口设置唯一标识，避免重复打开多个窗口。
private struct WindowIdentifierSetter: NSViewRepresentable {
    let identifier: String

    /// 中文注释：创建用于写入窗口标识的 AppKit 视图。
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            view?.window?.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        return view
    }

    /// 中文注释：在更新阶段确保窗口标识保持一致。
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            nsView?.window?.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
    }
}

