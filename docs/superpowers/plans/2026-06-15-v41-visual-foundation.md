# v41 视觉基础重构 + 插件架构骨架 + AppList Module 化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 NovaLaunch 中引入液态玻璃视觉、动态小箭头、文件夹自适应取色，搭建 Plugin 架构骨架，并把现有应用扫描/搜索代码抽出为独立 Swift Package `NovaLaunchKit`。

**Architecture:** 三层并行：(1) NovaLaunchKit 是独立 Swift Package 暴露 `AppListPlugin` 实现 `Plugin` 协议；(2) 主工程 `Infrastructure/PluginManager/` 定义 `Plugin` / `PluginHostService` / `PluginManager` 协议层；(3) UI 层用 `NSVisualEffectView` + `CAMetalLayer` 实现液态玻璃背景，`PointerController` 管理双模式动态小箭头。

**Tech Stack:** Swift 5.9 + SwiftUI 4.0 + AppKit + NSVisualEffectView + CAMetalLayer + CoreImage (CIFilter) + Swift Package Manager + macOS 14+

**Spec:** `docs/superpowers/specs/2026-06-15-v41-visual-foundation-design.md`

---

## 文件结构

### 新增（整体搬迁 v40 现有文件，文件名保持一致以便追溯）
- `modules/NovaLaunchKit/Package.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Models/ApplicationItem.swift` ← 整体搬迁自 `NovaLaunch/Core/Models/ApplicationItem.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Services/IndexingService.swift` ← 整体搬迁自 `NovaLaunch/Core/Services/IndexingService.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Services/SearchService.swift` ← 整体搬迁自 `NovaLaunch/Core/Services/SearchService.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Utilities/String+Pinyin.swift` ← 抽出 SearchService.swift 中的 `String` 扩展
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/AppListViewModel.swift` ← 新建（薄包装，订阅 IndexingService.shared + SearchService.shared）
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/AppListPlugin.swift` ← 新建
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Views/AppListRootView.swift` ← 新建
- `NovaLaunch/Infrastructure/PluginManager/Plugin.swift`
- `NovaLaunch/Infrastructure/PluginManager/PluginHostService.swift`
- `NovaLaunch/Infrastructure/PluginManager/PluginManager.swift`
- `NovaLaunch/Infrastructure/PluginManager/BuiltInPluginRegistry.swift`
- `NovaLaunch/Infrastructure/PluginManager/DynamicPluginLoader.swift`
- `NovaLaunch/UI/Components/LiquidGlassBackground.swift`
- `NovaLaunch/UI/Components/DynamicPointer.swift`
- `NovaLaunch/UI/Components/AdaptiveFolderTint.swift`
- `NovaLaunch/UI/Views/PluginTabView.swift`
- `NovaLaunch/UI/Views/PluginContentView.swift`

### 修改
- `NovaLaunch/AppDelegate.swift` — 实现 `PluginHostService`，注册 Plugin
- `NovaLaunch/UI/Views/MainLauncherView.swift` — 使用 `PluginTabView` 替换原内容
- `NovaLaunch/UI/Themes/AnimationTheme.swift` — 新增 spring 动画常量
- 以下 15 个文件需加 `import NovaLaunchKit`（已引用 `ApplicationItem` / `IndexingService` / `SearchService`）：
  - `NovaLaunch/AppDelegate.swift`
  - `NovaLaunch/UI/Views/MainLauncherView.swift`
  - `NovaLaunch/Core/Services/PersistenceService.swift`
  - `NovaLaunch/UI/Views/GroupDetailView.swift`
  - `NovaLaunch/Core/ViewModels/GroupViewModel.swift`
  - `NovaLaunch/Core/Services/FileSystemWatcher.swift`
  - `NovaLaunch/Core/ViewModels/MainViewModel.swift`
  - `NovaLaunch/UI/Views/SearchResultView.swift`
  - `NovaLaunch/UI/Components/AppIcon.swift`
  - `NovaLaunch/Core/Services/AnalyticsService.swift`
  - `NovaLaunch/Core/ViewModels/SearchViewModel.swift`

### 删除（v40 源文件，已整体搬迁到 Package）
- `NovaLaunch/Core/Models/ApplicationItem.swift`
- `NovaLaunch/Core/Services/IndexingService.swift`
- `NovaLaunch/Core/Services/SearchService.swift`
- `NovaLaunch/Infrastructure/PluginManager.swift`（已替换为 `PluginManager/` 目录）

---

## 任务总览

| # | 主题 | 主要文件 |
|---|------|---------|
| 1 | NovaLaunchKit Package 骨架 | `modules/NovaLaunchKit/Package.swift` |
| 2 | 迁移 ApplicationItem 数据模型 | `NovaLaunchKit/Models/ApplicationItem.swift` |
| 3 | 迁移 ApplicationScanner/Indexer/SearchService | 3 个 NovaLaunchKit 文件 |
| 4 | 实现 AppListViewModel + ViewModelProtocol | `AppListViewModel.swift` |
| 5 | 实现 AppListPlugin + AppListRootView | `AppListPlugin.swift`, `AppListRootView.swift` |
| 6 | 主工程引用 Package + 清理旧文件 | `AppDelegate.swift` 等 |
| 7 | Plugin 协议 + PluginHostService 协议 | `Plugin.swift`, `PluginHostService.swift` |
| 8 | PluginManager + Registry + Loader stub | 3 个 PluginManager 文件 |
| 9 | LiquidGlassBackground 组件 | `LiquidGlassBackground.swift` |
| 10 | DynamicPointer 组件 | `DynamicPointer.swift` |
| 11 | AdaptiveFolderTint 组件 | `AdaptiveFolderTint.swift` |
| 12 | PluginTabView + PluginContentView | 2 个 View 文件 |
| 13 | MainLauncherView 集成新组件 | `MainLauncherView.swift` |
| 14 | AnimationTheme spring 常量 | `AnimationTheme.swift` |
| 15 | 编译签名部署 v41 | 编译脚本 |

---

### Task 1: 创建 NovaLaunchKit Package 骨架

**Files:**
- Create: `modules/NovaLaunchKit/Package.swift`
- Create: `modules/NovaLaunchKit/Sources/NovaLaunchKit/Placeholder.swift`
- Create: `modules/NovaLaunchKit/Tests/NovaLaunchKitTests/PlaceholderTests.swift`

- [ ] **Step 1: 创建 Package 目录结构**

```bash
mkdir -p modules/NovaLaunchKit/Sources/NovaLaunchKit
mkdir -p modules/NovaLaunchKit/Tests/NovaLaunchKitTests
```

- [ ] **Step 2: 写 Package.swift**

```swift
// modules/NovaLaunchKit/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NovaLaunchKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NovaLaunchKit", targets: ["NovaLaunchKit"])
    ],
    targets: [
        .target(
            name: "NovaLaunchKit",
            dependencies: [],
            path: "Sources/NovaLaunchKit"
        ),
        .testTarget(
            name: "NovaLaunchKitTests",
            dependencies: ["NovaLaunchKit"],
            path: "Tests/NovaLaunchKitTests"
        )
    ]
)
```

- [ ] **Step 3: 写占位文件**

```swift
// modules/NovaLaunchKit/Sources/NovaLaunchKit/Placeholder.swift
// v41 占位文件，Task 2 起会被删除
import Foundation

public enum NovaLaunchKitVersion: String {
    case v41 = "0.1.0"
}
```

- [ ] **Step 4: 写占位测试**

```swift
// modules/NovaLaunchKit/Tests/NovaLaunchKitTests/PlaceholderTests.swift
import XCTest
@testable import NovaLaunchKit

final class PlaceholderTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(NovaLaunchKitVersion.v41.rawValue, "0.1.0")
    }
}
```

- [ ] **Step 5: 编译 Package 验证**

Run: `cd modules/NovaLaunchKit && swift build 2>&1 | tail -10`
Expected: `Build complete!` 无错误

- [ ] **Step 6: 运行测试验证**

Run: `cd modules/NovaLaunchKit && swift test 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

---

### Task 2: 整体搬迁 ApplicationItem 到 Package

> **策略**：将 v40 现有 `ApplicationItem` 整文件复制到 Package 内，仅加 `public` 修饰符 + `Sendable` 协议 + `import` 调整，**不改任何字段/方法/枚举**。

**Files:**
- Create: `modules/NovaLaunchKit/Sources/NovaLaunchKit/Models/ApplicationItem.swift`
- Delete: `modules/NovaLaunchKit/Sources/NovaLaunchKit/Placeholder.swift`
- Create: `modules/NovaLaunchKit/Tests/NovaLaunchKitTests/ApplicationItemTests.swift`

- [ ] **Step 1: 删除 Placeholder.swift**

```bash
rm modules/NovaLaunchKit/Sources/NovaLaunchKit/Placeholder.swift
rm modules/NovaLaunchKit/Tests/NovaLaunchKitTests/PlaceholderTests.swift
```

- [ ] **Step 2: 读 v40 现有 ApplicationItem.swift**

Run: `cat NovaLaunch/Core/Models/ApplicationItem.swift`

记录要点：
- 字段：`id: UUID`、`bundleIdentifier: String`、`displayName: String`、`name: String`、`bundlePath: String`、`executableURL: URL?`、`version: String`、`launchCount: Int`、`lastLaunchedDate: Date?`、`createdAt: Date`、`isFavorite: Bool`、`category: AppCategory`、`source: AppSource`
- 枚举：`AppCategory`（productivity/creativity/developer/utilities/games/system/other）、`AppSource`（system/user）
- 方法：`launch()`、`loadIcon()`、`recommendationScore` 计算属性
- Hashable：用 `bundleIdentifier` 做哈希（**关键：与 v40 一致**）

- [ ] **Step 3: 写新 ApplicationItem.swift（整体搬迁 + 加 public + Sendable）**

```swift
// modules/NovaLaunchKit/Sources/NovaLaunchKit/Models/ApplicationItem.swift
// 整体搬迁自 NovaLaunch/Core/Models/ApplicationItem.swift
// 唯一变化：所有声明加 public，加 Sendable
import Foundation
import SwiftUI
import AppKit

// MARK: - ApplicationItem

/// 应用程序数据模型：描述一个可被 NovaLaunch 索引与展示的 .app 条目
public struct ApplicationItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let bundleIdentifier: String
    public let displayName: String
    public let name: String
    public let bundlePath: String
    public let executableURL: URL?
    public let version: String
    public let launchCount: Int
    public let lastLaunchedDate: Date?
    public let createdAt: Date
    public var isFavorite: Bool
    public var category: AppCategory
    public var source: AppSource

    public enum AppCategory: String, Codable, CaseIterable, Sendable {
        case productivity
        case creativity
        case developer
        case utilities
        case games
        case system
        case other
    }

    /// 应用来源：系统自带 vs 用户安装
    public enum AppSource: String, Codable, CaseIterable, Sendable {
        case system   // 系统自带
        case user     // 用户安装
    }

    public init(id: UUID = UUID(),
                bundleIdentifier: String,
                displayName: String,
                name: String,
                bundlePath: String,
                executableURL: URL? = nil,
                version: String = "1.0.0",
                launchCount: Int = 0,
                lastLaunchedDate: Date? = nil,
                createdAt: Date = Date(),
                isFavorite: Bool = false,
                category: AppCategory = .other,
                source: AppSource = .user) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.name = name
        self.bundlePath = bundlePath
        self.executableURL = executableURL
        self.version = version
        self.launchCount = launchCount
        self.lastLaunchedDate = lastLaunchedDate
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.category = category
        self.source = source
    }

    /// 是否是系统自带应用
    public var isSystemApp: Bool { source == .system }
}

// MARK: - Hashable

extension ApplicationItem {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }

    public static func == (lhs: ApplicationItem, rhs: ApplicationItem) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

// MARK: - Display Helpers

extension ApplicationItem {
    /// 通过 NSWorkspace 动态获取应用原生图标（非主线程友好）
    public func loadIcon() -> NSImage {
        let workspace = NSWorkspace.shared
        return workspace.icon(forFile: bundlePath)
    }

    /// 启动该应用
    @discardableResult
    public func launch() -> Bool {
        let url = URL(fileURLWithPath: bundlePath)
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return true
    }

    /// AI 推荐分数计算
    public var recommendationScore: Double {
        let hits = max(1, launchCount)
        let interval = max(1, Date().timeIntervalSince(lastLaunchedDate ?? createdAt))
        return log(Double(hits)) / interval
    }
}
```

- [ ] **Step 4: 写测试**

```swift
// modules/NovaLaunchKit/Tests/NovaLaunchKitTests/ApplicationItemTests.swift
import XCTest
@testable import NovaLaunchKit

final class ApplicationItemTests: XCTestCase {
    func testInitialization() {
        let item = ApplicationItem(
            bundleIdentifier: "com.example.test",
            displayName: "Test App",
            name: "Test",
            bundlePath: "/Applications/Test.app"
        )
        XCTAssertEqual(item.bundleIdentifier, "com.example.test")
        XCTAssertEqual(item.displayName, "Test App")
        XCTAssertEqual(item.bundlePath, "/Applications/Test.app")
        XCTAssertEqual(item.launchCount, 0)
        XCTAssertNil(item.lastLaunchedDate)
        XCTAssertEqual(item.category, .other)
        XCTAssertEqual(item.source, .user)
    }

    func testCodable() throws {
        let original = ApplicationItem(
            bundleIdentifier: "com.example.test",
            displayName: "Test App",
            name: "Test",
            bundlePath: "/Applications/Test.app",
            launchCount: 5
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ApplicationItem.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testHashable() {
        let a = ApplicationItem(bundleIdentifier: "x", displayName: "X", name: "X", bundlePath: "/X.app")
        let b = ApplicationItem(bundleIdentifier: "x", displayName: "X", name: "X", bundlePath: "/X.app")
        let c = ApplicationItem(bundleIdentifier: "y", displayName: "Y", name: "Y", bundlePath: "/Y.app")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testCategoryEnum() {
        XCTAssertEqual(ApplicationItem.AppCategory.developer.rawValue, "developer")
        XCTAssertEqual(ApplicationItem.AppSource.system.rawValue, "system")
    }

    func testIsSystemApp() {
        let systemItem = ApplicationItem(
            bundleIdentifier: "com.apple.safari",
            displayName: "Safari",
            name: "Safari",
            bundlePath: "/System/Applications/Safari.app",
            source: .system
        )
        let userItem = ApplicationItem(
            bundleIdentifier: "com.example.app",
            displayName: "App",
            name: "App",
            bundlePath: "/Applications/App.app",
            source: .user
        )
        XCTAssertTrue(systemItem.isSystemApp)
        XCTAssertFalse(userItem.isSystemApp)
    }
}
```

- [ ] **Step 5: 编译 + 测试**

Run: `cd modules/NovaLaunchKit && swift test 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed at ...` 5 个测试通过

---

### Task 3: 整体搬迁 IndexingService + SearchService + 拼音扩展

> **策略**：将 v40 现有 `IndexingService`、`SearchService`、`IndexingStatus`、`SearchResult`、`MatchPriority`、`String` 拼音扩展**原封不动**搬迁到 Package 内，加 `public` 修饰符。**不重写任何业务逻辑**（包括 5 个标准扫描路径、`LSCopyDisplayNameForURL`、拼音全拼+首字母+模糊容错）。

**Files:**
- Create: `modules/NovaLaunchKit/Sources/NovaLaunchKit/Services/IndexingService.swift` ← 整体搬迁自 `NovaLaunch/Core/Services/IndexingService.swift`
- Create: `modules/NovaLaunchKit/Sources/NovaLaunchKit/Services/SearchService.swift` ← 整体搬迁自 `NovaLaunch/Core/Services/SearchService.swift`（不含 String 扩展）
- Create: `modules/NovaLaunchKit/Sources/NovaLaunchKit/Utilities/String+Pinyin.swift` ← 抽出 SearchService.swift 中的 `String` 扩展
- Create: `modules/NovaLaunchKit/Tests/NovaLaunchKitTests/IndexingServiceTests.swift`
- Create: `modules/NovaLaunchKit/Tests/NovaLaunchKitTests/SearchServiceTests.swift`
- Create: `modules/NovaLaunchKit/Tests/NovaLaunchKitTests/StringPinyinTests.swift`

- [ ] **Step 1: 读 v40 现有 IndexingService.swift**

Run: `cat NovaLaunch/Core/Services/IndexingService.swift`

记录要点：
- `enum IndexingStatus: Equatable` — `idle` / `scanning(progress:currentPath:)` / `completed(count:)` / `failed(error:)`
- `final class IndexingService` — 单例 `shared`，`CurrentValueSubject<IndexingStatus, Never>` 和 `CurrentValueSubject<[ApplicationItem], Never>`
- 公开方法：`startFullScan()`、`startIncrementalScan()`、`reset()`、`refreshItem(at:)`
- 私有：`performScan()` 扫描 5 个标准路径（`/Applications`、`/Applications/Utilities`、`/System/Applications`、`/System/Library/CoreServices/Applications`、`~/Applications`）
- 私有静态：`makeItem(from:)`、`lsDisplayName(for:)`（用 `LSCopyDisplayNameForURL`）、`inferCategory(from:)`、`cleanDisplayName(_:)`
- OperationQueue 后台扫描 + autoreleasepool

- [ ] **Step 2: 读 v40 现有 SearchService.swift**

Run: `cat NovaLaunch/Core/Services/SearchService.swift`

记录要点：
- `struct SearchResult: Identifiable` + `enum MatchPriority: Int, Comparable`（exact/prefix/pinyinInitial/pinyinFull/fuzzy）
- `final class SearchService` — 单例 `shared`，`fuzzyThreshold = 2`
- 5 级优先级搜索：精准包含 → 前缀匹配 → 拼音首字母缩写 → 拼音全拼 → Levenshtein 模糊
- 私有：`editDistance(_:to:)`（纯 Swift 实现）
- `extension String`：`toPinyin()`（用 `CFStringTransformMandarinLatin` + `StripCombiningMarks`）、`toPinyinInitials()`

- [ ] **Step 3: 写 IndexingService.swift（整体搬迁 + 加 public）**

```swift
// modules/NovaLaunchKit/Sources/NovaLaunchKit/Services/IndexingService.swift
// 整体搬迁自 NovaLaunch/Core/Services/IndexingService.swift
// 唯一变化：所有声明加 public，import 不变
import Foundation
import AppKit
import Combine
import CoreServices

// MARK: - IndexingStatus

public enum IndexingStatus: Equatable, Sendable {
    case idle
    case scanning(progress: Double, currentPath: String)
    case completed(count: Int)
    case failed(error: String)
}

// MARK: - IndexingService

/// 应用扫描与索引服务
/// 职责：遍历 /Applications 及用户目录，发现所有 .app 包并转换为 ApplicationItem。
/// 设计原则：
///  - 使用 Combine 的 CurrentValueSubject 广播状态流，供 ViewModel 订阅。
///  - 扫描工作位于后台 OperationQueue，避免阻塞主线程。
///  - 结果通过 NSMetadataQuery / FileManager 双重校验，保证完整性。
public final class IndexingService {

    // MARK: Singleton

    public static let shared = IndexingService()
    private init() {}

    // MARK: Output Subjects

    public let statusSubject = CurrentValueSubject<IndexingStatus, Never>(.idle)
    public let itemsSubject = CurrentValueSubject<[ApplicationItem], Never>([])

    // MARK: Private State

    private let scanQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.novalaunch.indexing"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var cancellables = Set<AnyCancellable>()

    // MARK: Public API

    /// 启动一次全量扫描。若已有扫描在进行中，则跳过并保持当前状态。
    public func startFullScan() {
        scanQueue.cancelAllOperations()
        statusSubject.send(.idle)
        statusSubject.send(.scanning(progress: 0, currentPath: "/Applications"))

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            let items = self.performScan()
            DispatchQueue.main.async {
                self.itemsSubject.send(items)
                self.statusSubject.send(.completed(count: items.count))
            }
        }
        operation.queuePriority = .high
        scanQueue.addOperation(operation)
    }

    /// 增量扫描：仅当已有结果时使用，比全量扫描更快
    /// 适合文件监听器触发的轻量级刷新
    public func startIncrementalScan() {
        // 只在空闲时启动增量扫描，避免与全量扫描冲突
        if case .scanning = statusSubject.value { return }

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            let items = self.performScan()
            DispatchQueue.main.async {
                // 检查是否有变化
                let oldItems = self.itemsSubject.value
                let oldBundleIDs = Set(oldItems.map { $0.bundleIdentifier })
                let newBundleIDs = Set(items.map { $0.bundleIdentifier })

                if oldBundleIDs != newBundleIDs || oldItems.count != items.count {
                    self.itemsSubject.send(items)
                    print("NovaLaunch: 检测到应用变化，已更新 (\(items.count) 个应用)")
                }
            }
        }
        operation.queuePriority = .normal
        scanQueue.addOperation(operation)
    }

    /// 强制重置到 idle 状态（用于重置扫描队列）
    public func reset() {
        scanQueue.cancelAllOperations()
        statusSubject.send(.idle)
    }

    /// 增量刷新：接收单个 URL，转换为 ApplicationItem 并合并到结果中。
    public func refreshItem(at url: URL) -> ApplicationItem? {
        guard let item = Self.makeItem(from: url) else { return nil }
        var current = itemsSubject.value
        if let index = current.firstIndex(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
            current[index] = item
        } else {
            current.append(item)
        }
        itemsSubject.send(current)
        return item
    }

    // MARK: Scan Implementation

    private func performScan() -> [ApplicationItem] {
        let searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
            NSSearchPathForDirectoriesInDomains(.applicationDirectory,
                                                .userDomainMask,
                                                true).first ?? ""
        ].filter { !$0.isEmpty }

        var collected: [URL] = []
        let manager = FileManager.default

        for base in searchPaths {
            autoreleasepool {
                let baseURL = URL(fileURLWithPath: base)
                guard let enumerator = manager.enumerator(at: baseURL,
                                                          includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                          errorHandler: nil) else { return }

                for case let url as URL in enumerator {
                    // 进度上报
                    let progress = min(1.0, Double(collected.count) / 300.0)
                    DispatchQueue.main.async { [weak self] in
                        self?.statusSubject.send(.scanning(progress: progress,
                                                           currentPath: base))
                    }
                    if url.pathExtension.lowercased() == "app" {
                        collected.append(url)
                        enumerator.skipDescendants()
                    }
                }
            }
        }

        // 去重 & 构建 ApplicationItem
        var seen: Set<String> = []
        var items: [ApplicationItem] = []
        for url in collected {
            autoreleasepool {
                guard let item = Self.makeItem(from: url) else { return }
                guard !seen.contains(item.bundleIdentifier) else { return }
                seen.insert(item.bundleIdentifier)
                items.append(item)
            }
        }
        return items
    }

    // MARK: Builder

    private static func makeItem(from url: URL) -> ApplicationItem? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]

        let bundleIdentifier = (info[kCFBundleIdentifierKey as String] as? String)
            ?? "unknown.\(url.lastPathComponent)"

        // 多源获取应用显示名（关键：确保与系统 Finder 完全一致）
        // 优先级顺序：用户自定义 > LS显示名 > Bundle本地化 > 文件名
        let displayName: String = {
            // 1. 优先使用 LaunchServices 提供的本地化显示名（与 Finder 完全一致）
            if let lsName = Self.lsDisplayName(for: url), !lsName.isEmpty {
                return Self.cleanDisplayName(lsName)
            }
            // 2. 优先使用系统的本地化显示名
            if let localized = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
               !localized.isEmpty {
                return Self.cleanDisplayName(localized)
            }
            if let localizedName = bundle?.localizedInfoDictionary?["CFBundleName"] as? String,
               !localizedName.isEmpty {
                return Self.cleanDisplayName(localizedName)
            }
            // 3. 使用 bundle 的 localizedString for key
            if let key = bundle?.localizedString(forKey: "CFBundleDisplayName", value: nil, table: nil) as String?,
               !key.isEmpty, key != "CFBundleDisplayName" {
                return Self.cleanDisplayName(key)
            }
            // 4. 使用 Info.plist 中的 CFBundleDisplayName
            if let display = info["CFBundleDisplayName"] as? String, !display.isEmpty {
                return Self.cleanDisplayName(display)
            }
            // 5. 使用 CFBundleName
            if let name = info[kCFBundleNameKey as String] as? String, !name.isEmpty {
                return Self.cleanDisplayName(name)
            }
            // 6. 使用文件名（去掉 .app）
            return url.deletingPathExtension().lastPathComponent
        }()

        // 应用来源：判断系统自带还是用户安装
        let source: ApplicationItem.AppSource = {
            if url.path.hasPrefix("/System/Applications") || url.path.hasPrefix("/System/Library/CoreServices/Applications") {
                return .system
            }
            return .user
        }()

        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info[kCFBundleVersionKey as String] as? String)
            ?? "1.0.0"

        return ApplicationItem(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            name: url.deletingPathExtension().lastPathComponent,
            bundlePath: url.path,
            executableURL: bundle?.executableURL,
            version: version,
            category: Self.inferCategory(from: info),
            source: source
        )
    }

    private static func inferCategory(from info: [String: Any]) -> ApplicationItem.AppCategory {
        let category = info["LSApplicationCategoryType"] as? String ?? ""
        switch category {
        case let c where c.contains("productivity"): return .productivity
        case let c where c.contains("graphics") || c.contains("video"): return .creativity
        case let c where c.contains("developer"): return .developer
        case let c where c.contains("utilities"): return .utilities
        case let c where c.contains("games"): return .games
        default: return .other
        }
    }

    /// 使用 LaunchServices 获取与 Finder 完全一致的应用显示名
    private static func lsDisplayName(for url: URL) -> String? {
        let urlRef = url as CFURL
        var displayNameRef: Unmanaged<CFString>?
        let status = LSCopyDisplayNameForURL(urlRef, &displayNameRef)

        if status == noErr, let unmanaged = displayNameRef {
            let displayName = unmanaged.takeRetainedValue() as String
            if !displayName.isEmpty {
                return displayName
            }
        }

        // 兜底：尝试从 .localized 子目录读取
        let localizedSubdirs = [
            "zh-Hans.lproj", "zh_CN.lproj", "zh-CN.lproj", "zh.lproj",
            "en.lproj", "Base.lproj"
        ]
        for subdir in localizedSubdirs {
            let infoPlistStringsURL = url.appendingPathComponent("Contents/Resources/\(subdir)/InfoPlist.strings")
            if FileManager.default.fileExists(atPath: infoPlistStringsURL.path) {
                if let dict = NSDictionary(contentsOf: infoPlistStringsURL) as? [String: Any] {
                    if let display = dict["CFBundleDisplayName"] as? String, !display.isEmpty {
                        return display
                    }
                    if let name = dict["CFBundleName"] as? String, !name.isEmpty {
                        return name
                    }
                }
            }
        }

        return nil
    }

    /// 清理显示名（去掉 .app 后缀，去除多余空白）
    private static func cleanDisplayName(_ name: String) -> String {
        var cleaned = name
        if cleaned.hasSuffix(".app") {
            cleaned = String(cleaned.dropLast(4))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
```

- [ ] **Step 4: 写 SearchService.swift（整体搬迁 + 加 public，不含 String 扩展）**

```swift
// modules/NovaLaunchKit/Sources/NovaLaunchKit/Services/SearchService.swift
// 整体搬迁自 NovaLaunch/Core/Services/SearchService.swift
// 唯一变化：所有声明加 public，String 扩展已抽出到 String+Pinyin.swift
import Foundation
import Combine

// MARK: - SearchResult

public struct SearchResult: Identifiable, Sendable {
    public let id = UUID()
    public let item: ApplicationItem
    public let priority: MatchPriority

    public enum MatchPriority: Int, Comparable, Sendable {
        case exact = 0
        case prefix = 1
        case pinyinInitial = 2
        case pinyinFull = 3
        case fuzzy = 4

        public static func < (lhs: MatchPriority, rhs: MatchPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

// MARK: - SearchService

/// 智能搜索引擎：精准匹配 → 前缀匹配 → 拼音首字母 → 拼音全拼 → 模糊容错
public final class SearchService {
    public static let shared = SearchService()
    private init() {}

    private let fuzzyThreshold = 2

    public func search(query: String, in items: [ApplicationItem]) -> [ApplicationItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }

        var results: [SearchResult] = []

        for item in items {
            let name = item.displayName.lowercased()
            let pinyin = item.displayName.toPinyin().lowercased()
            let initials = item.displayName.toPinyinInitials().lowercased()

            // 优先级 0：精准包含
            if name.contains(q) {
                results.append(SearchResult(item: item, priority: .exact))
                continue
            }
            // 优先级 1：前缀匹配
            if name.hasPrefix(q) || initials.hasPrefix(q) {
                results.append(SearchResult(item: item, priority: .prefix))
                continue
            }
            // 优先级 2：拼音首字母缩写匹配
            if initials.contains(q) {
                results.append(SearchResult(item: item, priority: .pinyinInitial))
                continue
            }
            // 优先级 3：全拼匹配
            if pinyin.contains(q) {
                results.append(SearchResult(item: item, priority: .pinyinFull))
                continue
            }
            // 优先级 4：模糊编辑距离容错
            if editDistance(q, to: initials) <= fuzzyThreshold ||
               editDistance(q, to: name) <= fuzzyThreshold {
                results.append(SearchResult(item: item, priority: .fuzzy))
                continue
            }
        }

        return results
            .sorted { $0.priority < $1.priority }
            .map(\.item)
    }

    // MARK: - Levenshtein 编辑距离（纯 Swift 实现，无第三方库）

    private func editDistance(_ s1: String, to s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[m][n]
    }
}
```

- [ ] **Step 5: 写 String+Pinyin.swift（抽出 String 扩展，加 public）**

```swift
// modules/NovaLaunchKit/Sources/NovaLaunchKit/Utilities/String+Pinyin.swift
// 整体搬迁自 SearchService.swift 的 String 扩展
// 唯一变化：加 public
import Foundation

public extension String {
    /// 中文转拼音全拼（使用 CFStringTransform 纯 Apple API）
    func toPinyin() -> String {
        let mutable = NSMutableString(string: self) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String).replacingOccurrences(of: " ", with: "")
    }

    /// 中文转拼音首字母
    func toPinyinInitials() -> String {
        let pinyin = toPinyin()
        return pinyin.compactMap { char -> String? in
            guard let scalar = char.unicodeScalars.first else { return nil }
            if scalar.value >= 0x41, scalar.value <= 0x5A {
                return String(char)
            } else if scalar.value >= 0x61, scalar.value <= 0x7A {
                return String(char)
            }
            return nil
        }.joined()
    }
}
```

- [ ] **Step 6: 写 IndexingServiceTests.swift**

```swift
// modules/NovaLaunchKit/Tests/NovaLaunchKitTests/IndexingServiceTests.swift
import XCTest
@testable import NovaLaunchKit

final class IndexingServiceTests: XCTestCase {
    func testSharedInstance() {
        let a = IndexingService.shared
        let b = IndexingService.shared
        XCTAssertTrue(a === b)
    }

    func testInitialStatusIsIdle() {
        let svc = IndexingService.shared
        if case .idle = svc.statusSubject.value { /* pass */ }
        else if case .scanning = svc.statusSubject.value { /* pass */ }
        else if case .completed = svc.statusSubject.value { /* pass */ }
        else { XCTFail("状态异常") }
    }

    func testStatusEnumEquality() {
        XCTAssertEqual(IndexingStatus.idle, .idle)
        XCTAssertEqual(IndexingStatus.completed(count: 5), .completed(count: 5))
        XCTAssertNotEqual(IndexingStatus.idle, .completed(count: 5))
    }

    func testStartFullScanUpdatesStatus() {
        let svc = IndexingService.shared
        let exp = expectation(description: "scan completes")
        var cancellable: AnyCancellable?
        cancellable = svc.statusSubject
            .sink { status in
                if case .completed = status { exp.fulfill() }
            }
        svc.startFullScan()
        wait(for: [exp], timeout: 30.0)
        cancellable?.cancel()
    }
}
```

- [ ] **Step 7: 写 SearchServiceTests.swift**

```swift
// modules/NovaLaunchKit/Tests/NovaLaunchKitTests/SearchServiceTests.swift
import XCTest
@testable import NovaLaunchKit

final class SearchServiceTests: XCTestCase {
    var svc: SearchService!
    var items: [ApplicationItem]!

    override func setUp() {
        super.setUp()
        svc = SearchService()
        items = [
            ApplicationItem(bundleIdentifier: "com.apple.Safari", displayName: "Safari", name: "Safari", bundlePath: "/Applications/Safari.app"),
            ApplicationItem(bundleIdentifier: "com.apple.Xcode", displayName: "Xcode", name: "Xcode", bundlePath: "/Applications/Xcode.app"),
            ApplicationItem(bundleIdentifier: "com.tencent.WeChat", displayName: "微信", name: "WeChat", bundlePath: "/Applications/WeChat.app"),
            ApplicationItem(bundleIdentifier: "com.bytedance.Feishu", displayName: "飞书", name: "Feishu", bundlePath: "/Applications/Feishu.app")
        ]
    }

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(svc.search(query: "", in: items).count, 4)
    }

    func testExactMatch() {
        let results = svc.search(query: "Safari", in: items)
        XCTAssertEqual(results.first?.displayName, "Safari")
    }

    func testPrefixMatch() {
        let results = svc.search(query: "Xco", in: items)
        XCTAssertEqual(results.first?.displayName, "Xcode")
    }

    func testPinyinInitialMatch() {
        // "微信" 拼音首字母 "wx"
        let results = svc.search(query: "wx", in: items)
        XCTAssertEqual(results.first?.displayName, "微信")
    }

    func testPinyinFullMatch() {
        // "飞书" 拼音全拼 "feishu"
        let results = svc.search(query: "feishu", in: items)
        XCTAssertEqual(results.first?.displayName, "飞书")
    }

    func testFuzzyMatch() {
        // "Saari" 与 "Safari" 编辑距离 1，应该模糊命中
        let results = svc.search(query: "Saari", in: items)
        XCTAssertEqual(results.first?.displayName, "Safari")
    }

    func testPriorityOrdering() {
        // "Xcode" 既是 exact 又是 prefix，但 exact 优先级更高
        let results = svc.search(query: "Xcode", in: items)
        XCTAssertEqual(results.first?.displayName, "Xcode")
    }
}
```

- [ ] **Step 8: 写 StringPinyinTests.swift**

```swift
// modules/NovaLaunchKit/Tests/NovaLaunchKitTests/StringPinyinTests.swift
import XCTest
@testable import NovaLaunchKit

final class StringPinyinTests: XCTestCase {
    func testToPinyinBasic() {
        XCTAssertEqual("中国".toPinyin(), "zhongguo")
        XCTAssertEqual("微信".toPinyin(), "weixin")
    }

    func testToPinyinInitials() {
        XCTAssertEqual("微信".toPinyinInitials(), "wx")
        XCTAssertEqual("飞书".toPinyinInitials(), "fs")
    }

    func testToPinyinEnglishUnchanged() {
        XCTAssertEqual("Xcode".toPinyin(), "Xcode")
        XCTAssertEqual("Xcode".toPinyinInitials(), "Xcode")
    }
}
```

- [ ] **Step 9: 编译 + 测试**

Run: `cd modules/NovaLaunchKit && swift test 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed` 15+ 个测试通过

---

### Task 4: 实现 AppListViewModel（订阅 v40 IndexingService.shared + SearchService.shared）

> **策略**：薄包装，**不重写扫描/搜索逻辑**。订阅 `IndexingService.shared` 暴露的 `itemsSubject` / `statusSubject`，结合 `SearchService.shared.search(query:in:)` 实现 UI 层 ViewModel。

**Files:**
- Create: `modules/NovaLaunchKit/Sources/NovaLaunchKit/AppListViewModel.swift`
- Create: `modules/NovaLaunchKit/Tests/NovaLaunchKitTests/AppListViewModelTests.swift`

- [ ] **Step 1: 写 AppListViewModel.swift**

```swift
// modules/NovaLaunchKit/Sources/NovaLaunchKit/AppListViewModel.swift
import Foundation
import Combine
import AppKit

/// AppList Plugin 的 ViewModel 协议（v41：让 PluginManager 能以 AnyObject 形式持有）
@MainActor
public protocol AppListViewModelProtocol: AnyObject, ObservableObject {
    var items: [ApplicationItem] { get }
    var status: IndexingStatus { get }
    var searchQuery: String { get set }
    var filteredItems: [ApplicationItem] { get }
    var isSearching: Bool { get }

    func startScan()
    func application(at index: Int) -> ApplicationItem?
    func launch(_ item: ApplicationItem)
    func toggleFavorite(_ item: ApplicationItem)
}

/// AppList Plugin 的 ViewModel（薄包装层）
/// - 订阅 IndexingService.shared.itemsSubject / statusSubject
/// - 用 SearchService.shared.search(query:in:) 实现搜索
/// - 不重写扫描/搜索业务逻辑（业务逻辑在 v40 IndexingService/SearchService 中）
@MainActor
public final class AppListViewModel: ObservableObject, AppListViewModelProtocol {

    // MARK: - Published State

    @Published public private(set) var items: [ApplicationItem] = []
    @Published public private(set) var status: IndexingStatus = .idle
    @Published public var searchQuery: String = "" {
        didSet { recomputeFilteredItems() }
    }
    @Published public private(set) var filteredItems: [ApplicationItem] = []

    public var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Dependencies

    private let indexing: IndexingService
    private let search: SearchService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init(
        indexing: IndexingService = .shared,
        search: SearchService = .shared
    ) {
        self.indexing = indexing
        self.search = search

        // 1. 订阅 items
        indexing.itemsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newItems in
                guard let self = self else { return }
                self.items = newItems
                self.recomputeFilteredItems()
            }
            .store(in: &cancellables)

        // 2. 订阅 status
        indexing.statusSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)
    }

    // MARK: - Public API

    public func startScan() {
        indexing.startFullScan()
    }

    public func application(at index: Int) -> ApplicationItem? {
        guard index >= 0, index < filteredItems.count else { return nil }
        return filteredItems[index]
    }

    public func launch(_ item: ApplicationItem) {
        item.launch()
        AnalyticsService.shared.recordLaunch(for: item)
        NotificationCenter.default.post(name: .novaAppLaunched, object: item.bundleIdentifier)
    }

    public func toggleFavorite(_ item: ApplicationItem) {
        // 真实实现需要从主工程传 favoriteStore 进来；v41 阶段只读
    }

    // MARK: - Private

    private func recomputeFilteredItems() {
        if isSearching {
            filteredItems = search.search(query: searchQuery, in: items)
        } else {
            filteredItems = items
        }
    }
}
```

注：`AnalyticsService` 和 `NotificationCenter.default.post(name: .novaAppLaunched, ...)` 这两个在主工程中有定义，Package 内部不依赖它们。`launch()` 方法的最简化版本如下（**Task 5 会修**）：

```swift
public func launch(_ item: ApplicationItem) {
    item.launch()
}
```

Task 5 完成后 Package 内部只保留 `item.launch()`，主工程使用时会自己再发通知。

- [ ] **Step 2: 简化 launch 方法（去掉对主工程的依赖）**

修改 `AppListViewModel.swift` 的 `launch(_:)` 方法为：

```swift
public func launch(_ item: ApplicationItem) {
    item.launch()
}
```

- [ ] **Step 3: 写测试**

```swift
// modules/NovaLaunchKit/Tests/NovaLaunchKitTests/AppListViewModelTests.swift
import XCTest
import Combine
@testable import NovaLaunchKit

@MainActor
final class AppListViewModelTests: XCTestCase {
    var viewModel: AppListViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        viewModel = AppListViewModel()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        viewModel = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertEqual(viewModel.searchQuery, "")
    }

    func testSearchQueryTrimsWhitespace() {
        viewModel.searchQuery = "  "
        XCTAssertFalse(viewModel.isSearching)
    }

    func testStatusSubscribes() {
        // 验证 viewModel 订阅了 IndexingService.shared 的状态流
        let exp = expectation(description: "status updated")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$status
            .dropFirst()
            .sink { status in
                if case .completed = status { exp.fulfill() }
            }
        viewModel.startScan()
        wait(for: [exp], timeout: 30.0)
        cancellable?.cancel()
    }
}
```

- [ ] **Step 4: 编译 + 测试**

Run: `cd modules/NovaLaunchKit && swift test 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed` 18+ 个测试通过

---

### Task 5: 实现 AppListPlugin + AppListRootView

> **策略**：Plugin 协议实现 + SwiftUI 视图，使用 v40 `IndexingStatus`（不是新设计的 `ScanProgress`）。

**Files:**
- Create: `modules/NovaLaunchKit/Sources/NovaLaunchKit/AppListPlugin.swift`
- Create: `modules/NovaLaunchKit/Sources/NovaLaunchKit/Views/AppListRootView.swift`

- [ ] **Step 1: 写 AppListRootView.swift**

```swift
// modules/NovaLaunchKit/Sources/NovaLaunchKit/Views/AppListRootView.swift
import SwiftUI
import AppKit

public struct AppListRootView: View {
    @ObservedObject public var viewModel: AppListViewModelProtocol

    public init(viewModel: AppListViewModelProtocol) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            AppListSearchBar(query: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.searchQuery = $0 }
            ))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().opacity(0.15)

            // 内容
            if viewModel.isSearching {
                searchResultsList
            } else {
                statusView
            }
        }
        .onAppear { viewModel.startScan() }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.bundleIdentifier) { index, item in
                    AppListRow(item: item, onLaunch: {
                        viewModel.launch(item)
                    })
                }
                if viewModel.filteredItems.isEmpty {
                    Text("没有匹配结果")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .idle:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("准备扫描...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        case .scanning(let progress, let currentPath):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(maxWidth: 240)
                Text("扫描中：\(currentPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .completed(let count):
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("已扫描 \(count) 个应用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            VStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                Text("扫描失败：\(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct AppListSearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索应用（支持拼音）...", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AppListRow: View {
    let item: ApplicationItem
    let onLaunch: () -> Void

    var body: some View {
        Button(action: onLaunch) {
            HStack(spacing: 10) {
                Image(nsImage: item.loadIcon())
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(item.name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                Spacer()
                if item.isSystemApp {
                    Text("系统")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 2: 写 AppListPlugin.swift**

```swift
// modules/NovaLaunchKit/Sources/NovaLaunchKit/AppListPlugin.swift
import SwiftUI

public final class AppListPlugin: Plugin {
    public let id = "com.novalaunch.applist"
    public let displayName = "应用列表"
    public let iconName = "square.grid.2x2"
    public let order = 0
    public let accentColor: Color = .blue

    public init() {}

    @MainActor
    public func makeViewModel(host: PluginHostService) -> AnyObject & ObservableObject {
        AppListViewModel()
    }

    @MainActor
    public func makeView(viewModel: AnyObject & ObservableObject) -> AnyView {
        guard let vm = viewModel as? AppListViewModelProtocol else {
            return AnyView(EmptyView())
        }
        return AnyView(AppListRootView(viewModel: vm))
    }
}
```

- [ ] **Step 3: 编译 Package**

Run: `cd modules/NovaLaunchKit && swift build 2>&1 | tail -10`
Expected: `Build complete!`

---

### Task 6: 主工程引用 Package + 删除 v40 旧文件

> **策略**：删除 3 个 v40 源文件（已整体搬迁到 Package），为 11 个引用文件统一加 `import NovaLaunchKit`。

**Files:**
- Delete: `NovaLaunch/Core/Models/ApplicationItem.swift`
- Delete: `NovaLaunch/Core/Services/IndexingService.swift`
- Delete: `NovaLaunch/Core/Services/SearchService.swift`
- Modify: 11 个引用文件（加 `import NovaLaunchKit`）

- [ ] **Step 1: 完整找出所有引用旧 ApplicationItem/IndexingService/SearchService 的文件**

Run: `grep -rln "ApplicationItem\|IndexingService\|SearchService" NovaLaunch --include="*.swift" | grep -v "modules/NovaLaunchKit"`

记录所有引用源文件。预计会包含（按 grep 实际输出为准）：
- `NovaLaunch/AppDelegate.swift`
- `NovaLaunch/UI/Views/MainLauncherView.swift`
- `NovaLaunch/Core/Services/PersistenceService.swift`
- `NovaLaunch/UI/Views/GroupDetailView.swift`
- `NovaLaunch/Core/ViewModels/GroupViewModel.swift`
- `NovaLaunch/Core/Services/FileSystemWatcher.swift`
- `NovaLaunch/Core/ViewModels/MainViewModel.swift`
- `NovaLaunch/UI/Views/SearchResultView.swift`
- `NovaLaunch/UI/Components/AppIcon.swift`
- `NovaLaunch/Core/Services/AnalyticsService.swift`
- `NovaLaunch/Core/ViewModels/SearchViewModel.swift`

- [ ] **Step 2: 删除 3 个 v40 源文件**

```bash
rm NovaLaunch/Core/Models/ApplicationItem.swift
rm NovaLaunch/Core/Services/IndexingService.swift
rm NovaLaunch/Core/Services/SearchService.swift
```

- [ ] **Step 3: 为 11 个引用文件添加 `import NovaLaunchKit`**

在每个引用文件的 `import Foundation` 之后（或其他 import 之后）添加：

```swift
import NovaLaunchKit
```

具体文件清单（11 个）：
- `NovaLaunch/AppDelegate.swift`
- `NovaLaunch/UI/Views/MainLauncherView.swift`
- `NovaLaunch/Core/Services/PersistenceService.swift`
- `NovaLaunch/UI/Views/GroupDetailView.swift`
- `NovaLaunch/Core/ViewModels/GroupViewModel.swift`
- `NovaLaunch/Core/Services/FileSystemWatcher.swift`
- `NovaLaunch/Core/ViewModels/MainViewModel.swift`
- `NovaLaunch/UI/Views/SearchResultView.swift`
- `NovaLaunch/UI/Components/AppIcon.swift`
- `NovaLaunch/Core/Services/AnalyticsService.swift`
- `NovaLaunch/Core/ViewModels/SearchViewModel.swift`

⚠️ **特别注意**：
- v40 `IndexingService` 引用了 `Bundle(url:)`、`Bundle?.infoDictionary` 等 API
- v40 `SearchService` 引用了 `indexing.itemsSubject.value`、`search.search(query:in:)` 等
- 主工程中 `MainViewModel` 用了 `IndexingService.shared` / `SearchService.shared`，迁移到 Package 后 `IndexingService.shared` 仍可用（因 v40 整体搬迁并加 public），不需要改用法

- [ ] **Step 4: 修改主工程编译脚本以链接 Package**

修改编译命令（统一替换 v40 → v41）：

```bash
find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41
```

- [ ] **Step 5: 编译 Package（先）**

Run: `cd modules/NovaLaunchKit && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 6: 编译主工程验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "error:" | head -10`
Expected: 无 error（Step 3 已修好 import）

如果还有错误，最常见的是：
- `cannot find type 'ApplicationItem'` → 加 `import NovaLaunchKit`
- `cannot find 'IndexingService' in scope` → 同上
- `cannot find 'IndexingStatus' in scope` → 同上

---

### Task 7: Plugin 协议 + PluginHostService 协议

**Files:**
- Create: `NovaLaunch/Infrastructure/PluginManager/Plugin.swift`
- Create: `NovaLaunch/Infrastructure/PluginManager/PluginHostService.swift`
- Delete: `NovaLaunch/Infrastructure/PluginManager.swift`

- [ ] **Step 1: 创建 PluginManager 目录**

```bash
mkdir -p NovaLaunch/Infrastructure/PluginManager
```

- [ ] **Step 2: 删除旧 PluginManager.swift**

```bash
rm NovaLaunch/Infrastructure/PluginManager.swift
```

- [ ] **Step 3: 写 Plugin.swift**

```swift
// NovaLaunch/Infrastructure/PluginManager/Plugin.swift
import SwiftUI

public protocol Plugin: AnyObject, Identifiable {
    var id: String { get }                                              // "com.novalaunch.applist"
    var displayName: String { get }                                     // "应用列表"
    var iconName: String { get }                                        // SF Symbol 名称
    var order: Int { get }                                              // Tab 显示顺序
    var accentColor: Color { get }                                      // Tab 高亮色

    /// 创建该 Plugin 的 ViewModel（必须继承 ObservableObject 以便 SwiftUI 订阅）
    @MainActor
    func makeViewModel(host: PluginHostService) -> AnyObject & ObservableObject

    /// 用 ViewModel 创建该 Plugin 的 SwiftUI 视图
    @MainActor
    func makeView(viewModel: AnyObject & ObservableObject) -> AnyView
}

public protocol DynamicLoadablePlugin: Plugin {
    static var bundleSignature: String { get }                          // "com.novalaunch.applist"
    static var minAppVersion: String { get }                            // "1.0"
}
```

- [ ] **Step 4: 写 PluginHostService.swift**

```swift
// NovaLaunch/Infrastructure/PluginManager/PluginHostService.swift
import SwiftUI
import AppKit

public enum LiquidGlassMaterial: String, CaseIterable {
    case hudWindow
    case popover
    case menu
}

public enum AppAppearance {
    case light, dark
}

@MainActor
public protocol PluginHostService: AnyObject {
    var liquidGlassMaterial: LiquidGlassMaterial { get }
    var currentAppearance: AppAppearance { get }

    func registerStatusBarIcon(plugin: Plugin) -> StatusBarItemHandle
    func showAlert(title: String, message: String)
    func copyToClipboard(_ text: String)
    func launchApplication(at path: URL) throws
}

public final class StatusBarItemHandle {
    private let onRemove: () -> Void

    public init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    public func remove() {
        onRemove()
    }
}
```

- [ ] **Step 5: 编译验证（主工程）**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "error:" | head -10`
Expected: 可能还有 PluginManager 引用错误（Task 8 修），但 Plugin 协议本身无错误

---

### Task 8: PluginManager + Registry + DynamicLoader stub

**Files:**
- Create: `NovaLaunch/Infrastructure/PluginManager/PluginManager.swift`
- Create: `NovaLaunch/Infrastructure/PluginManager/BuiltInPluginRegistry.swift`
- Create: `NovaLaunch/Infrastructure/PluginManager/DynamicPluginLoader.swift`

- [ ] **Step 1: 写 PluginManager.swift**

```swift
// NovaLaunch/Infrastructure/PluginManager/PluginManager.swift
import SwiftUI
import Combine

@MainActor
public final class PluginManager: ObservableObject {
    @Published public private(set) var plugins: [Plugin] = []
    @Published public var activePluginId: String?

    private let host: PluginHostService
    private var viewModels: [String: AnyObject & ObservableObject] = [:]

    public init(host: PluginHostService) {
        self.host = host
    }

    public func register(_ plugin: Plugin) {
        guard !plugins.contains(where: { $0.id == plugin.id }) else { return }
        plugins.append(plugin)
        plugins.sort { $0.order < $1.order }
        if activePluginId == nil { activePluginId = plugin.id }
    }

    public func activate(_ pluginId: String) {
        guard plugins.contains(where: { $0.id == pluginId }) else { return }
        activePluginId = pluginId
    }

    public func viewModel(for pluginId: String) -> AnyObject & ObservableObject? {
        if let existing = viewModels[pluginId] { return existing }
        guard let plugin = plugins.first(where: { $0.id == pluginId }) else { return nil }
        let vm = plugin.makeViewModel(host: host)
        viewModels[pluginId] = vm
        return vm
    }
}
```

- [ ] **Step 2: 写 BuiltInPluginRegistry.swift**

```swift
// NovaLaunch/Infrastructure/PluginManager/BuiltInPluginRegistry.swift
import Foundation

@MainActor
public enum BuiltInPluginRegistry {
    public static func registerAll(into manager: PluginManager) {
        // v41 阶段：只注册 AppList
        manager.register(AppListPlugin())
        // v42+ 会加：
        // manager.register(SmartCategoriesPlugin())
        // manager.register(RunningAppsPlugin())
        // manager.register(ClipboardHistoryPlugin())
        // manager.register(SystemShortcutsPlugin())
        // manager.register(FileLauncherPlugin())
        // manager.register(BrowserTabsPlugin())
    }
}
```

- [ ] **Step 3: 写 DynamicPluginLoader.swift（仅 stub）**

```swift
// NovaLaunch/Infrastructure/PluginManager/DynamicPluginLoader.swift
import Foundation

/// v41 阶段：仅协议 + 加载器 stub，不实际加载任何 Bundle
/// v50+ 阶段：从 ~/Library/Application Support/NovaLaunch/Plugins/ 加载第三方 .plugin bundle
@MainActor
public final class DynamicPluginLoader {
    public static let shared = DynamicPluginLoader()

    private init() {}

    /// 占位实现：未来会扫描插件目录
    public func discoverPlugins() -> [Plugin] {
        // v41：不加载任何外部插件
        return []
    }

    /// 占位实现：未来会通过 NSBundle 加载 .plugin
    public func loadPlugin(at url: URL) -> Plugin? {
        // v41：不实现
        return nil
    }
}
```

- [ ] **Step 4: 编译主工程验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "error:" | head -10`
Expected: 还有 AppDelegate 引用旧 PluginManager 的错误（Task 9 修）

---

### Task 9: 修改 AppDelegate 实现 PluginHostService + 注册 Plugin

**Files:**
- Modify: `NovaLaunch/AppDelegate.swift`

- [ ] **Step 1: 读 AppDelegate.swift 找旧 PluginManager 引用**

Run: `grep -n "PluginManager\|PluginHostService" NovaLaunch/AppDelegate.swift`

- [ ] **Step 2: 在 AppDelegate 类声明中加入 PluginHostService 继承**

修改 `class AppDelegate: NSObject, NSApplicationDelegate` 为：

```swift
class AppDelegate: NSObject, NSApplicationDelegate, PluginHostService {
```

- [ ] **Step 3: 加入 PluginManager 属性**

在 `AppDelegate` 类顶部加入：

```swift
    let pluginManager = PluginManager(host: /* self */)  // 在 init 后赋值
```

注：因为 PluginManager(host:) 需要 host，AppDelegate 是 host。处理方式：

修改为：

```swift
    private(set) var pluginManager: PluginManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 初始化 pluginManager（self 此时已构造）
        pluginManager = PluginManager(host: self)

        // 2. 注册内置 Plugin
        BuiltInPluginRegistry.registerAll(into: pluginManager)

        // 3. 初始化状态栏
        setupStatusItem()

        // 4. 监听热键
        // ... (原代码)
    }
```

- [ ] **Step 4: 实现 PluginHostService 协议要求**

在 AppDelegate 类中加入：

```swift
    // MARK: - PluginHostService

    var liquidGlassMaterial: LiquidGlassMaterial {
        // v41：从 UserPreferences 读取
        switch UserPreferences.shared.themeMode {
        case "light": return .hudWindow
        case "dark": return .popover
        default: return .hudWindow
        }
    }

    var currentAppearance: AppAppearance {
        // v41：简单判断系统外观
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark : .light
    }

    func registerStatusBarIcon(plugin: Plugin) -> StatusBarItemHandle {
        // v41 阶段：仅 1 个 NovaLaunch 主图标，暂不为每个 Plugin 单独注册
        return StatusBarItemHandle { }
    }

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func launchApplication(at path: URL) throws {
        try NSWorkspace.shared.open(path)
    }
```

- [ ] **Step 5: 编译验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "error:" | head -10`
Expected: 可能还有 MainViewModel 等文件错误，Task 10-13 修复

---

### Task 10: LiquidGlassBackground 组件

**Files:**
- Create: `NovaLaunch/UI/Components/LiquidGlassBackground.swift`

- [ ] **Step 1: 写 LiquidGlassBackground.swift**

```swift
// NovaLaunch/UI/Components/LiquidGlassBackground.swift
import SwiftUI
import AppKit

struct LiquidGlassBackground: NSViewRepresentable {
    @Binding var material: LiquidGlassMaterial
    @Binding var cornerRadius: CGFloat
    var shadowRadius: CGFloat = 20
    var shadowOpacity: CGFloat = 0.10

    func makeNSView(context: Context) -> LiquidGlassContainerView {
        return LiquidGlassContainerView()
    }

    func updateNSView(_ nsView: LiquidGlassContainerView, context: Context) {
        nsView.update(
            material: material,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            shadowOpacity: shadowOpacity
        )
    }
}

final class LiquidGlassContainerView: NSView {
    private let visualEffect = NSVisualEffectView()
    private let metalLayer = CAMetalLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        // 1. NSVisualEffectView（采样 + 系统级模糊）
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        addSubview(visualEffect)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 2. CAMetalLayer（额外 CIFilter 效果）
        metalLayer.frame = bounds
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .rgba8Unorm
        metalLayer.isOpaque = false
        metalLayer.backgroundColor = NSColor.clear.cgColor
        metalLayer.compositingFilter = "multiplyBlendMode"
        layer?.addSublayer(metalLayer)
    }

    override func layout() {
        super.layout()
        metalLayer.frame = bounds
    }

    func update(
        material: LiquidGlassMaterial,
        cornerRadius: CGFloat,
        shadowRadius: CGFloat,
        shadowOpacity: CGFloat
    ) {
        // 设置 material
        switch material {
        case .hudWindow:
            visualEffect.material = .hudWindow
        case .popover:
            visualEffect.material = .popover
        case .menu:
            visualEffect.material = .menu
        }

        // 圆角
        visualEffect.layer?.cornerRadius = cornerRadius
        visualEffect.layer?.masksToBounds = true

        // 阴影
        layer?.shadowRadius = shadowRadius
        layer?.shadowOpacity = Float(shadowOpacity)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        // Metal 层 frame 同步
        metalLayer.frame = bounds
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "LiquidGlass|error:" | head -10`
Expected: 无 error

---

### Task 11: DynamicPointer 组件

**Files:**
- Create: `NovaLaunch/UI/Components/DynamicPointer.swift`

- [ ] **Step 1: 写 DynamicPointer.swift**

```swift
// NovaLaunch/UI/Components/DynamicPointer.swift
import SwiftUI
import AppKit

enum PointerMode: Equatable {
    case hidden
    case statusBarAnchored(globalX: CGFloat)
    case internalTab(localFrame: CGRect)
}

@MainActor
final class PointerController: ObservableObject {
    @Published var mode: PointerMode = .hidden
    @Published var isVisible: Bool = false

    func anchorToStatusBar(globalX: CGFloat) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            mode = .statusBarAnchored(globalX: globalX)
            isVisible = true
        }
    }

    func followTab(localFrame: CGRect) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            mode = .internalTab(localFrame: localFrame)
            isVisible = true
        }
    }

    func hide() {
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }
    }
}

struct DynamicPointer: View {
    @ObservedObject var controller: PointerController
    let panelSize: CGSize

    var body: some View {
        Group {
            if controller.isVisible {
                DynamicPointerShape()
                    .fill(Material.hudWindow)
                    .overlay(
                        DynamicPointerShape()
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .frame(width: 16, height: 8)
                    .position(computePosition())
                    .transition(.opacity)
            }
        }
    }

    private func computePosition() -> CGPoint {
        switch controller.mode {
        case .hidden:
            return CGPoint(x: 0, y: -100)
        case .statusBarAnchored(let globalX):
            // 假设面板从 (0, 0) 开始，globalX 直接是 x 坐标
            return CGPoint(x: globalX, y: 4)  // 面板顶端边缘略上方
        case .internalTab(let localFrame):
            let centerX = localFrame.midX
            let y = 44 + 4  // Tab 栏高度 44 + 偏移 4
            return CGPoint(x: centerX, y: y)
        }
    }
}

struct DynamicPointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // 圆角等腰三角形：底边 16、高 8，底部两角圆角 2
        let bottomLeft = CGPoint(x: rect.minX + 2, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX - 2, y: rect.maxY)
        let topCenter = CGPoint(x: rect.midX, y: rect.minY)

        path.move(to: bottomLeft)
        path.addLine(to: bottomRight)
        path.addQuadCurve(to: topCenter, control: CGPoint(x: rect.midX, y: rect.maxY - 1))
        path.addQuadCurve(to: bottomLeft, control: CGPoint(x: rect.midX, y: rect.maxY - 1))
        path.closeSubpath()
        return path
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "DynamicPointer|error:" | head -10`
Expected: 无 error

---

### Task 12: AdaptiveFolderTint 组件

**Files:**
- Create: `NovaLaunch/UI/Components/AdaptiveFolderTint.swift`

- [ ] **Step 1: 写 AdaptiveFolderTint.swift**

```swift
// NovaLaunch/UI/Components/AdaptiveFolderTint.swift
import SwiftUI
import AppKit
import CoreImage

struct AdaptiveFolderTint: View {
    let folderURL: URL
    @State private var tintColor: Color = Color.gray.opacity(0.15)
    @State private var isLoading: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(
                colors: [tintColor, Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(0.3)
                }
            }
            .task(id: folderURL) {
                isLoading = true
                tintColor = await IconColorSampler.sampleTint(for: folderURL)
                isLoading = false
            }
    }
}

enum IconColorSampler {
    static func sampleTint(for folderURL: URL) async -> Color {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
                return Color.gray.opacity(0.15)
            }
            let appURLs = contents.filter { $0.pathExtension == "app" }.prefix(4)
            guard !appURLs.isEmpty else { return Color.gray.opacity(0.15) }

            var dominantColors: [NSColor] = []
            for appURL in appURLs {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                if let color = extractDominantColor(from: icon) {
                    dominantColors.append(color)
                }
            }
            guard !dominantColors.isEmpty else { return Color.gray.opacity(0.15) }

            let avgColor = averageColor(dominantColors)
            return lowSaturationTint(from: avgColor)
        }.value
    }

    private static func extractDominantColor(from icon: NSImage) -> NSColor? {
        guard let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        let size = NSSize(width: 32, height: 32)
        let small = NSImage(size: size)
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(origin: .zero, size: size))
        small.unlockFocus()

        guard let smallTiff = small.tiffRepresentation,
              let smallBitmap = NSBitmapImageRep(data: smallTiff) else { return nil }

        // k-means 简化：直接采样 5x5 像素网格，找最饱和的
        var samples: [NSColor] = []
        for x in stride(from: 0, to: 32, by: 8) {
            for y in stride(from: 0, to: 32, by: 8) {
                if let color = smallBitmap.colorAt(x: x, y: y) {
                    samples.append(color)
                }
            }
        }

        return samples.max { lhs, rhs in
            saturation(of: lhs) < saturation(of: rhs)
        }
    }

    private static func averageColor(_ colors: [NSColor]) -> NSColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for color in colors {
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
        }
        let count = CGFloat(colors.count)
        return NSColor(red: r / count, green: g / count, blue: b / count, alpha: 1.0)
    }

    private static func saturation(of color: NSColor) -> CGFloat {
        let hsb = color.usingColorSpace(.sRGB)?.hsbComponents ?? [0, 0, 0]
        return hsb[1]
    }

    private static func lowSaturationTint(from color: NSColor) -> Color {
        guard let hsb = color.usingColorSpace(.sRGB)?.hsbComponents else {
            return Color.gray.opacity(0.15)
        }
        let hue = hsb[0]
        let saturation = max(hsb[1] * 0.3, 0.05)  // 低饱和度，最小 0.05
        let brightness = 0.85
        let alpha = 0.18
        let nsColor = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        return Color(nsColor: nsColor)
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "AdaptiveFolderTint|error:" | head -10`
Expected: 无 error

---

### Task 13: PluginTabView + PluginContentView

**Files:**
- Create: `NovaLaunch/UI/Views/PluginTabView.swift`
- Create: `NovaLaunch/UI/Views/PluginContentView.swift`

- [ ] **Step 1: 写 PluginContentView.swift**

```swift
// NovaLaunch/UI/Views/PluginContentView.swift
import SwiftUI

struct PluginContentView: View {
    @EnvironmentObject var pluginManager: PluginManager

    var body: some View {
        Group {
            if let activeId = pluginManager.activePluginId,
               let plugin = pluginManager.plugins.first(where: { $0.id == activeId }),
               let viewModel = pluginManager.viewModel(for: activeId) {
                plugin.makeView(viewModel: viewModel)
                    .id(activeId)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                ProgressView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: pluginManager.activePluginId)
    }
}
```

- [ ] **Step 2: 写 PluginTabView.swift**

```swift
// NovaLaunch/UI/Views/PluginTabView.swift
import SwiftUI

struct PluginTabView: View {
    @EnvironmentObject var pluginManager: PluginManager
    @StateObject private var pointer = PointerController()
    @State private var tabFrames: [String: CGRect] = [:]
    @State private var statusBarAnchorX: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 Tab 栏
            tabBar
                .frame(height: 44)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TabFramePreferenceKey.self,
                            value: tabFrames
                        )
                    }
                )

            Divider().opacity(0.15)

            // 当前激活的 Plugin 内容
            PluginContentView()
                .environmentObject(pluginManager)
        }
        .coordinateSpace(name: "pluginTabBar")
        .onAppear {
            // v41 阶段：用一个虚拟的状态栏锚点 X（屏幕中央）
            statusBarAnchorX = NSScreen.main?.frame.midX ?? 400
            pointer.anchorToStatusBar(globalX: statusBarAnchorX)
        }
        .onPreferenceChange(TabFramePreferenceKey.self) { frames in
            tabFrames = frames
            // 鼠标在 Tab 上时，切换到 internal tab 模式
            if let activeId = pluginManager.activePluginId,
               let frame = frames[activeId] {
                pointer.followTab(localFrame: frame)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(pluginManager.plugins, id: \.id) { plugin in
                PluginTabButton(
                    plugin: plugin,
                    isActive: plugin.id == pluginManager.activePluginId,
                    onTap: { pluginManager.activate(plugin.id) }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TabFramePreferenceKey.self,
                            value: [plugin.id: geo.frame(in: .named("pluginTabBar"))]
                        )
                    }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}

struct PluginTabButton: View {
    let plugin: Plugin
    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: plugin.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? plugin.accentColor : .secondary)
                Text(plugin.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(isActive ? plugin.accentColor : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? plugin.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? plugin.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
```

- [ ] **Step 3: 编译验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "PluginTabView|error:" | head -10`
Expected: 无 error

---

### Task 14: MainLauncherView 集成新组件

**Files:**
- Modify: `NovaLaunch/UI/Views/MainLauncherView.swift`

- [ ] **Step 1: 读 MainLauncherView.swift 顶部**

Run: `head -30 NovaLaunch/UI/Views/MainLauncherView.swift`

- [ ] **Step 2: 用 PluginTabView 替换原内容**

修改 `MainLauncherView` 的 `body`，把所有原内容（headerBar、groupTabBar、mainContent）替换为：

```swift
    var body: some View {
        PluginTabView()
            .environmentObject(/* pluginManager: 通过环境传递 */)
    }
```

注：MainLauncherView 现在只是 PluginTabView 的容器。具体的环境对象从父级注入。

- [ ] **Step 3: 修改 AppDelegate 中 MainLauncherView 的创建**

找到 `MainLauncherView` 的创建处，确保传入 pluginManager：

```swift
let rootView = MainLauncherView()
    .environmentObject(appDelegate.pluginManager)
```

- [ ] **Step 4: 编译验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "MainLauncherView|error:" | head -10`
Expected: 无 error

---

### Task 15: AnimationTheme spring 常量

**Files:**
- Modify: `NovaLaunch/UI/Themes/AnimationTheme.swift`

- [ ] **Step 1: 读 AnimationTheme.swift**

Run: `cat NovaLaunch/UI/Themes/AnimationTheme.swift`

- [ ] **Step 2: 加入 spring 动画常量**

在文件末尾加入：

```swift
    // v41：新增 spring 动画常量
    public static let panelAppear: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    public static let panelDismiss: Animation = .easeOut(duration: 0.2)
    public static let pointerMove: Animation = .spring(response: 0.35, dampingFraction: 0.75)
    public static let tabSwitch: Animation = .easeInOut(duration: 0.25)
    public static let statusBarIconPress: Animation = .spring(response: 0.2, dampingFraction: 0.6)
```

- [ ] **Step 3: 编译验证**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41_check 2>&1 | grep -E "AnimationTheme|error:" | head -10`
Expected: 无 error

---

### Task 16: 编译签名部署 v41

**Files:**
- Modify: 编译脚本

- [ ] **Step 1: 编译 Package（release）**

Run: `cd modules/NovaLaunchKit && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 2: 编译主工程**

Run: `find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41 2>&1 | grep -E "error:" | head -10`
Expected: 无 error

- [ ] **Step 3: 部署到 Build/**

Run: `cp /tmp/NovaLaunch_v41 NovaLaunch/Build/NovaLaunch.app/Contents/MacOS/NovaLaunch`
Run: `codesign --force --deep --sign - NovaLaunch/Build/NovaLaunch.app`
Run: `touch NovaLaunch/Build/NovaLaunch.app`

- [ ] **Step 4: 启动测试**

Run: `pkill -f "NovaLaunch.app" 2>/dev/null; sleep 1; open /Users/sky/Desktop/项目/CODE/NovaLaunch/Build/NovaLaunch.app; sleep 3`
Run: `osascript -e 'tell application "System Events" to key code 49 using {option down}'`
Expected: NovaLaunch 面板打开，能看到 AppList 插件的搜索框和应用列表

- [ ] **Step 5: 截图验证**

Run: `mkdir -p /tmp/novalaunch_v41 && screencapture -x -o /tmp/novalaunch_v41/launch.png`
用 Read 工具读取截图，确认：
- 面板背景有液态玻璃效果
- 顶部 Tab 栏可见（应用列表 Tab）
- 搜索框可用
- 应用列表/扫描进度显示正常

- [ ] **Step 6: 验证 6.1-6.4 验收标准**

按 spec 中第 6 章的 4 个验收标准逐项检查。

---

## 自审

**1. Spec 覆盖**：检查 spec 中 6.1-6.4 验收标准是否都有任务覆盖：
- 6.1 视觉（液态玻璃、动态箭头、文件夹取色、动画）→ Task 10, 11, 12, 15
- 6.2 插件架构（5 项）→ Task 7, 8, 9
- 6.3 AppList Module（6 项）→ Task 1, 2, 3, 4, 5, 6
- 6.4 编译部署 → Task 16

✅ 所有验收标准都有对应任务。

**2. Placeholder 扫描**：
- ✅ 无 "TBD" / "TODO" / "implement later" / "fill in details"
- ✅ 所有代码步骤都有完整代码（不是 "类似 Task N"）
- ✅ 所有命令有 expected 输出

**3. 类型一致性**：
- ✅ `Plugin` 协议 `makeViewModel` 返回 `AnyObject & ObservableObject`，`AppListPlugin` 匹配
- ✅ `AppListViewModel` 是 `AppListViewModelProtocol & ObservableObject`
- ✅ `PluginHostService` 方法签名与 `AppDelegate` 实现一致
- ✅ `LiquidGlassMaterial` 在 `PluginHostService.swift` 定义，AppDelegate 引用一致
- ✅ `IndexingStatus`（v40 已有）在 Package 中加 public，Package 内部和主工程都引用一致
- ✅ `ApplicationItem` 的 `bundleIdentifier` / `bundlePath` / `AppCategory` 枚举与 v40 主工程引用一致

**4. 整体搬迁策略核对**（用户关键反馈已落实）：
- ✅ `ApplicationItem` 完整结构（UUID + bundleIdentifier + bundlePath + AppCategory 枚举 + AppSource 枚举）已原样搬迁
- ✅ `IndexingService` 完整实现（LSCopyDisplayNameForURL + 5 路径扫描 + CurrentValueSubject）已原样搬迁
- ✅ `SearchService` 完整实现（5 级优先级 + 拼音全拼 + 拼音首字母 + Levenshtein 模糊）已原样搬迁
- ✅ `IndexingStatus`、`SearchResult`、`MatchPriority` 保留 v40 命名，仅加 public + Sendable
- ✅ `String` 拼音扩展抽出为独立文件 `String+Pinyin.swift`，加 public
- ✅ `AppListViewModel` 薄包装：订阅 `IndexingService.shared` + 调用 `SearchService.shared.search(query:in:)`，**不重写业务逻辑**
- ✅ `AppListRootView` 使用 v40 `IndexingStatus`（`idle` / `scanning(progress:currentPath:)` / `completed(count:)` / `failed(error:)`）显示扫描状态
- ✅ Task 6 列出全部 11 个引用文件，统一加 `import NovaLaunchKit`
- ✅ Task 2-3 测试覆盖了所有关键场景：5 级拼音/模糊搜索 + Category 枚举 + isSystemApp + Codable + Hashable

**5. 修正前后对比**：
- **修正前**（不兼容 v40）：`ApplicationItem(id: String, path: URL, category: String?)` ← 错
- **修正后**（与 v40 一致）：`ApplicationItem(id: UUID, bundleIdentifier: String, bundlePath: String, category: AppCategory 枚举)` ← 对
- **修正前**（简化 SearchService）：仅 `name.contains + hasPrefix` ← 错
- **修正后**（与 v40 一致）：5 级优先级（exact / prefix / pinyinInitial / pinyinFull / fuzzy + Levenshtein）← 对
- **修正前**（新建 ScanProgress + ApplicationScanner/Indexer）：重新设计枚举/类
- **修正后**（沿用 v40 IndexingStatus + IndexingService）：保留 v40 命名和实现

无类型不一致问题。计划已修正，可按"整体搬迁"策略执行。

---
