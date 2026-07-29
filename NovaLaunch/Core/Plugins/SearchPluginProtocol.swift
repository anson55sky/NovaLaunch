import SwiftUI
import AppKit

// MARK: - 搜索插件协议（v46）

/// 搜索插件协议 — 所有搜索增强插件必须实现
/// 与 ViewPlugin（Tab 视图插件）并行，不替代也不继承
/// 设计原则：
/// - 轻量：只要求 search() + handle()，不强制 UI
/// - 异步：search() 返回 async，允许网络/IO 操作
/// - 关键词触发：通过 keywords 匹配快速唤起
protocol SearchPluginProtocol: AnyObject, Identifiable {
    /// 唯一标识符
    var id: String { get }

    /// 显示名称
    var name: String { get }

    /// SF Symbol 图标名
    var icon: String { get }

    /// 触发关键词（如 ["clip", "剪贴板"]）
    /// 当搜索 query 以任一关键词开头时，优先调用此插件的 search()
    var keywords: [String] { get }

    /// PluginManager 知道需要高频刷新或懒加载
    var isDynamic: Bool { get }

    /// 搜索接口
    /// - Parameter query: 用户输入的搜索词
    /// - Returns: 匹配的结果列表
    func search(query: String) async -> [PluginResultItem]

    /// 动作处理接口（如回车后的行为）
    /// - Parameters:
    ///   - action: 动作类型（"copy", "open", "paste" 等）
    ///   - item: 被操作的结果条目
    func handle(action: String, item: PluginResultItem) async

    ///
    /// 返回 false 表示不支持关闭操作
    func close(item: PluginResultItem) async -> Bool

    /// 可选：独立面板 UI
    /// 如果该插件需要专属视图（如剪贴板历史列表），返回 SwiftUI View
    /// 返回 nil 则使用默认搜索结果行样式
    func panelView() -> AnyView?
}

/// 默认实现：panelView 返回 nil
extension SearchPluginProtocol {
    var isDynamic: Bool { false }
    func close(item: PluginResultItem) async -> Bool { false }
    func panelView() -> AnyView? { nil }
}

// MARK: - 插件搜索结果模型

/// 插件搜索结果条目
struct PluginResultItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: PluginResultIcon
    let pluginID: String           // 来源插件 ID
    let action: String             // 默认动作
    let data: [String: String]?    // 附加数据（如剪贴板内容的 hash）
    ///
    var isClosable: Bool = false

    enum PluginResultIcon: Hashable {
        case systemName(String)         // SF Symbol
        case appBundleID(String)        // 应用图标（通过 bundleID 加载）
        case image(NSImage)             // 自定义图片（如剪贴板图片缩略图）

        func hash(into hasher: inout Hasher) {
            switch self {
            case .systemName(let name):
                hasher.combine(0)
                hasher.combine(name)
            case .appBundleID(let bundleID):
                hasher.combine(1)
                hasher.combine(bundleID)
            case .image:
                // NSImage 不可 Hashable，使用指针地址
                hasher.combine(2)
            }
        }

        static func == (lhs: PluginResultIcon, rhs: PluginResultIcon) -> Bool {
            switch (lhs, rhs) {
            case (.systemName(let a), .systemName(let b)):
                return a == b
            case (.appBundleID(let a), .appBundleID(let b)):
                return a == b
            case (.image(let a), .image(let b)):
                return a === b
            default:
                return false
            }
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PluginResultItem, rhs: PluginResultItem) -> Bool {
        lhs.id == rhs.id
    }
}
