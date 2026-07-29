// AppListPlugin 的主工程侧 ViewPlugin 适配器（Adapter Pattern）
//
// 为什么需要 Adapter：
// - NovaLaunchKit Package 内部的 `AppListPlugin.makeViewModel()` 返回 `some AppListViewModelProtocol`（不透明类型）
// - 主工程 ViewPlugin 协议要求 `any AppListViewModelProtocol`（existential）
// - Swift 严格模式下，`some` 不能直接隐式转换为 `any`
//   （编译器需要为 existential 分配固定大小的存储 + 见证表）
// - 由于 NovaLaunchKit Package 不可修改，必须在主工程侧写 Adapter 桥接
//
// 实现策略：
// 1. 包装 AppListPlugin 实例
// 2. 把 id/displayName/iconName/order/accentColor 转发到 descriptor
// 3. makeViewModel() 直接转发（编译器会隐式把 `some` 包装为 `any` existential）
// 4. makeView(viewModel:) 用 `as?` cast 回具体类型 AppListViewModel 后再转发给 wrapped
import SwiftUI
import NovaLaunchKit

/// AppListPlugin 的主工程侧 `ViewPlugin` 适配器
///
/// 该 Adapter 把 Package 内的 `AppListPlugin`（返回 `some`）桥接为主工程 `ViewPlugin`（要求 `any`）。
@MainActor
public final class AppListPluginAdapter: ViewPlugin {

    /// 被包装的 Package 内 AppListPlugin 实例
    private let wrapped: AppListPlugin

    public var id: String { wrapped.descriptor.id }
    public var displayName: String { wrapped.descriptor.displayName }
    public var iconName: String { wrapped.descriptor.iconName }
    public var order: Int { wrapped.descriptor.order }
    public var accentColor: Color { wrapped.descriptor.swiftUIColor }

    public init() {
        // 注意：不能写成 `init(plugin: AppListPlugin = AppListPlugin())`
        // AppListPlugin 的 init 是 @MainActor 隔离的，
        // 默认参数值在 nonisolated 上下文求值，Swift 5.10+ 禁止
        // 改为在 init 体内部显式构造（@MainActor 上下文允许）
        self.wrapped = AppListPlugin()
    }

    public init(plugin: AppListPlugin) {
        self.wrapped = plugin
    }

    public func makeViewModel() -> any AppListViewModelProtocol {
        // some AppListViewModelProtocol → any AppListViewModelProtocol
        // 编译器会在此隐式包装为 existential
        wrapped.makeViewModel()
    }

    public func makeView(viewModel: any AppListViewModelProtocol) -> AnyView {
        // any → some 转换需要具体类型
        // wrapped.makeView 签名期望 `some AppListViewModelProtocol`
        // 这里 cast 回具体类型 AppListViewModel 后再转发
        if let concrete = viewModel as? AppListViewModel {
            return wrapped.makeView(viewModel: concrete)
        }
        // fallback：理想情况下不应触发
        // （AppListPlugin.makeViewModel() 总是返回 AppListViewModel）
        return AnyView(EmptyView())
    }
}
