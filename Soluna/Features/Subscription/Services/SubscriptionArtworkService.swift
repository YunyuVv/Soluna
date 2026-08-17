//
//  SubscriptionArtworkService.swift
//  Soluna
//

import Foundation

/// `SubscriptionArtworkService` 的作用：把订阅博主头像下载到本地缓存目录，
/// 使订阅卡片离线也能显示头像，并避免每次刷新都从网络重复拉取。
enum SubscriptionArtworkService {

    /// 中文注释：头像缓存目录（Application Support/Soluna/subscription_avatars），不存在时自动创建。
    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Soluna/subscription_avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 中文注释：根据频道 ID 计算头像缓存文件路径（固定以频道 ID 命名，便于「更新信息」时覆盖）。
    static func fileURL(for channelId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(channelId).jpg")
    }

    /// 中文注释：下载头像到本地缓存。
    /// - Parameters:
    ///   - remoteURLString: 远程头像地址（可为 nil，则跳过）。
    ///   - channelId: 频道 ID，用作缓存文件名。
    ///   - force: true 时忽略已有缓存重新下载（用于「更新信息」），false 时命中缓存直接返回。
    /// - Returns: 本地文件路径字符串；无需下载或下载失败返回 nil。
    static func cacheAvatar(remoteURLString: String?, channelId: String, force: Bool = false) async -> String? {
        guard let remoteURLString, let url = URL(string: remoteURLString) else { return nil }
        let fileURL = fileURL(for: channelId)
        if !force, FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL.path
        }
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            // 中文注释：模拟浏览器 UA，降低被返回占位图的概率。
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Soluna/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }
}
