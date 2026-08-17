//
//  PlaylistResolveSheet.swift
//  Soluna
//

import SwiftUI

/// `PlaylistResolveSheet` 的作用：展示播放列表解析结果，让用户选择「整列下载 / 仅当前视频 / 手动勾选」后入队。
struct PlaylistResolveSheet: View {
    let result: MediaPlaylistResolutionResult
    /// 中文注释：确认回调，传出最终需要下载的条目与所选模式。
    var onConfirm: (_ entries: [MediaPlaylistEntry], _ mode: MediaPlaylistDownloadMode) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: MediaPlaylistDownloadMode
    @State private var entries: [MediaPlaylistEntry]

    /// 中文注释：默认下载模式；为 nil 时按列表类型推断（列表中的视频→仅当前，其余→整列），下载页沿用此行为。
    /// 「加载全部视频」场景传 .selectedEntries，避免上千条默认整列下载。
    init(result: MediaPlaylistResolutionResult,
         defaultMode: MediaPlaylistDownloadMode? = nil,
         onConfirm: @escaping (_ entries: [MediaPlaylistEntry], _ mode: MediaPlaylistDownloadMode) -> Void) {
        self.result = result
        self.onConfirm = onConfirm
        // 中文注释：列表中的视频默认「仅当前视频」，其余默认「下载整个列表」；外部可覆盖默认模式。
        let initialMode = defaultMode
            ?? (result.playlistType == .videoInPlaylist ? .singleVideo : .fullPlaylist)
        _mode = State(initialValue: initialMode)
        _entries = State(initialValue: result.entries)
    }

    private var selectedCount: Int { entries.filter { $0.isSelected }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            modeSection
            Divider()
            contentSection
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(result.playlistType.title) · 共 \(result.entries.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("下载模式", selection: $mode) {
                ForEach(MediaPlaylistDownloadMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            Text(mode.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var contentSection: some View {
        switch mode {
        case .fullPlaylist:
            summaryRow("将下载整个列表的 \(result.entries.count) 个视频")
        case .singleVideo:
            singleVideoSection
        case .selectedEntries:
            selectedListSection
        }
    }

    private func summaryRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private var singleVideoSection: some View {
        // 中文注释：仅下载当前视频（列表链接中带 v= 的那条），否则取第一条。
        let target = result.entries.first { $0.videoID == result.currentVideoID } ?? result.entries.first
        return VStack(alignment: .leading, spacing: 6) {
            Text("仅下载当前视频：")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let target {
                HStack(spacing: 8) {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                    Text(target.displayTitle)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                Text("未找到可下载的当前视频")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var selectedListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选择 \(selectedCount) / \(entries.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全选") { entries = entries.map { var e = $0; e.isSelected = true; return e } }
                Button("全不选") { entries = entries.map { var e = $0; e.isSelected = false; return e } }
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(entries.indices, id: \.self) { idx in
                        Toggle(isOn: Binding(
                            get: { entries[idx].isSelected },
                            set: { newValue in
                                var e = entries[idx]
                                e.isSelected = newValue
                                entries[idx] = e
                            }
                        )) {
                            HStack {
                                Text(entries[idx].displayTitle)
                                    .lineLimit(1)
                                Spacer()
                                if let dur = entries[idx].durationText {
                                    Text(dur)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("开始下载") {
                onConfirm(chosenEntries(), mode)
            }
            .buttonStyle(.borderedProminent)
            .disabled(mode == .selectedEntries && selectedCount == 0)
        }
        .padding(16)
    }

    /// 中文注释：根据所选模式返回需要下载的条目。
    private func chosenEntries() -> [MediaPlaylistEntry] {
        switch mode {
        case .fullPlaylist:
            return entries
        case .selectedEntries:
            return entries.filter { $0.isSelected }
        case .singleVideo:
            if let target = entries.first(where: { $0.videoID == result.currentVideoID }) {
                return [target]
            }
            return entries.first.map { [$0] } ?? []
        }
    }
}
