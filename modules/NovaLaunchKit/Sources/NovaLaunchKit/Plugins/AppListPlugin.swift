// AppList 插件描述符 + Factory
// 策略：v40 没有"视图插件"协议（Task 7 才会创建），本任务暴露元数据 + factory 方法
//       Task 7 创建主工程 Plugin 协议后，本类可作为 Plugin 协议的实现适配过去
//
// 设计动机：
// - 避免与 Task 7 在主工程创建的 Plugin 协议发生重复定义 / 协议签名冲突
// - 保持 Package 自包含：AppListPlugin 不依赖主工程的任何类型
// - 暴露最小元数据（id/displayName/iconName/order/accentColor）+ factory 方法
//   → Task 7 适配时只需让 AppListPlugin 满足 Plugin 协议，descriptor 的字段会自然映射过去
import SwiftUI

// MARK: - AppListPluginDescriptor

/// 插件元数据描述符（v41 临时结构，Task 7 主工程 Plugin 协议会接管这部分职责）
///
/// 字段说明：
/// - `id`：唯一标识符，使用反向域名格式（与 v40 NovaPlugin.pluginID 约定一致）
/// - `displayName`：用户可见的 Tab 名称
/// - `iconName`：SF Symbol 名称（用于 Tab 图标）
/// - `order`：Tab 顺序（升序排列，数字越小越靠前）
/// - `accentColor`：强调色（仅枚举值，不直接依赖 SwiftUI Color → 满足 Sendable）
public struct AppListPluginDescriptor: Sendable {
    public let id: String
    public let displayName: String
    public let iconName: String
    public let order: Int
    public let accentColor: AccentColor

    /// 强调色枚举（Sendable 友好，避免直接持有 SwiftUI Color）
    public enum AccentColor: String, Sendable, CaseIterable {
        case blue, purple, green, orange, red, pink, yellow, gray
    }

    public init(
        id: String = "com.novalaunch.applist",
        displayName: String = "应用列表",
        iconName: String = "square.grid.2x2",
        order: Int = 0,
        accentColor: AccentColor = .blue
    ) {
        self.id = id
        self.displayName = displayName
        self.iconName = iconName
        self.order = order
        self.accentColor = accentColor
    }

    /// 转换为 SwiftUI Color（用于 Tab 高亮）—— 调用方需在 @MainActor 上下文
    @MainActor
    public var swiftUIColor: Color {
        switch accentColor {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .yellow: return .yellow
        case .gray: return .gray
        }
    }
}

// MARK: - AppListPlugin

/// AppList 插件
///
/// 职责：
/// 1. 暴露元数据（`descriptor`）—— PluginManager/Task 7 可读取用于注册 Tab
/// 2. 提供 factory 方法创建 ViewModel 和 SwiftUI 视图
/// 3. Task 7 在主工程创建 `Plugin` 协议后，本类可直接满足该协议（无需修改）
///
/// 线程模型：
/// - 类本身标注 `@MainActor`（viewModel 构造和 view 构造都依赖 SwiftUI main run loop）
/// - factory 方法也都在主 actor 上执行
@MainActor
public final class AppListPlugin {
    /// 当前实例的元数据
    public let descriptor: AppListPluginDescriptor

    public init(descriptor: AppListPluginDescriptor = AppListPluginDescriptor()) {
        self.descriptor = descriptor
    }

    /// 创建该 Plugin 的 ViewModel
    /// - Returns: 满足 `AppListViewModelProtocol` 的具体实现
    public func makeViewModel() -> some AppListViewModelProtocol {
        AppListViewModel()
    }

    /// 用 ViewModel 创建 SwiftUI 视图（返回 `AnyView` 便于 Protocol 化）
    /// - Parameter viewModel: 由 `makeViewModel()` 创建或外部注入的 viewModel
    /// - Returns: 类型擦除后的 SwiftUI 视图
    public func makeView(viewModel: some AppListViewModelProtocol) -> AnyView {
        AnyView(AppListRootView(viewModel: viewModel))
    }

    /// 注册入口（v41 临时静态方法，Task 7 PluginManager 会替换为统一注册 API）
    /// - Returns: 一个新创建的 AppListPlugin 实例
    public static func register() -> AppListPlugin {
        AppListPlugin()
    }
}
