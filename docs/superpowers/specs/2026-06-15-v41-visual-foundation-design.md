# v41 — 视觉基础重构 + 插件架构骨架 + AppList Module 化

**作者**：NovaLaunch 团队
**日期**：2026-06-15
**状态**：Draft → 待用户审阅
**目标 macOS**：14+

---

## 1. 背景与目标

NovaLaunch 已经具备 v40 的功能（应用扫描、搜索、分组、拖拽、热键、捏合手势、窗口/全屏双模式）。用户决定进入"第二阶段核心功能与视觉大改版"，分 6 个版本（v41-v46）逐步交付。

**v41 是这次大改版的第一阶段**，交付 3 件事：

1. **视觉基础重构** —— 模仿 macOS 27 (Beta) 设计语言，引入液态晶透背景、动态小箭头、文件夹自适应取色。
2. **插件架构骨架** —— 在主程序中定义 `Plugin` 协议和 `PluginManager`，为未来模块化提供标准接口。
3. **AppList Module 化** —— 把现有的 `IndexingService` / `SearchService` / `ApplicationItem` 抽出为独立的 Swift Package `NovaLaunchKit`，作为第一个真正的 Plugin。

v41 **不**实现智能分类、运行中应用、浏览器标签页、快捷操作、剪贴板、文件启动 —— 这些分别在 v42-v46 单独交付。

---

## 2. 路线图（v41-v46）

| 版本 | 主题 | 关键交付 |
|------|------|---------|
| **v41** | 视觉 + 插件骨架 + AppList Module | 液态玻璃 + 动态箭头 + 文件夹取色 + Plugin Protocol + NovaLaunchKit Package |
| **v42** | 智能分类系统 | LSApplicationCategoryType + 关键词映射 + 4 预设分类 |
| **v43** | 运行中应用 + 浏览器标签页 | NSWorkspace + AppleScript(Safari/Chrome) |
| **v44** | 系统快捷操作 | 废纸篓/隐藏桌面/锁屏/音量/亮度 |
| **v45** | 剪贴板历史 | NSPasteboard 监听 + 50 条历史 |
| **v46** | 文件/文件夹启动 | 拖入文件夹 + NSWorkspace.open |

---

## 3. v41 详细设计

### 3.1 视觉基础（Visual Foundation）

#### 3.1.1 液态玻璃背景（Liquid Glass Background）

**实现层次**（自下而上）：

```
[NSVisualEffectView]  ← 采样屏幕内容 + 系统级模糊
   ↓
[CAMetalLayer]         ← CIFilter 自定义效果（折射、色彩偏移）
   ↓
[SwiftUI 视图层]       ← 图标、文字、按钮
```

**API 设计**：

```swift
// UI/Components/LiquidGlassBackground.swift
import SwiftUI
import AppKit

public enum LiquidGlassMaterial: String, CaseIterable {
    case hudWindow    // 高度透明 + 模糊
    case popover      // 极高透明（macOS 14+）
    case menu         // 菜单风格
}

struct LiquidGlassBackground: NSViewRepresentable {
    @Binding var material: LiquidGlassMaterial
    @Binding var cornerRadius: CGFloat
    var shadowRadius: CGFloat = 20
    var shadowOpacity: CGFloat = 0.10

    func makeNSView(context: Context) -> LiquidGlassContainerView
    func updateNSView(_ nsView: LiquidGlassContainerView, context: Context)
}

final class LiquidGlassContainerView: NSView {
    private let visualEffect = NSVisualEffectView()
    private let metalLayer = CAMetalLayer()
    private var displayLink: CVDisplayLink?
    // 初始化：visualEffect.material = .hudWindow, blendingMode = .behindWindow
    //         metalLayer 添加到 visualEffect 之上，frame 同步
    //         CIFilter 链：CIGaussianBlur(radius: 30) → CITwirlDistortion → CIConstantColorGenerator(white alpha 0.05)
    //         渲染：每帧用 MTKView 绘制 metalLayer.contents = filteredImage
}
```

**性能考虑**：
- Metal 层只在窗口 resize / move / 主题切换时刷新
- 使用 `CVDisplayLink` 控制 30fps（不需要 60fps，视觉看不出差别）
- 缓存 CIContext，避免重复创建

#### 3.1.2 动态小箭头（Dual-Mode Dynamic Pointer）

**两种模式**：

| 模式 | 触发条件 | 箭头位置 | 箭头方向 | 数据源 |
|------|---------|---------|---------|--------|
| **Status Bar Anchored** | 点击状态栏 NovaLaunch 图标打开面板 | 面板顶端边缘上方 | 向上 | `@State var anchorFrame: CGRect?`（状态栏图标坐标） |
| **Internal Tab Follower** | 鼠标移到内部 Tab 上 / 点击 Tab 切换 | 面板内顶部 Tab 栏正上方 | 向下 | `@State var activeTabFrame: CGRect`（当前激活 Tab 的坐标） |

**切换逻辑**：
- 状态：默认进入 `StatusBarAnchored` 模式
- 鼠标第一次移到内部 Tab → 平滑切换到 `InternalTabFollower` 模式
- 鼠标离开面板 → 重新进入 `StatusBarAnchored` 模式
- 用 `withAnimation(.spring(response: 0.35, dampingFraction: 0.75))` 平滑过渡

**实现**：

```swift
// UI/Components/DynamicPointer.swift
enum PointerMode: Equatable {
    case statusBarAnchored(globalX: CGFloat)
    case internalTab(localFrame: CGRect)
}

@MainActor
final class PointerController: ObservableObject {
    @Published var mode: PointerMode = .statusBarAnchored(globalX: 0)
    @Published var isVisible: Bool = false

    func anchorToStatusBar(globalX: CGFloat) { ... }
    func followTab(localFrame: CGRect) { ... }
    func hide() { ... }
}

struct DynamicPointer: View {
    @ObservedObject var controller: PointerController
    let panelSize: CGSize

    var body: some View {
        DynamicPointerShape()
            .fill(LiquidGlassMaterial.current.gradient)  // 与面板同色
            .frame(width: 16, height: 8)
            .position(computePosition())
            .opacity(controller.isVisible ? 1 : 0)
    }

    private func computePosition() -> CGPoint { ... }
}

struct DynamicPointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        // 圆角等腰三角形：底边 16、高 8，底部两角圆角 2
    }
}
```

#### 3.1.3 文件夹自适应取色（Adaptive Folder Tinting）

**算法流程**：

1. 给定文件夹路径 → 读取前 4 个子项的 App 图标 (`NSWorkspace.icon(forFile:)`)
2. 每个图标缩小到 32×32 像素
3. 用 k-means（k=3）提取主色调（3 个候选色）
4. 选最饱和的一个作为"代表色"
5. 转换到 HSL / Lab 色彩空间：
   - 饱和度 S 乘以 0.3（低饱和度）
   - 亮度 L 设为 0.85（浅色背景）
   - 透明度 α = 0.18
6. 生成 `LinearGradient` 从代表色 → 白色

**实现**：

```swift
// UI/Components/AdaptiveFolderTint.swift
struct AdaptiveFolderTint: View {
    let folderURL: URL
    @State private var tintColor: Color = .gray.opacity(0.15)

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(
                colors: [tintColor, .white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .task {
                tintColor = await IconColorSampler.sampleTint(for: folderURL)
            }
    }
}

enum IconColorSampler {
    static func sampleTint(for folderURL: URL) async -> Color {
        // 1. 读取子项
        // 2. 取前 4 个图标
        // 3. k-means 提取主色
        // 4. 转换到低饱和度 + 高透明
        // 返回 Color
    }
}
```

#### 3.1.4 面板基本参数

- **圆角**：24pt
- **阴影**：radius 20, opacity 0.10, color black
- **默认尺寸**：680 × 460pt（可在设置中调整）
- **内边距**：16pt
- **顶部 Tab 栏高度**：44pt
- **状态栏下方偏移**：8pt
- **背景材质**：默认 `.hudWindow`，可在偏好设置切换 `.popover` / `.menu`

#### 3.1.5 出现动画

- **面板出现**：状态栏图标点击 → 面板从该图标位置 `scale(0.9 → 1.0) + opacity(0 → 1)`，spring(response: 0.35, dampingFraction: 0.8)
- **Tab 切换**：旧 Tab 内容向左滑出 + 新 Tab 内容从右滑入，easeInOut(duration: 0.25)
- **状态栏图标缩放反馈**：点击时状态栏图标 `scale(1.0 → 0.85 → 1.0)`，spring

---

### 3.2 插件架构（Plugin Skeleton）

#### 3.2.1 目录结构

```
NovaLaunch/                                       # 主工程
├── AppDelegate.swift
├── NovaLaunchApp.swift
├── UI/                                            # 所有 UI 在主工程
│   ├── Views/
│   │   ├── MainLauncherView.swift                 # 改：使用 LiquidGlassBackground
│   │   ├── PluginTabView.swift                    # 新：动态 Tab 容器
│   │   └── PluginContentView.swift                # 新：根据当前 Plugin 渲染内容
│   ├── Components/
│   │   ├── LiquidGlassBackground.swift            # 新
│   │   ├── DynamicPointer.swift                   # 新
│   │   └── AdaptiveFolderTint.swift               # 新
│   ├── Themes/
│   │   ├── AnimationTheme.swift                   # 改：新增 spring 动画
│   │   └── ColorTheme.swift                       # 不变
│   └── ...
├── Infrastructure/
│   ├── PluginManager/
│   │   ├── Plugin.swift                           # 新：核心协议
│   │   ├── PluginManager.swift                    # 新：调度器
│   │   ├── PluginHostService.swift                # 新：主工程提供的服务
│   │   ├── BuiltInPluginRegistry.swift            # 新：注册内置 Plugin
│   │   └── DynamicPluginLoader.swift              # 新（预留）：未来 Bundle 加载
│   └── Persistence/                               # 不变
│
Modules/                                           # 独立 Swift Package 目录
└── NovaLaunchKit/                                 # AppList 模块
    ├── Package.swift
    └── Sources/NovaLaunchKit/
        ├── AppListPlugin.swift                    # 实现 Plugin 协议
        ├── ApplicationScanner.swift               # 来自 IndexingService
        ├── ApplicationIndexer.swift               # 来自 IndexingService
        ├── SearchService.swift                    # 来自 SearchService
        ├── AppListViewModel.swift                 # 新：主工程通过它操作
        ├── Models/
        │   ├── ApplicationItem.swift              # 来自 Core/Models
        │   └── ScanProgress.swift                 # 新
        └── Utilities/
            ├── ApplicationPaths.swift
            └── IconCache.swift
```

#### 3.2.2 核心协议

```swift
// Infrastructure/PluginManager/Plugin.swift
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

public extension Plugin {
    var id: String { String(reflecting: Self.self) }
}

// 未来扩展：动态加载
public protocol DynamicLoadablePlugin: Plugin {
    static var bundleSignature: String { get }                          // "com.novalaunch.applist"
    static var minAppVersion: String { get }                            // "1.0"
}
```

```swift
// Infrastructure/PluginManager/PluginHostService.swift
import SwiftUI
import AppKit

@MainActor
public protocol PluginHostService: AnyObject {
    var liquidGlassMaterial: LiquidGlassMaterial { get }
    var currentAppearance: AppAppearance { get }
    var userPreferences: UserPreferences { get }

    func registerStatusBarIcon(plugin: Plugin) -> StatusBarItemHandle
    func showAlert(title: String, message: String)
    func copyToClipboard(_ text: String)
}

public final class StatusBarItemHandle {
    public func updateTitle(_ title: String) { ... }
    public func remove() { ... }
}
```

```swift
// Infrastructure/PluginManager/PluginManager.swift
import SwiftUI
import Combine

@MainActor
public final class PluginManager: ObservableObject {
    @Published public private(set) var plugins: [Plugin] = []
    @Published public var activePluginId: String?

    private let host: PluginHostService
    private var viewModels: [String: AnyObject] = [:]

    public init(host: PluginHostService) { self.host = host }

    public func register(_ plugin: Plugin) {
        plugins.append(plugin)
        plugins.sort { $0.order < $1.order }
        if activePluginId == nil { activePluginId = plugin.id }
    }

    public func activate(_ pluginId: String) { ... }
    public func viewModel(for pluginId: String) -> AnyObject? { ... }
}
```

#### 3.2.3 主工程集成

```swift
// NovaLaunchApp.swift
@main
struct NovaLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup { EmptyView() }
    }
}

// AppDelegate.swift（节选）
class AppDelegate: NSObject, NSApplicationDelegate, PluginHostService {
    let pluginManager: PluginManager

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 创建 PluginHostService
        pluginManager = PluginManager(host: self)

        // 2. 注册内置 Plugin
        BuiltInPluginRegistry.registerAll(into: pluginManager)

        // 3. 初始化状态栏图标
        setupStatusItem()

        // 4. 监听热键
        hotkeyManager.onTriggered = { [weak self] in
            self?.toggleLauncher()
        }
    }
}

enum BuiltInPluginRegistry {
    static func registerAll(into manager: PluginManager) {
        // v41 阶段：只注册 AppList
        manager.register(AppListPlugin())
        // v42+ 会加：SmartCategoriesPlugin()、RunningAppsPlugin() 等
    }
}
```

#### 3.2.4 视图层集成

```swift
// UI/Views/PluginTabView.swift
struct PluginTabView: View {
    @EnvironmentObject var pluginManager: PluginManager
    @StateObject private var pointer = PointerController()
    @State private var tabFrames: [String: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 Tab 栏
            HStack(spacing: 4) {
                ForEach(pluginManager.plugins, id: \.id) { plugin in
                    PluginTabButton(
                        plugin: plugin,
                        isActive: plugin.id == pluginManager.activePluginId,
                        onTap: { pluginManager.activate(plugin.id) },
                        onHover: { frame in
                            pointer.followTab(localFrame: frame)
                        }
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TabFrameKey.self,
                                value: [plugin.id: geo.frame(in: .named("pluginTabBar"))]
                            )
                        }
                    )
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 8)
            .coordinateSpace(name: "pluginTabBar")

            Divider().opacity(0.15)

            // 当前激活的 Plugin 内容
            if let activeId = pluginManager.activePluginId,
               let plugin = pluginManager.plugins.first(where: { $0.id == activeId }),
               let viewModel = pluginManager.viewModel(for: activeId) {
                plugin.makeView(viewModel: viewModel)
                    .id(activeId)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .background(LiquidGlassBackground(material: .constant(.hudWindow), cornerRadius: .constant(24)))
        .overlay(alignment: .top) { DynamicPointer(controller: pointer, panelSize: /*...*/) }
    }
}
```

---

### 3.3 AppList Module（NovaLaunchKit）

#### 3.3.1 Package.swift

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

#### 3.3.2 模块边界

**模块暴露的 API**（其他模块可见）：

```swift
public protocol AppListViewModelProtocol: AnyObject, ObservableObject {
    var applications: [ApplicationItem] { get }
    var scanProgress: ScanProgress { get }
    var searchQuery: String { get set }
    var searchResults: [ApplicationItem] { get }

    func startScan()
    func application(at index: Int) -> ApplicationItem?
    func launchApplication(_ item: ApplicationItem) throws
}

public struct ApplicationItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String                  // bundle identifier
    public var displayName: String
    public var path: URL
    public var iconPath: URL?
    public var category: String?           // 来自 Info.plist LSApplicationCategoryType
    public var lastLaunched: Date?
    public var launchCount: Int

    public init(...) { ... }
}

public enum ScanProgress: Equatable {
    case idle
    case scanning(processed: Int, total: Int)
    case completed(count: Int)
    case failed(reason: String)
}
```

**模块不暴露**（保留在主工程 UI 层）：
- 拖拽逻辑（`onDrag` / `onDrop`）
- 分组 Tab（`GroupContainer` / `GroupViewModel`）
- 拖拽时 `DragContext` 状态
- PagingScrollView 渲染
- ContextMenu 右键菜单

#### 3.3.3 AppListPlugin 实现

```swift
// Sources/NovaLaunchKit/AppListPlugin.swift
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
        AppListViewModel(
            scanner: ApplicationScanner(),
            indexer: ApplicationIndexer(),
            searchService: SearchService()
        )
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

#### 3.3.4 主工程引用方式

主工程通过 Swift Package Manager 引用本地 Package：

```bash
# 在 NovaLaunch.xcodeproj 中：
# File > Add Packages... > Add Local... > 选择 modules/NovaLaunchKit
```

**编译命令调整**（保留 v40 风格的命令行编译）：
```bash
swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library \
  NovaLaunch/**/*.swift -o /tmp/NovaLaunch_v41
```

---

## 4. 数据流

```
1. 用户点击状态栏 NovaLaunch 图标
   ↓
2. AppDelegate.hotkeyManager.onTriggered → toggleLauncher()
   ↓
3. showLauncher() 创建 NSWindow（如果还没创建）
   ↓
4. MainLauncherView 渲染：
   - 背景：LiquidGlassBackground（NSVisualEffectView + CAMetalLayer）
   - 顶部：PluginTabView（包含 DynamicPointer）
   - 内容：当前激活 Plugin 的 View
   ↓
5. PluginTabView 启动时通过 PluginManager 拿到所有 Plugin
   ↓
6. 激活第一个 Plugin（AppListPlugin）
   ↓
7. PluginManager 调用 makeViewModel → 拿到 AppListViewModelProtocol
   ↓
8. PluginManager 调用 makeView(viewModel) → 拿到 SwiftUI 视图
   ↓
9. AppListRootView 通过 viewModel 加载应用列表
   ↓
10. 鼠标在 Tab 栏移动 → PointerController.followTab()
    ↓
11. DynamicPointer 用 withAnimation 滑动到新位置
    ↓
12. 鼠标点击 Tab → pluginManager.activate(newId)
    ↓
13. 旧 Plugin 视图向左滑出 + 新 Plugin 视图从右滑入
    ↓
14. 鼠标点击面板外部（v40 已实现 NSEvent.addLocalMonitorForEvents）→ 关闭
```

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| Metal 渲染掉帧 | 视觉卡顿 | 静态背景用 Metal 缓存 framebuffer；只在 resize/move 时重算；CVDisplayLink 30fps |
| 插件架构过度设计 | v41 完成不了 | 只做 Protocol + 1 个示例 Module；DynamicPluginLoader 留 stub |
| AppList 抽离破坏现有功能 | 用户体验下降 | 编译命令同时支持原 v40 编译路径（保留原文件做 fallback）；新代码走 Package 路径；上线前在两种模式都测一遍 |
| 状态栏多图标开发量大 | v41 延期 | v41 **只做 1 个状态栏图标 + 内部 Tab 切换**；多状态栏图标留到 v42+ |
| 动态箭头状态切换视觉不连贯 | 视觉体验差 | 状态切换用 spring 动画 + 位置缓动；目标 X 计算用 `Animation.interpolatingSpring` |
| 文件夹取色对深色背景不友好 | 视觉效果差 | 自适应 brightness 检测：深色背景用低饱和度高亮，浅色背景用低饱和度中色 |

---

## 6. 验收标准

### 6.1 视觉

- [ ] 面板背景可见液态玻璃效果（NSVisualEffectView + CIFilter/Metal）
- [ ] 状态栏图标点击后面板有 `scale(0.9→1.0) + fade in` 动画，spring 缓动
- [ ] 动态小箭头出现在面板顶端边缘，宽度 16pt、高度 8pt、圆角等腰三角形
- [ ] 面板刚出现时箭头指向状态栏图标正下方
- [ ] 鼠标移到内部 Tab 时，箭头平滑（spring）滑动到 Tab 上方
- [ ] 拖入 3 个不同 App 组成的文件夹，文件夹背景色明显不同
- [ ] 圆角 24pt、阴影 radius 20 opacity 0.10

### 6.2 插件架构

- [ ] `Plugin` 协议定义清晰，含 id / displayName / iconName / order / accentColor / makeViewModel(返回 `AnyObject & ObservableObject`) / makeView(接收 `AnyObject & ObservableObject`)
- [ ] `PluginHostService` 协议定义清晰，提供 liquidGlassMaterial / appearance / preferences / copyToClipboard 等
- [ ] `PluginManager` 实例管理所有 Plugin（由 AppDelegate 持有），支持 register / activate / viewModel(for:)
- [ ] `BuiltInPluginRegistry` 在 AppDelegate 启动时注册所有内置 Plugin
- [ ] `DynamicPluginLoader` 留 stub（仅协议，无实现），未来扩展

### 6.3 AppList Module

- [ ] `modules/NovaLaunchKit/Package.swift` 可独立 `swift build` 编译通过
- [ ] `NovaLaunchKit` 暴露 `AppListViewModelProtocol` / `ApplicationItem` / `ScanProgress` / `AppListPlugin`
- [ ] 主工程通过 SPM 引用 `NovaLaunchKit`，编译通过
- [ ] v40 的所有应用扫描、搜索功能完全保留
- [ ] 主工程 UI 层（拖拽、分组、PagingScrollView、ContextMenu）保持不变
- [ ] 删除主工程中原 `Core/Services/IndexingService.swift` / `SearchService.swift` / `Models/ApplicationItem.swift` 旧路径（不重复编译）

### 6.4 编译部署

- [ ] `swiftc` 编译命令调整后能成功生成 `/tmp/NovaLaunch_v41`
- [ ] `cp` + `codesign` 部署到 `Build/NovaLaunch.app`
- [ ] 启动后状态栏图标可见，按热键面板能打开
- [ ] 打开后所有功能正常（搜索、拖拽、分组、捏合手势等）

### 6.5 性能

- [ ] 面板打开响应 < 100ms
- [ ] 箭头移动 60fps 流畅
- [ ] 状态栏图标点击反馈 < 50ms

---

## 7. 不在 v41 范围

- ❌ 智能分类（v42）
- ❌ 运行中应用列表（v43）
- ❌ 浏览器标签页集成（v43）
- ❌ 系统快捷操作（v44）
- ❌ 剪贴板历史（v45）
- ❌ 文件/文件夹启动（v46）
- ❌ 多状态栏图标（v42+）
- ❌ 动态加载第三方 Plugin Bundle（v50+）
- ❌ macOS 13 兼容（v41+ 仅支持 macOS 14）

---

## 8. 附录

### 8.1 编译命令模板（v41）

```bash
# 1. 编译 NovaLaunchKit Package
cd /Users/sky/Desktop/项目/CODE/NovaLaunch/modules/NovaLaunchKit
swift build -c release

# 2. 编译主工程
cd /Users/sky/Desktop/项目/CODE/NovaLaunch
find NovaLaunch -name "*.swift" | xargs swiftc -target arm64-apple-macos14.0 \
  -I modules/NovaLaunchKit/.build/release \
  -L modules/NovaLaunchKit/.build/release \
  -lNovaLaunchKit \
  -framework SwiftUI -framework AppKit -framework CoreData -framework CloudKit -framework Combine \
  -parse-as-library -o /tmp/NovaLaunch_v41

# 3. 部署
cp /tmp/NovaLaunch_v41 Build/NovaLaunch.app/Contents/MacOS/NovaLaunch
codesign --force --deep --sign - Build/NovaLaunch.app
touch Build/NovaLaunch.app
```

### 8.2 测试命令

```bash
# 启动
pkill -f "NovaLaunch.app" 2>/dev/null; sleep 1
open /Users/sky/Desktop/项目/CODE/NovaLaunch/Build/NovaLaunch.app
sleep 3

# 唤起面板
osascript -e 'tell application "System Events" to key code 49 using {option down}'

# 验证窗口
swift -e '
import CoreGraphics
let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for info in list {
    if let owner = info[kCGWindowOwnerName as String] as? String, owner == "NovaLaunch",
       let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] {
        print("Window: \(bounds["Width"] ?? 0)x\(bounds["Height"] ?? 0) at (\(bounds["X"] ?? 0),\(bounds["Y"] ?? 0))")
    }
}
'
```

### 8.3 文件清单

**新增**：
- `NovaLaunch/UI/Components/LiquidGlassBackground.swift`
- `NovaLaunch/UI/Components/DynamicPointer.swift`
- `NovaLaunch/UI/Components/AdaptiveFolderTint.swift`
- `NovaLaunch/UI/Views/PluginTabView.swift`
- `NovaLaunch/UI/Views/PluginContentView.swift`
- `NovaLaunch/Infrastructure/PluginManager/Plugin.swift`
- `NovaLaunch/Infrastructure/PluginManager/PluginHostService.swift`
- `NovaLaunch/Infrastructure/PluginManager/PluginManager.swift`
- `NovaLaunch/Infrastructure/PluginManager/BuiltInPluginRegistry.swift`
- `NovaLaunch/Infrastructure/PluginManager/DynamicPluginLoader.swift`
- `modules/NovaLaunchKit/Package.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/AppListPlugin.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/AppListViewModel.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/ApplicationScanner.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/ApplicationIndexer.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/SearchService.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Models/ApplicationItem.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Models/ScanProgress.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Utilities/ApplicationPaths.swift`
- `modules/NovaLaunchKit/Sources/NovaLaunchKit/Utilities/IconCache.swift`

**修改**：
- `NovaLaunch/AppDelegate.swift` — 实现 `PluginHostService`，注册 Plugin
- `NovaLaunch/NovaLaunchApp.swift` — 适配新架构
- `NovaLaunch/UI/Views/MainLauncherView.swift` — 使用 `PluginTabView` 替换原内容
- `NovaLaunch/UI/Themes/AnimationTheme.swift` — 新增 spring 动画常量

**删除**（已迁移到 NovaLaunchKit）：
- `NovaLaunch/Core/Services/IndexingService.swift`（移到 `ApplicationIndexer.swift`）
- `NovaLaunch/Core/Services/SearchService.swift`（移到 `SearchService.swift`）
- `NovaLaunch/Core/Models/ApplicationItem.swift`（移到 `Models/ApplicationItem.swift`）
- `NovaLaunch/Core/ViewModels/MainViewModel.swift`（应用扫描部分移到 `AppListViewModel.swift`，UI 部分保留或重构）
- `NovaLaunch/Infrastructure/PluginManager.swift`（替换为新的 PluginManager/ 目录）
