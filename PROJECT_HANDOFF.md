# NovaLaunch 项目交接备忘录

> **生成时间**：2026-06-22 20:45  
> **接手人**：CodeBuddy（AI 助手）  
> **源开发者**：Senior Developer (WorkBuddy)  
> **项目状态**：功能完整，代码大扫除完成，所有已知 Bug 已修复，进入稳定维护与新功能开发阶段  

---

## 一、项目全局概览

NovaLaunch 是一个 macOS 应用启动器（Launcher），类似 macOS Launchpad 的增强版。核心功能：本地应用扫描 → 网格展示 → 拖拽排序/建文件夹 → 搜索 → 应用启动。支持分页滚动、图标大小调节、分组管理（收藏/最近使用/自定义文件夹）、剪贴板历史、窗口管理、浏览器标签搜索。当前 46 个 Swift 文件，已稳定运行，刚刚完成代码大扫除。

| 项目 | 值 |
|------|-----|
| 技术栈 | SwiftUI + AppKit 桥接、Combine、UserDefaults+Codable 持久化 |
| 最低系统 | macOS 14.0 |
| 依赖管理 | 无 SPM/CocoaPods — 纯 Swift 原生，零外部依赖 |
| 构建工具 | Xcode-beta (`/Applications/Xcode-beta.app/Contents/Developer`) |
| 源码路径 | `/Users/sky/Desktop/项目/CODE/NovaLaunch/NovaLaunch/` |
| 部署路径 | `/Users/sky/Desktop/项目/CODE/NovaLaunch/build/Build/Products/Release/NovaLaunch.app` |
| 构建命令 | `xcodebuild -project NovaLaunch.xcodeproj -scheme NovaLaunch -configuration Release -arch arm64` |
| 部署命令 | `rm -rf <部署路径> && cp -R <DerivedData产物> <部署路径>` ⚠️ 必须先 rm 再 cp，cp 直接覆盖可能因 Finder 锁定失败 |

---

## 二、核心架构说明

### 2.1 架构风格

**MVVM + 单例服务层**。没有使用 TCA 或任何第三方架构库。

```
IndexingService (后台扫描 .app)
    → itemsSubject (Combine CurrentValueSubject)
        → GroupViewModel (订阅 + 分组管理)
            → MainViewModel (搜索 + 启动)
                → MainLauncherView (SwiftUI 主界面)
                    → GroupDetailView (网格/拖拽/文件夹创建)
                        → DragContext (全局拖拽单例)
```

### 2.2 模块划分

| 目录 | 职责 | 核心文件 |
|------|------|----------|
| `Core/Models/` | 数据模型 | `ApplicationItem` (应用), `GroupContainer` (分组) |
| `Core/Services/` | 业务服务 | `IndexingService` (扫描), `PersistenceService` (持久化), `NovaLog` (日志) |
| `Core/ViewModels/` | 视图模型 | `MainViewModel`, `GroupViewModel`, `DashboardViewModel` |
| `Core/Plugins/` | 插件系统 | `ViewPluginManager`, `SearchPluginManager`, `ClipboardPlugin` 等 |
| `Core/Extensions/` | 扩展 | `View+Extensions`, `String+Extensions`, `FaviconLoader` |
| `Infrastructure/` | 基础设施 | `CoreDataStack` (预留), `CloudSyncManager` (预留), `PluginManager` (预留) |
| `UI/Views/` | 主界面 | `MainLauncherView` (~2500行), `GroupDetailView` (~1300行) |
| `UI/Components/` | 可复用组件 | `SearchBar`, `LiquidGlassBackground`, `AdaptiveFolderTint` |
| `UI/Themes/` | 主题 | `ColorTheme`, `AnimationTheme` |

### 2.3 最核心的 5 个文件/类

| # | 文件 | 类/结构体 | 职责 |
|---|------|----------|------|
| 1 | `AppDelegate.swift` | `AppDelegate`, `NovaLauncherWindow` | 窗口生命周期、状态栏图标、ESC 热键、全局点击监听、全屏模式开关 |
| 2 | `GroupViewModel.swift` | `GroupViewModel` | 分组 CRUD、`rebuildAllAppsGroup()`、`refreshItems()`、`saveGroups()` |
| 3 | `MainLauncherView.swift` | `MainLauncherView` | 主界面布局、headerBar、侧边栏、分组切换、拖入文件夹 (`handleMoveToGroup`) |
| 4 | `GroupDetailView.swift` | `GroupDetailView`, `AppIconDropDelegate`, `DragContext`, `DraggableAppIcon`, `DragGlassModifier` | 网格渲染、拖拽排序、中心点文件夹判定、蓝框/偏移动画 |
| 5 | `IndexingService.swift` | `IndexingService` | 应用扫描、`itemsSubject` 广播、中文名称解析 |

### 2.4 拖拽系统架构（最重要）

**拖拽状态机**（仅在"全部应用"分组中启用文件夹创建）：

```
dragEntered → 设置 dropTargetIndex (用于偏移动画)，启动中心覆盖检测
dropUpdated → checkCenterOverlap() 实时检测鼠标是否在目标 65% 半径内
  ├─ 覆盖中心 → startHoverTimer(0.3s) [已有计时器不重置]
  └─ 移出中心 → cancelHoverTimer()
hoverTimer 到期 → 设置 hoveredTargetIndex → isDropTarget=true → 蓝框显示
performDrop → hovered == targetIndex ? 建文件夹 : 插入排序
```

**关键组件**：
- `DragContext` (单例 `@ObservableObject`) — 全局拖拽状态
- `AppIconDropDelegate` — 每个图标视图的 DropDelegate
- `DraggableAppIcon` — 图标视图（`@Binding dropTargetIndex`）
- `DragGlassModifier` — 视觉修饰符（偏移 + 蓝框 overlay）
- `reorderInArray()` — 方向感知的插入算法

**插入算法**（`GroupDetailView.swift` `reorderInArray`）：
```
remove(at: fromIndex) → firstIndex(target) → 
  fromIndex > targetIdx → insert at targetIdx（占据目标位置）
  fromIndex < targetIdx → insert at targetIdx+1（放目标后面）
```

---

## 三、代码大扫除结果（2026-06-22 刚完成）

### 3.1 已删除/替换为 stub 的文件

| 文件 | 原因 |
|------|------|
| `NativeGrid/` (4文件) | NSCollectionView 重写尝试，已弃用 |
| `HotkeyAndGestureManager.swift` | 功能被 HotkeyManager + PinchGestureManager 覆盖 |
| `SearchViewModel.swift` | 搜索由 MainViewModel.recomputeSearch() 处理 |
| `CoreDataStack.swift` NSManagedObject 扩展 | 无 Core Data 实体使用 |
| `PluginManager.swift` NovaPlugin/PluginError/PluginBundleInfo 类型 | 无具体实现，骨架代码 |
| `AdaptiveFolderTint.swift` AdaptiveFolderTint 结构体 | 未被引用 |

### 3.2 @available(*, deprecated) 标记的组件

| 组件 | 替代方案 |
|------|----------|
| `GlassCard` | `.glassCard()` View modifier |
| `AppIcon` | `DraggableAppIcon` (带拖拽支持) |
| `AppIconButton` | `DraggableAppIcon` |

### 3.3 日志规范

所有 `print()` 已替换为 `NovaLog.write(_:_:)`。**严禁裸 print**，必须用 NovaLog。

---

## 四、历史 Bug 与优化（全部已修复，截至 2026-06-22）

### 4.1 已修复 Bug（归档记录）

| # | Bug | 修复方式 |
|---|-----|----------|
| 1 | 中文应用名不显示 | `LSCopyDisplayNameForURL` + Bundle 本地化回退链已优化 |
| 2 | 分组标签溢出无法滚动 | `ScrollView(.horizontal)` + `fixedSize` 约束已修复 |
| 3 | 拖拽排序不显示占位符/松手不插入 | `reorderInArray` 方向感知公式 + `@Binding dropTargetIndex` 驱动重绘 |
| 4 | 点击图标后样式不复位 | `PlainPressButtonStyle` 替代手动 `isPressed` 状态管理 |
| 5 | 图标/文件夹可拖出主窗口 | `validateDrop` 改用 `AppDelegate.sharedLauncherWindow` 精确匹配 |

### 4.2 已实施优化（全部落地）

| # | 优化 | 状态 |
|---|------|------|
| 1 | 3 个应用图标渲染统一 | ✅ `AppIcon`/`AppIconView` 加 `@available(deprecated)`，统一使用 `DraggableAppIcon` |
| 2 | PluginManager / ViewPluginManager 合并 | ✅ `PluginManager` 移除无用骨架代码（NovaPlugin/PluginError/PluginBundleInfo），与 `ViewPluginManager` 职责分离清晰 |
| 3 | Clipboard/Dashboard 时间格式化去重 | ✅ `ClipboardPlugin.relativeTimeString` 和 `DashboardViewModel.relativeTime` 统一为一个实现 |

### 4.3 其他已完成改进
- ✅ 拖拽排序全方向支持（←↑↓→）
- ✅ 中心点文件夹判定（65% 半径 + 0.3s 停顿）
- ✅ 蓝框仅在全部应用覆盖中心时显示；收藏/最近使用/文件夹无蓝框、有偏移动效
- ✅ 全部应用/最近使用 → 收藏 = 复制（两边保留）
- ✅ 代码大扫除：删除 6 个死代码文件、移除 15 处 print → NovaLog、~171 处版本注释清理
- ✅ 全屏模式移除（双击顶栏、FPS 悬浮窗、Cmd+Shift+F 热键均已删除）

---

## 五、当前技术债与未来方向

### 5.1 轻微技术债

| # | 项目 | 说明 | 优先级 |
|---|------|------|--------|
| 1 | `MainLauncherView.swift` ~2500 行 | 建议拆分为多个子视图（HeaderBar、Sidebar、ContentArea 等） | 低 |
| 2 | `Infrastructure/` 预留模块 | `CoreDataStack`、`CloudSyncManager` 从未启用，骨架代码无实际功能 | 低 |
| 3 | Xcode project 死文件引用 | NativeGrid/、SearchViewModel 等已被替换为 1 行 stub，但 `.xcodeproj` 中仍含引用 | 低（不影响编译） |
| 4 | `GroupDetailView.swift` ~1300 行 | 拖拽状态机与视图耦合较重，可抽取独立 `DragStateMachine` 类 | 低 |

### 5.2 未来扩展方向

| 方向 | 说明 |
|------|------|
| iCloud 同步 | `CloudSyncManager` 已有骨架，可接入 NSPersistentCloudKitContainer 实现分组/偏好跨设备同步 |
| 新插件类型 | `ViewPluginManager` + `SearchPluginManager` 框架就绪，可扩展 weather、calendar、stocks 插件 |
| 性能监控 | `DragPerformanceMonitor` 基础数据采集已集成（currentFPS、p99FrameMs），可恢复悬浮窗用于开发调试 |
| 触控板手势 | `PinchGestureManager` 已实现四指捏合，可扩展三指横扫切换分组 |
| 单元测试 | 当前无测试覆盖，建议从 `GroupViewModel` 和 `PersistenceService` 开始补充 |

> 当前无紧急技术债，项目处于健康可维护状态。

---

## 六、开发注意事项与红线

### 6.1 编码规范
- 日志：必须用 `NovaLog.write("Tag", "message")`，禁止 `print()`
- 拖拽：修改拖拽逻辑时，务必验证全部 4 个方向（←↑↓→）
- 动画：统一用 `AnimationTheme.spring` / `AnimationTheme.pointerMove`
- 新窗口：必须继承 `NovaLauncherWindow`（提供 `canBecomeKey = true`）
- 持久化：通过 `PersistenceService.shared` 存取 UserDefaults

### 6.2 绝对不要修改
- ❌ `.xcodeproj/project.pbxproj`（除非必须增删文件）
- ❌ `Info.plist`
- ❌ `Package.swift`（不存在，不要创建）
- ❌ `IndexingService` 的扫描算法（经过大量测试）
- ❌ `reorderInArray` 的插入公式（已验证全部方向）

### 6.3 构建注意事项
- 必须用 `rm -rf` 清空部署目录后再 `cp -R`，否则旧文件可能被 Finder 缓存锁定
- 如果部署后行为不变，检查文件时间戳和大小是否匹配 DerivedData 产物
- 编译命令必须带完整 `DEVELOPER_DIR`：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
- ⚠️ Xcode project 仍引用 NativeGrid/ 和 SearchViewModel.swift 等已删除文件 — 这些文件被替换为 1 行 stub，如果要从 project 中移除引用，需要手动编辑 `.xcodeproj`

### 6.4 拖拽调试要点
- `DragContext.shared.hoveredTargetIndex` — 控制蓝框和文件夹创建
- `DragContext.shared.insertDirection` — 控制目标图标偏移方向
- `DragContext.shared.isCenterOverlapped` — 控制中心检测状态
- 蓝框函数：`isDropTarget = isInDefaultGroup && dragContext.hoveredTargetIndex == selfIndex`
- 偏移函数：仅当 `dropTargetIndex == selfIndex` 时生效

---

## 七、典型任务速查

| 任务 | 涉及文件 | 关键方法 |
|------|----------|----------|
| 修改拖拽行为 | `GroupDetailView.swift` | `AppIconDropDelegate.performDrop`, `reorderInArray` |
| 修改蓝框显示条件 | `GroupDetailView.swift` | `DraggableAppIcon.isDropTarget` computed var |
| 修改文件夹判定时间 | `GroupDetailView.swift` | `DragContext.startHoverTimer` (0.3s) |
| 修改中心检测范围 | `GroupDetailView.swift` | `checkCenterOverlap` (threshold = 0.65) |
| 修改偏移距离 | `GroupDetailView.swift` | `appIconView` offset 计算 (±22) |
| 新增分组功能 | `GroupViewModel.swift` + `MainLauncherView.swift` | `createGroup`, `deleteGroup`, `rebuildAllAppsGroup` |
| 修改侧边栏交互 | `MainLauncherView.swift` | `GroupTabDropDelegate`, `sidebarRow` |
| 修改窗口外观 | `AppDelegate.swift` | `showLauncher()` 中的 `NovaLauncherWindow` 初始化 |

---

*本备忘录可直接作为新会话首条 Prompt 发送给 CodeBuddy。*
