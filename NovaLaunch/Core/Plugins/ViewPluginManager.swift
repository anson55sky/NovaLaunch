// ViewPluginManager — 视图插件管理器
// 策略：与 v40 NovaPlugin (Infrastructure/PluginManager.swift) 并存
//       - v40 PluginManager 负责 Phase 4 通用生态（搜索提供者/主题/小组件/...）
//       - v41 ViewPluginManager 负责"可作为 Tab 展示的视图插件"
//
// 设计动机：
// - 通用 NovaPlugin 不一定需要 viewModel/view（可能只是数据源或 action provider）
// - ViewPlugin 是 NovaPlugin 的"特化子集"，专门服务于主程序 Tab 系统
// - 分离关注点：v40 Manager 管 .bundle 加载，新 Manager 管注册 + Tab 排序 + 当前激活
import SwiftUI
import Combine

/// 视图插件管理器
///
/// 职责：
/// 1. 注册/反注册 `ViewPlugin` 实例
/// 2. 维护按 `order` 排序的插件列表
/// 3. 跟踪当前激活的 Plugin（Tab 选中状态）
/// 4. 提供按 ID 查找、计算当前激活 Plugin 的便捷 API
@MainActor
public final class ViewPluginManager: ObservableObject {

    /// 单例（与 v40 PluginManager.shared 风格一致）
    public static let shared = ViewPluginManager()

    /// 已注册的插件（按 `order` 升序排列，数字越小越靠前）
    @Published public private(set) var plugins: [any ViewPlugin] = []

    /// 当前激活的 Plugin ID（用于 Tab 选中状态）
    @Published public var activePluginID: String?

    private init() {}

    // MARK: - Registration

    /// 注册一个 Plugin
    /// - Parameter plugin: 要注册的 ViewPlugin
    /// - Note: 如果同 ID 的 Plugin 已存在则忽略（保持幂等）
    public func register(_ plugin: any ViewPlugin) {
        if !plugins.contains(where: { $0.id == plugin.id }) {
            plugins.append(plugin)
            plugins.sort { $0.order < $1.order }
        }
    }

    /// 反注册一个 Plugin
    /// - Parameter id: 要反注册的 Plugin ID
    public func unregister(id: String) {
        plugins.removeAll { $0.id == id }
    }

    // MARK: - Lookup

    /// 按 ID 查找 Plugin
    public func plugin(forID id: String) -> (any ViewPlugin)? {
        plugins.first(where: { $0.id == id })
    }

    /// 当前激活的 Plugin（便捷访问）
    /// - 如果 `activePluginID` 为 nil 或指向不存在的 ID，则回退到第一个 Plugin
    public var activePlugin: (any ViewPlugin)? {
        guard let id = activePluginID else { return plugins.first }
        return plugin(forID: id) ?? plugins.first
    }

    // MARK: - Built-in Registration

    /// 注册主工程内置的视图插件
    ///
    /// 应在 `AppDelegate.applicationDidFinishLaunching` 中、Phase 2 偏好加载之后、Phase 3 Plugin 加载之后调用。
    /// 当前内置：
    /// - `AppListPluginAdapter`（包装 Package 内的 `AppListPlugin`）
    public func registerBuiltInPlugins() {
        register(AppListPluginAdapter())
    }
}
