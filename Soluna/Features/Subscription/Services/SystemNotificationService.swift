//
//  SystemNotificationService.swift
//  Soluna
//

import Foundation
import UserNotifications
import AppKit
import os

@MainActor
/// `SystemNotificationService` 的作用：封装本地通知授权与发送，点击通知即可在 userInfo 中拿到视频链接。
/// 同时作为 `UNUserNotificationCenterDelegate`：保证 App 在前台时也能弹出横幅+声音（否则 macOS 默认会抑制）。
final class SystemNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: "Soluna", category: "Notification")
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        // 中文注释：设置 delegate 是「前台也能弹横幅」的关键——不设的话 App 在前台时通知只会静默进通知中心。
        center.delegate = self
    }

    /// 中文注释：进入订阅功能时申请一次授权，后续发送不再弹窗。
    func requestAuthorizationIfNeeded() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                self.logger.error("通知授权失败: \(error.localizedDescription, privacy: .public)")
            }
            if !granted {
                self.logger.warning("用户未授权本地通知，频道更新将只显示在收件箱")
            }
        }
    }

    func notifyNewVideo(channelTitle: String, videoTitle: String, videoURLString: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(channelTitle) 更新了"
        content.body = videoTitle
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = ["videoURL": videoURLString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                self.logger.error("发送通知失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 中文注释：下载完成时发送系统通知，点击可在 Finder 中定位文件。
    func notifyDownloadFinished(title: String, fileURL: URL?) {
        let content = UNMutableNotificationContent()
        content.title = "下载完成"
        content.body = title
        content.sound = .default
        content.interruptionLevel = .active
        if let fileURL {
            content.userInfo = ["fileURL": fileURL.path]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                self.logger.error("发送下载完成通知失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 中文注释：下载失败时发送系统通知，便于用户及时发现并处理。
    func notifyDownloadFailed(title: String, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "下载失败"
        content.body = "\(title) — \(reason)"
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                self.logger.error("发送下载失败通知失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 中文注释：用「真实视频」发送一条测试通知（标题=频道更新、正文=视频标题），点击可打开视频。
    /// 回调返回是否成功以及失败原因，供 UI 给出明确反馈。
    func sendTestNotification(channelTitle: String,
                             videoTitle: String,
                             videoURLString: String,
                             completion: @escaping @Sendable (Bool, String?) -> Void) {
        // 中文注释：先查询当前授权状态，未授权时直接反馈原因，避免用户以为功能坏了。
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            guard status == .authorized || status == .provisional else {
                let reason: String
                switch status {
                case .denied:
                    reason = "系统通知权限被拒绝，请到「系统设置 → 通知 → Soluna」中开启「允许通知」。"
                case .notDetermined:
                    reason = "尚未授权通知，请重新进入订阅页触发授权，或到系统设置中开启。"
                default:
                    reason = "当前通知权限不可用，请到「系统设置 → 通知 → Soluna」中检查。"
                }
                self.logger.warning("测试通知未发送：\(reason, privacy: .public)")
                completion(false, reason)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "\(channelTitle) 更新了（测试）"
            content.body = videoTitle
            content.sound = .default
            content.interruptionLevel = .active
            content.userInfo = ["videoURL": videoURLString]
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            self.center.add(request) { error in
                if let error {
                    self.logger.error("测试通知发送失败: \(error.localizedDescription, privacy: .public)")
                    completion(false, error.localizedDescription)
                } else {
                    completion(true, nil)
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 中文注释：App 在前台时收到通知，明确要求系统「弹横幅 + 播声音 + 进列表」，否则默认会被抑制。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// 中文注释：用户点击通知横幅时，若带有视频链接则用默认浏览器打开；若是本地下载文件则定位到 Finder。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["videoURL"] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        } else if let path = userInfo["fileURL"] as? String {
            let fileURL = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        }
        completionHandler()
    }
}
