// ViewPlugin 协议 — 主工程侧的"插件 ↔ 宿主"边界契约
// 策略：在主工程定义协议，NovaLaunchKit 内部 Package 不感知此协议
//       任何想要被 ViewPluginManager 管理的视图插件必须实现此协议
//
// 设计动机：
// - v40 NovaPlugin 协议是"通用插件生态"协议（不绑定视图），本协议专注于"视图插件"
// - 协议要求使用 `any AppListViewModelProtocol`（existential），
//   使 PluginManager 可以在 `[ViewPlugin]` 集合中统一管理（`some` 不透明类型不可集合化）
// - 标注 `@MainActor`：工厂方法（makeViewModel / makeView）涉及 SwiftUI 主 run loop
// - 继承 `Identifiable`：便于 SwiftUI ForEach / List 遍历
import SwiftUI
import NovaLaunchKit

/// 视图插件协议
///
/// 任何想要被 `ViewPluginManager` 管理的 SwiftUI 视图插件必须实现此协议。
/// 协议实现者应当是 `@MainActor` 的 class（构造 viewModel/view 必须运行在主线程上）。
@MainActor
public protocol ViewPlugin: AnyObject, Identifiable {
    /// 唯一标识符（与 NovaPlugin.pluginID / AppListPluginDescriptor.id 对齐）
    var id: String { get }

    /// 显示名称（用作 Tab 标题）
    var displayName: String { get }

    /// SF Symbol 图标名（用作 Tab 图标）
    var iconName: String { get }

    /// Tab 排序（升序，数字越小越靠前）
    var order: Int { get }

    /// Tab 高亮色
    var accentColor: Color { get }

    /// 工厂方法：创建该 Plugin 的 ViewModel
    /// - Returns: 满足 `AppListViewModelProtocol` 的实例（existential）
    func makeViewModel() -> any AppListViewModelProtocol

    /// 工厂方法：使用 ViewModel 创建 SwiftUI 视图
    /// - Parameter viewModel: 由 `makeViewModel()` 创建或外部注入的 viewModel
    /// - Returns: 类型擦除后的 SwiftUI 视图
    func makeView(viewModel: any AppListViewModelProtocol) -> AnyView
}
