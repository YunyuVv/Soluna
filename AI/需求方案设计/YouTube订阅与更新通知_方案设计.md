# YouTube 博主订阅与更新通知 — 需求方案设计

> 文档版本：v2.0（重构：无 Cookies · 官方 RSS 轮询 · 复制链接手动下载）
> 日期：2026-07-16
> 状态：方案设计（已评审 · v1 范围已锁定）
> 项目：Soluna（macOS SwiftUI 桌面应用）
> 一句话目标：**订阅 YouTube 博主 → 博主更新视频时发出系统通知，并在应用内维护一个“通知收件箱”；每条通知必须由用户手动删除、或复制下载地址去手动下载后标记处理，才会从待处理列表中消失。**

> **v2 核心确认（本次调整）**
> 1. **不使用 Cookies**：仅做“查是否有更新”，采用 YouTube **官方 RSS 订阅源**（免鉴权、无账号绑定、几乎无封号风险）。不涉及会员内容。
> 2. **侧边栏合并**：只新增**一个「订阅」分区**，内部用**标签页**切换「订阅管理 / 通知收件箱」。
> 3. **下载改为手动**：应用**只负责通知**；卡片提供“**复制下载地址**”，用户自行到下载页面手动下载。清除通知的方式为「删除」或「标记为已处理（已下载）」。

---

## 1. 需求概述

### 1.1 背景
Soluna 当前是一个基于 `yt-dlp` 的媒体下载工具，已在 `Features/MediaDownloader` 中沉淀了链接解析、下载队列、SwiftData 本地持久化等成熟能力。

用户希望把“**发现新视频**”这一步自动化：订阅若干频道，应用帮其盯着更新，有新内容时通知，并把“通知”当作待办来管理（看到 → 删掉，或复制链接自己去下载后标记处理）。

### 1.2 目标
- 支持通过频道链接 / `@handle` / 频道 ID 订阅博主（一次性解析出频道 ID + 名称 + 头像）。
- 周期性、**无需 Cookies** 地检测订阅频道是否有“新视频”。
- 发现新视频时：① 弹出 macOS 系统通知；② 在应用内“通知收件箱”新增一条记录。
- 通知收件箱中的每条通知，**只能**通过“手动删除”或“标记为已处理（已下载）”两种动作离开待处理列表（不自动消失）。
- 每条通知卡片支持**一键复制下载地址 / 打开原视频页面**，方便用户自行下载。

### 1.3 范围
| 在范围内（v1） | 暂不在范围内 |
| --- | --- |
| 频道订阅管理（增/删/查、立即检查） | 关闭 App 后的后台常驻检测（见 §9.3 / §12） |
| **基于官方 RSS 的无 Cookies 轮询** | 使用 Cookies / 登录态 / 会员内容 |
| macOS 本地通知（UNUserNotificationCenter） | 应用内自动下载 / 复用下载队列（改为手动） |
| 单一「订阅」分区（标签页：订阅管理 / 通知收件箱） | 跨设备同步、云端订阅 |
| 通知清除：删除 / 标记已处理 + 复制下载地址 | 直播开播提醒、评论/社区帖提醒 |

---

## 2. 用户故事与功能需求（FR）

- **FR-1 添加订阅**：用户粘贴频道 URL（`https://www.youtube.com/@xxx`、`/channel/UCxxxx`）或 `@handle`；应用解析出 `channelId`（UCxxxx）、频道标题、头像，并建立订阅记录。
- **FR-2 订阅列表管理**：展示所有订阅频道卡片（头像、名称、最近检测时间、最新视频标题），支持“取消订阅”“立即检查更新”“启用/停用”。
- **FR-3 无 Cookies 轮询检测**：应用在前台运行时，按可配置间隔（默认 30 分钟）读取每个频道的**官方 RSS 源**，与上次已知视频比对。
- **FR-4 新视频 → 通知**：检测到从未记录过的新视频 ID 时，写入通知记录并发送系统通知（标题=频道名，正文=视频标题）。
- **FR-5 通知收件箱**：列表展示所有“待处理”通知（缩略图、频道、标题、发布时间、发现时间），支持按频道筛选、关键字搜索。
- **FR-6 清除方式 A — 手动删除**：用户点“删除”，通知从待处理列表移除（仅删记录，不涉及任何文件）。
- **FR-7 清除方式 B — 标记已处理（已下载）**：用户点“复制下载地址”自行下载后，点“标记已处理”，通知转 `handled` 并离开待处理列表。
- **FR-8 复制下载地址 / 打开原页面**：每条卡片一键复制视频 URL、或在浏览器打开原视频页面，供用户手动下载。
- **FR-9 去重**：同一视频 ID 对同一订阅只产生一条通知；重复轮询不重复弹通知。
- **FR-10 设置**：全局轮询间隔、是否启用系统通知、单次并发检测数。（**不再有 Cookies 相关设置**）
- **FR-11 状态徽标**：侧边栏「订阅」入口显示待处理通知数量徽标（Badge）。

**非功能需求见第 10 节。**

---

## 3. 关键设计决策（选型与取舍）

### 3.1 数据源：官方 RSS 优先，无需 Cookies（核心变更）
用户诉求是“只查是否更新、不要 Cookies、担心一直拉取被封号”。为此改为以 **YouTube 官方频道 RSS 源**为主：

```
https://www.youtube.com/feeds/videos.xml?channel_id=UCxxxxxxxx
```

该源返回频道最新约 15 条视频，每条含：`videoId`、`title`、`published`、`media:thumbnail`、原视频链接。**实测可直接匿名访问**（示例见附录 A）。

| 方案 | Cookies | 封号风险 | 负载 | 结论 |
| --- | --- | --- | --- | --- |
| **A. 官方 RSS（推荐，主）** | 不需要 | **极低**（官方公开端点、无账号绑定、纯只读 XML） | 极轻（单次几 KB） | **v1 采用** |
| B. yt-dlp `--flat-playlist` | 不需要 | 低（但比 RSS 重，偶发反爬） | 中（起进程、请求多） | **可选兜底**（仅添加订阅解析失败时用，轮询只用 RSS） |
| C. YouTube Data API v3 | 需 API Key | 低 | 轻 | 暂不做（增加配置负担） |
| D. 带 Cookies 轮询 | 需要 | **较高**（登录态被频繁请求判定异常，可能触发账号风控） | 中 | **明确排除**（用户不接受） |

**封号风险分析（回应用户担忧）**：
- **不带 Cookies = 不绑定任何 Google 账号**，因此“封号”在本方案里根本不成立——最坏情况只是**该 IP 被临时限流（HTTP 429）**，属临时、可恢复，不影响账号。
- RSS 是官方设计给客户端订阅用的端点，天生适合被周期性读取；配合**低频（≥30 分钟）+ 抖动错峰 + 限并发**，正常使用几乎不会触发限流。
- **添加订阅优先走公开 HTTP 页面解析**：`ChannelResolver` 先尝试直接从输入提取 `channelId`；否则请求该 `@handle`/链接的公开页面，从 HTML 的 `canonical` / `og:url` 中提取 `channel/UC...`，**全程无需 yt-dlp、无需 Cookies**。yt-dlp 仅作为“HTTP 解析失败且本机已安装”的可选兜底。
- 日常轮询完全走 RSS，把对 YouTube 的“打扰”降到最低。

**抽象**：定义 `ChannelUpdateProvider` 协议（`func latestVideos(for:) async throws -> [RemoteVideo]`），默认实现 `RSSFeedProvider`，备选 `YtDlpFeedProvider`；未来可无痛扩展 Data API Provider。

### 3.2 检测即“前台轮询”（v1），后台常驻为增强
macOS 桌面 App 关闭后无可靠系统级后台获取。v1 采用**应用运行时 `Timer` 轮询**：最简单、最稳、资源可控。当 App 退出即不检测（符合“前台工具”定位）。【✅ v1 已确认：接受「App 关掉就不检测」，不做后台常驻。】后台常驻（LaunchAgent + Helper）列入 Phase 2 增强，v1 不实现。

### 3.3 通知机制：UNUserNotificationCenter 本地通知
复用系统通知中心，授权一次即可；点击通知可激活 App 并定位到对应通知卡片。

### 3.4 “必须手动删除或下载才可以”的语义（下载改为手动）
- 通知有状态：`pending`（待处理） / `handled`（已处理/已下载，离开待处理） / `deleted`（已删除）。
- “待处理收件箱”只展示 `pending`；**只有**“删除”或“标记为已处理（已下载）”能改变其状态并使其离开列表。**不自动清除、不自动归档替代。**
- **下载动作改为手动**：应用不再入队下载，也不再耦合 `MediaDownloaderViewModel`。卡片提供“**复制下载地址**”“**打开原视频页面**”，用户到下载页面自行下载后，点“**标记已处理**”完成清除。
- 便捷项：可提供“**复制并标记已处理**”一步到位（复制链接的同时把该通知转 `handled`），减少两次点击（默认保留“复制”与“标记”为独立动作，避免误清；该合并项作为可选设置）。

---

## 4. 系统架构

### 4.1 目录结构（遵循现有 `Features/<Feature>/<Models|Services|ViewModels|Views>` 约定）

```
Soluna/
├── SolunaApp.swift                      # 扩展 Schema（新增 2 个 @Model）
├── Features/
│   ├── MediaDownloader/                 # （现有，完全不改）
│   └── Subscription/                   # 【新增，实际目录名】
│       ├── Models/
│       │   ├── ChannelSubscription.swift         # @Model + ChannelSubscriptionSnapshot
│       │   └── VideoNotification.swift           # @Model + VideoNotificationSnapshot + VideoNotificationStatus(pending/handled/deleted)
│       ├── Services/
│       │   ├── SubscriptionStore.swift           # SwiftData 读写（@MainActor）
│       │   ├── ChannelResolver.swift             # 【主】HTTP 公开页面解析 @handle/链接 → channelId（yt-dlp 仅可选兜底）
│       │   ├── RSSFeedProvider.swift             # 【主】官方 RSS 解析（无 Cookies）+ ChannelUpdateProvider 协议 + RemoteVideo
│       │   ├── SubscriptionPollingService.swift  # Timer 轮询调度（仅 RSS，失败记日志下次重试）
│       │   ├── SystemNotificationService.swift   # UNUserNotificationCenter 封装
│       │   └── SubscriptionSettings.swift        # UserDefaults 配置项
│       ├── ViewModels/
│       │   └── SubscriptionViewModel.swift       # @MainActor @Observable
│       └── Views/
│           ├── SubscriptionRootView.swift        # 【单一分区】内含「订阅管理 / 通知收件箱」标签页
│           ├── AddSubscriptionSheet.swift        # 添加订阅弹窗
│           ├── SubscriptionCardView.swift        # 标签1：订阅卡片
│           └── NotificationCardView.swift        # 标签2：通知卡片
```

> 注意：**不再需要 `AppCoordinator`**，因为不再与下载队列联动，订阅模块自成一体。

### 4.2 数据流（ASCII 概览）

```
                 ┌───────────────────────────────────────────┐
                 │                 SolunaApp                    │
                 │   ModelContainer（新增 2 个 @Model）          │
                 └───────────────────┬──────────────────────────┘
                                     │  .environment / @State
                          ┌──────────▼───────────────┐
                          │ YouTubeSubscriptionVM      │
                          │ （订阅 + 通知状态，自成一体）│
                          └──────────┬───────────────┘
                                     │  读写
                          ┌──────────▼───────────────┐
                          │   SubscriptionStore        │  ←→ SwiftData
                          └────────────────────────────┘

  轮询链路（无 Cookies）：
  SubscriptionPollingService(Timer, 前台)
       └─> ChannelUpdateProvider.latestVideos(sub)
                ├─(主) RSSFeedProvider: GET feeds/videos.xml?channel_id=UC..
                └─(备) YtDlpFeedProvider: yt-dlp --flat-playlist（RSS 失败时）
       └─> 比对已知 videoID → 发现新视频
                ├─> SubscriptionStore.insert(VideoNotification .pending)
                └─> SystemNotificationService.deliver(...)

  用户处理通知（手动下载）：
  NotificationCardView
       ├─ 复制下载地址 → NSPasteboard.setString(videoURL)
       ├─ 打开原页面   → NSWorkspace.open(videoURL)
       ├─ 标记已处理   → status=.handled（离开待处理）
       └─ 删除         → status=.deleted / delete
```

---

## 5. 数据模型设计（SwiftData）

> 风格对齐现有 `MediaDownloadHistoryRecord`：`@Model final class`，枚举以 `rawValue` 字符串存储，提供 `Snapshot` 值类型给 View 消费。**已移除所有 Cookies 相关字段。**

### 5.1 ChannelSubscription（订阅）
```swift
import Foundation
import SwiftData

/// `ChannelSubscription` 的作用：保存单个 YouTube 频道订阅及其轮询状态（无需 Cookies）。
@Model
final class ChannelSubscription {
    @Attribute(.unique) var id: UUID
    var channelURL: String
    var channelID: String            // UCxxxx —— RSS 轮询主键，添加订阅时解析得到
    var channelHandle: String?       // @handle
    var title: String
    var thumbnailURLString: String?
    var createdAt: Date
    var lastCheckedAt: Date?
    var lastVideoID: String?         // 上次已知最新视频 ID，用于快速 diff
    var lastVideoTitle: String?
    var lastError: String?           // 最近一次检测错误（用于侧边栏状态提示）
    var isEnabled: Bool
    var notifyOnNewVideo: Bool
    var pollIntervalMinutes: Int     // 0 表示使用全局默认

    init(id: UUID = UUID(), channelURL: String, channelID: String, title: String, ...) { ... }
}
```

### 5.2 VideoNotification（通知）
```swift
/// `VideoNotification` 的作用：记录一次“订阅频道更新了视频”的通知；
/// 须“手动删除”或“标记为已处理（已下载）”后清除。应用不负责实际下载。
@Model
final class VideoNotification {
    @Attribute(.unique) var id: UUID
    var videoID: String              // YouTube 视频 ID，配合 subscriptionID 去重
    var subscriptionID: UUID
    var channelTitle: String?
    var videoTitle: String
    var videoURL: String             // 供“复制下载地址 / 打开原页面”
    var thumbnailURLString: String?
    var publishedAt: Date?           // RSS 中的发布时间
    var detectedAt: Date             // Soluna 发现的时间
    var statusRawValue: String       // pending / handled / deleted
    var handledAt: Date?             // 标记已处理的时间

    var status: VideoNotificationStatus {
        get { VideoNotificationStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }
}
```

### 5.3 VideoNotificationStatus（状态枚举）
```swift
enum VideoNotificationStatus: String, CaseIterable, Identifiable {
    case pending     // 待处理（在收件箱主列表）
    case handled     // 已处理/已下载（用户手动下载后标记，离开待处理）
    case deleted     // 已手动删除
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pending: return "待处理"
        case .handled: return "已处理"
        case .deleted: return "已删除"
        }
    }
}
```

### 5.4 RemoteVideo（轮询返回值类型）
```swift
/// Provider 解析 RSS / yt-dlp 后返回的轻量视频信息。
struct RemoteVideo: Identifiable, Sendable {
    let id: String          // videoId
    let title: String
    let url: String
    let publishedAt: Date?
    let thumbnailURL: String?
}
```

### 5.5 Schema / 迁移处理
在 `SolunaApp` 的 `Schema` 中追加两个模型：
```swift
let schema = Schema([
    MediaDownloadHistoryRecord.self,
    ChannelSubscription.self,      // 新增
    VideoNotification.self         // 新增
])
```
- 向已有 store 增加实体类型，SwiftData 通常自动做轻量迁移（新建表），不破坏既有下载历史。
- **建议**：新增数据使用独立 `ModelConfiguration`（`Subscription.store`），与 `MediaDownloadHistory.store` 分离，互不污染、互不阻塞迁移。

---

## 6. 核心流程

### 6.1 添加订阅（HTTP 公开页面解析，无需 yt-dlp）
```
用户输入 URL / @handle / channelID
  → ChannelResolver.resolve(input)
      1. 输入即 channelId → 直接使用，无需联网
      2. 否则请求 @handle/链接 的公开页面，从 canonical/og:url 提取 channel/UC..
      3. （可选）HTTP 解析失败且本机装有 yt-dlp → yt-dlp 兜底一次
  → 得到 channelID(UC..) / 标题 / 头像
  → SubscriptionStore.insert(ChannelSubscription(...))
  → 立即用 RSS 拉一次建立 lastVideoID 基线（不弹历史通知）
```
> 若输入已是 `channel_id`，直接建立订阅并用 RSS 校验、取标题，全程不发任何外部请求。

### 6.2 轮询检测（Timer · RSS · 无 Cookies）
```
SubscriptionPollingService 每 tick：
  for sub in enabledSubscriptions（错峰/轮转/限并发，默认并发 2）:
     videos = RSSFeedProvider.latestVideos(sub)          // GET feeds/videos.xml?channel_id=..
              ↳ 失败则记错误日志，等待下一轮重试（不回退 yt-dlp，保持零外部进程依赖）
     known  = store.existingVideoIDs(sub)
     newOnes = videos.filter { !known.contains($0.id) }  // 首次基线之后才算“新”
     for v in newOnes:
        store.insert(VideoNotification(status: .pending, ...))
        if sub.notifyOnNewVideo { systemNotification.deliver(channel: sub.title, video: v.title) }
     sub.lastVideoID   = videos.first?.id
     sub.lastCheckedAt = now
     sub.lastError     = nil   // 或记录失败信息
```
> RSS 抖动错峰：各频道加入 0–N 秒随机延迟，避免同一时刻齐发请求。

### 6.3 通知清除 — 标记已处理（手动下载后）
```
用户在 NotificationCardView 点“复制下载地址” → NSPasteboard 写入 videoURL
用户自行到下载页面/工具完成下载
用户点“标记已处理”
  → notification.status = .handled；handledAt = now
  → store.save() → 离开“待处理”列表
（可选合并动作“复制并标记已处理”：一次完成上述两步）
```

### 6.4 通知清除 — 删除
```
用户点“删除”
  → store.markDeleted(notification) 或 store.delete(notification)
  → 从“待处理”列表消失（仅删通知记录，不触碰任何文件）
```

---

## 7. UI / UX 设计（侧边栏合并为单一「订阅」分区）

### 7.1 侧边栏
- **只新增一个分区：「订阅」**（`SubscriptionRootView`），**带待处理数量 Badge**。
- 点进后是一个**标签页容器**（`Picker`/分段控件），两个标签：
  - **订阅管理**（`SubscriptionManagePane`）
  - **通知收件箱**（`NotificationInboxPane`）

### 7.2 添加订阅弹窗 `AddSubscriptionSheet`
- 输入框：粘贴频道链接 / `@handle` / 频道 ID。
- 解析预览：解析成功后展示头像 + 名称 + 启用开关 + 轮询间隔（默认/自定义）。**无 Cookies 选项。**
- 错误态：解析失败提示（链接无效 / HTTP 解析失败 / 网络异常）；极端情况下提示直接粘贴频道 ID（UC 开头）。

### 7.3 标签页 1：订阅管理 `SubscriptionManagePane`
- 频道卡片 `SubscriptionCardView`：头像、名称、最近检测时间、最新视频标题、启用开关、“立即检查”按钮、“取消订阅”。
- 顶部：全部立即检查、添加订阅按钮。
- 空态：引导“添加一个频道订阅”。

### 7.4 标签页 2：通知收件箱 `NotificationInboxPane`
- 顶部：待处理数量、搜索框、频道筛选、子标签（待处理 / 已处理）。
- 列表：`NotificationCardView`（缩略图、频道、标题、发布时间、发现时间）。
- 每条卡片操作：
  - **复制下载地址**（borderedProminent）→ 复制 `videoURL` 到剪贴板。
  - **打开原页面** → 浏览器打开视频页，供手动下载。
  - **标记已处理** → 转 `handled`，离开待处理（见 6.3）。
  - **删除**（destructive）→ 清除（见 6.4）。
- 空态：暂无新更新 / 收件箱已清空。

> 设计要点：明确传达“待处理项不会自动消失”，引导用户三选一（复制去下载后标记 / 直接标记 / 删除）。

### 7.5 设置（新增“订阅与通知”分组）
- 全局轮询间隔（15/30/60/120 分钟，默认 30）。
- 启用系统通知（跳转系统偏好设置授权）。
- 单次并发检测数（1–4，默认 2）。
- （可选）“复制并标记已处理”合并动作开关（默认关）。
- **已移除**：所有 Cookies / 浏览器来源 / Data API / 严格清除模式等设置。

---

## 8. 无 Cookies 轮询与系统通知

### 8.1 RSS 轮询（前台，主）
- `RSSFeedProvider` 用 `URLSession` GET `feeds/videos.xml?channel_id=UC..`，`XMLParser` 解析 `entry`（`yt:videoId` / `title` / `published` / `media:thumbnail` / `link`）。
- 无任何 Cookies / Header 鉴权；设置合理 `User-Agent` 与超时（默认 15s）。
- `SubscriptionPollingService` 用 `Timer` 在主运行循环驱动；App 进入后台可暂停高频轮询，回前台恢复。

### 8.2 yt-dlp 兜底（可选，非必需）
- 仅在**添加订阅**时若公开 HTTP 页面解析失败、且本机已安装 yt-dlp，才作为解析频道信息的可选兜底；**RSS 轮询不回退 yt-dlp**。
- 未安装 yt-dlp 时，解析失败会提示用户直接粘贴频道 ID（UC 开头），不影响 RSS 轮询。
- 兜底命令：`yt-dlp --skip-download --print "%(channel_id)s||%(uploader)s||%(thumbnail)s" "<input>"`。

### 8.3 系统通知
- `SystemNotificationService` 封装 `UNUserNotificationCenter`：首次订阅时 `requestAuthorization`；新视频时 `add(UNNotificationRequest)`。
- 通知 `userInfo` 携带 `notificationID`，点击后 App 打开并定位到该卡片。

### 8.4 健壮性 & 防限流
- 低频（≥30 分钟）+ 频道间抖动错峰 + 限并发（默认 2），把请求量降到最低。
- 单频道单次失败不致命：记录 `lastError`，下轮重试；连续失败在卡片给出状态提示。
- 无账号绑定 ⇒ 不存在“封号”；最坏为临时 IP 限流（429），自动退避后恢复。

---

## 9. 后台常驻（Phase 2 增强，非 v1）
若需“关机/退出也检测”，可新增 **LaunchAgent + 轻量 Helper**：Helper 周期读取 RSS、写入共享 SwiftData，自身发通知；主 App 启动后读取同一份数据展示。代价：需签名/授权、管理常驻进程，复杂度上升。**v1 不做**，仅预留接口（`ChannelUpdateProvider` 与 Store 均可被 Helper 复用）。

---

## 10. 配置项（UserDefaults keys）
| Key | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `yt_subscription_poll_interval` | Int | 30 | 全局轮询间隔（分钟） |
| `yt_subscription_notifications_enabled` | Bool | true | 是否发系统通知 |
| `yt_subscription_concurrent_checks` | Int | 2 | 单次并发检测数 |
| `yt_subscription_copy_and_mark` | Bool | false | 是否启用“复制并标记已处理”合并动作 |

> 已删除：`use_cookies` / `cookie_source` / `strict_clear` / `use_data_api` / `api_key`。

---

## 11. 非功能需求
- **性能**：通知以 `(subscriptionID, videoID)` 去重与索引；RSS 单次仅几 KB；轮询错峰、限并发；列表沿用现有 `LazyVStack` 风格。
- **隐私 & 安全**：**无 Cookies、无登录态、无账号绑定**；全部数据本地存储，无遥测、无上传。
- **健壮性**：RSS 失败可回退 yt-dlp；yt-dlp 缺失/失败有降级提示；订阅模块与下载器完全解耦，互不影响。
- **可维护性**：严格对齐现有分层（Model / Store / ViewModel / View）、中文注释、值类型 Snapshot、统一 Action 枚举与 `confirmationDialog` 删除确认。

---

## 12. 风险与开放问题
1. **IP 临时限流（非封号）**：高频请求可能触发 429 → 缓解：低频 + 错峰 + 限并发 + 退避重试。**因无 Cookies，不涉及账号安全。**
2. **关闭 App 不检测**：v1 仅前台检测 → 【✅ 已确认接受】，Phase 2 用 LaunchAgent 增强。
3. **RSS 只含最新约 15 条**：更新极频繁的频道在两次轮询间可能超过 15 条而漏检 → 缓解：合理轮询间隔；必要时可临时借助 yt-dlp 兜底取更多历史。
4. **RSS 含 Shorts / 直播条目**：RSS 会混入 Shorts、首播 → 可按需过滤（v1 默认全部通知，后续可加“忽略 Shorts / 直播”开关）。
5. **@handle 解析**：当前通过公开 HTTP 页面解析（无 yt-dlp、无 Cookies）；仅当解析失败且本机装有 yt-dlp 才兜底。极端情况下提示用户直接粘贴 `channel_id`。

---

## 13. 实施里程碑
| 阶段 | 内容 | 产出 |
| --- | --- | --- |
| Phase 0 | 数据模型 + Store + Schema/迁移（独立 `Subscription.store`） | `ChannelSubscription`/`VideoNotification`/`VideoNotificationStatus`/`SubscriptionStore` |
| Phase 1 | 订阅管理（增删查 + ChannelResolver HTTP 解析 + 立即检查）+ 添加弹窗 | `AddSubscriptionSheet` / `SubscriptionRootView` / `ChannelResolver.resolve` |
| Phase 2 | **RSS 轮询** + 系统通知 + 收件箱 + 复制/标记/删除清除 | `RSSFeedProvider` / `SubscriptionPollingService` / `SystemNotificationService` / `NotificationInboxPane` |
| Phase 3 | 单一「订阅」分区 + 标签页 + 设置 + Badge + 空/错态打磨 + 自测 | `SubscriptionRootView` + 设置项 + 收尾 |
| （增强） | LaunchAgent 后台常驻 / 忽略 Shorts、直播 / Data API Provider | 可选 |

---

## 14. 验收标准
- [ ] 可通过链接/handle/channelID 成功订阅一个频道，并解析出标题与头像（解析走公开 HTTP 页面，无需安装 yt-dlp）。
- [ ] **全程不使用 Cookies**；轮询走官方 RSS（可在日志确认请求 URL 为 `feeds/videos.xml`）。
- [ ] 模拟该频道出现新视频（或手动插入新 videoID）后，能弹系统通知并在收件箱出现一条 `pending` 通知。
- [ ] 卡片“复制下载地址”能把视频链接写入剪贴板；“打开原页面”能在浏览器打开。
- [ ] 点“标记已处理”→ 通知转 `handled` 离开待处理；点“删除”→ 通知从待处理消失且仅删记录。
- [ ] 同一视频重复轮询不产生重复通知（去重）。
- [ ] 侧边栏只有**一个「订阅」分区**，内部标签页可切换“订阅管理 / 通知收件箱”，Badge 显示待处理数。
- [ ] 关闭/重开 App 后订阅与通知数据持久化保留。
- [ ] 现有下载功能不受任何影响（回归通过）。

---

## 附录 A：RSS 源实测样例
```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
      xmlns:media="http://search.yahoo.com/mrss/"
      xmlns="http://www.w3.org/2005/Atom">
  <yt:channelId>UC_x5XG1OV2P6uZZ5FSM9Ttw</yt:channelId>
  <title>Google for Developers</title>
  <entry>
    <yt:videoId>Q1TfKyOcosk</yt:videoId>
    <title>The harsh reality of coding</title>
    <link rel="alternate" href="https://www.youtube.com/watch?v=Q1TfKyOcosk"/>
    <published>2026-07-15T04:00:40+00:00</published>
    <media:group>
      <media:thumbnail url="https://i*.ytimg.com/vi/Q1TfKyOcosk/hqdefault.jpg"/>
    </media:group>
  </entry>
  <!-- 约 15 条 entry -->
</feed>
```
> 关键取值：`yt:videoId`（去重主键）、`title`、`link@href`（复制/打开）、`published`、`media:thumbnail@url`（缩略图）。
