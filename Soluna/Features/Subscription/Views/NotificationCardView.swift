//
//  NotificationCardView.swift
//  Soluna
//

import SwiftUI
import AppKit

/// `NotificationCardView` 的作用：收件箱中的单条新视频通知卡片。
/// 用户可一键把视频加入本项目下载队列，或打开原页面、标记已处理、删除。
struct NotificationCardView: View {
    let notification: VideoNotificationSnapshot
    let onDownload: () -> Void
    let onOpen: () -> Void
    let onMarkHandled: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(notification.channelTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(notification.publishedAt.formatted(.relative(presentation: .named)),
                      systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 8)

            actionButtons
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    /// 中文注释：缩略图，无图时用占位符。
    @ViewBuilder
    private var thumbnail: some View {
        if let urlString = notification.thumbnailURLString, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color(nsColor: .quaternaryLabelColor).opacity(0.18)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack {
                Color(nsColor: .quaternaryLabelColor).opacity(0.18)
                Image(systemName: "play.rectangle")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 104, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// 中文注释：右侧操作区——下载为主按钮，其余为图标按钮。
    private var actionButtons: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button(action: onDownload) {
                Label("下载", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("加入下载队列并跳转到下载页")

            HStack(spacing: 6) {
                iconButton("arrow.up.right.square", help: "浏览器打开原页面", action: onOpen)
                iconButton("checkmark.circle", help: "标记已处理", action: onMarkHandled)
                iconButton("trash", help: "删除", tint: .red, action: onDelete)
            }
        }
    }

    /// 中文注释：统一样式的圆形图标按钮。
    private func iconButton(_ systemName: String,
                            help: String,
                            tint: Color = .secondary,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.22))
                )
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
