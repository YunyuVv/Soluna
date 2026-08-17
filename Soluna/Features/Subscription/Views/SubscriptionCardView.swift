//
//  SubscriptionCardView.swift
//  Soluna
//

import SwiftUI
import AppKit

/// `SubscriptionCardView` 的作用：订阅管理列表中的单个频道卡片。
struct SubscriptionCardView: View {
    let subscription: ChannelSubscriptionSnapshot
    /// 中文注释：该频道是否正在手动检测中。
    let isChecking: Bool
    /// 中文注释：该频道是否正在「更新信息」中。
    let isRefreshing: Bool
    let onCheckNow: () -> Void
    let onRefreshInfo: () -> Void
    let onRemove: () -> Void
    /// 中文注释：点击头像/标题时，在浏览器中打开该博主频道主页。
    let onOpenChannel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 中文注释：头像 + 标题整体作为「在浏览器打开频道」的按钮，点击即跳转博主主页；纯文本样式 + 提示文案。
            Button {
                onOpenChannel()
            } label: {
                HStack(spacing: 12) {
                    avatar
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(subscription.title)
                            .font(.headline)
                            .lineLimit(1)
                        if let error = subscription.pollErrorMessage {
                            Text("检测失败：\(error)")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        } else if let last = subscription.lastCheckedAt {
                            Text("上次检测 \(last.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("尚未检测")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .help("在浏览器中打开「\(subscription.title)」的频道主页")

            Spacer(minLength: 0)

            // 中文注释：单频道手动检测按钮，检测中显示进度并禁用。
            Button {
                onCheckNow()
            } label: {
                if isChecking {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("检测中")
                    }
                } else {
                    Label("立即检查", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isChecking)

            // 中文注释：更新博主名称/头像按钮，刷新中显示进度并禁用。
            Button {
                onRefreshInfo()
            } label: {
                if isRefreshing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("更新中")
                    }
                } else {
                    Label("更新信息", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("取消订阅", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    /// 中文注释：头像——优先显示本地缓存文件（离线可用），其次回退远程地址，最后用占位图标。
    @ViewBuilder
    private var avatar: some View {
        if let localPath = subscription.localThumbnailPath,
           let nsImage = NSImage(contentsOfFile: localPath) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else if let urlString = subscription.thumbnailURLString, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
        } else {
            Image(systemName: "person.crop.circle")
                .resizable()
                .foregroundStyle(.secondary)
        }
    }
}
