import Foundation
import Combine
import SwiftUI

// MARK: - 搜索插件管理器（v45）

/// 搜索插件管理器
/// 职责：
/// 1. 注册/反注册 SearchPluginProtocol 插件
/// 2. 搜索聚合：并行调用所有插件的 search()，汇总结果
/// 3. 关键词匹配：当 query 匹配某插件的 keywords 时，优先返回该插件结果
/// 4. 生命周期管理
@MainActor
final class SearchPluginManager: ObservableObject {
    static let shared = SearchPluginManager()

    /// 已注册的搜索插件
    private(set) var plugins: [any SearchPluginProtocol] = []

    /// 最近一次搜索结果（按插件分组）
    @Published var searchResults: [PluginResultItem] = []

    /// 当前激活的插件专属视图（当关键词匹配时显示）
    @Published var activePluginPanel: AnyView?

    private init() {}

    // MARK: - 注册

    func register(_ plugin: any SearchPluginProtocol) {
        if !plugins.contains(where: { $0.id == plugin.id }) {
            plugins.append(plugin)
        }
    }

    func unregister(id: String) {
        plugins.removeAll { $0.id == id }
    }

    // MARK: - 搜索聚合

    /// 搜索：并行调用所有插件，汇总结果
    /// - Parameter query: 用户输入
    /// - Returns: 汇总后的结果列表
    func search(query: String) async -> [PluginResultItem] {
        guard !query.isEmpty else {
            searchResults = []
            activePluginPanel = nil
            return []
        }

        // 检查是否匹配某插件的 keywords
        let matchedPlugin = findPluginByKeyword(query)

        // 如果匹配，显示该插件的专属面板
        if let plugin = matchedPlugin {
            activePluginPanel = plugin.panelView()
        } else {
            activePluginPanel = nil
        }

        // 并行搜索所有插件
        var allResults: [PluginResultItem] = []

        await withTaskGroup(of: [PluginResultItem].self) { group in
            for plugin in plugins {
                // 如果匹配了特定插件，只搜索该插件（优先模式）
                if matchedPlugin != nil && plugin.id != matchedPlugin?.id {
                    continue
                }
                group.addTask {
                    await plugin.search(query: query)
                }
            }

            for await results in group {
                allResults.append(contentsOf: results)
            }
        }

        searchResults = allResults
        return allResults
    }

    /// 处理动作
    func handle(action: String, item: PluginResultItem) async {
        guard let plugin = plugins.first(where: { $0.id == item.pluginID }) else { return }
        await plugin.handle(action: action, item: item)
    }

    ///
    func handleClose(item: PluginResultItem) async -> Bool {
        guard let plugin = plugins.first(where: { $0.id == item.pluginID }) else { return false }
        return await plugin.close(item: item)
    }

    // MARK: - 关键词匹配

    /// 检查 query 是否以某插件的 keywords 开头
    private func findPluginByKeyword(_ query: String) -> (any SearchPluginProtocol)? {
        let lowerQuery = query.lowercased()
        // 支持 ".clip" 和 "clip" 两种格式
        let trimmedQuery = lowerQuery.hasPrefix(".") ? String(lowerQuery.dropFirst()) : lowerQuery

        for plugin in plugins {
            if plugin.keywords.contains(where: { trimmedQuery.hasPrefix($0.lowercased()) }) {
                return plugin
            }
        }
        return nil
    }

    // MARK: - 内置插件注册

    /// 注册内置搜索插件
    func registerBuiltInPlugins() {
        register(ClipboardPlugin())
        register(BrowserTabsPlugin())
        register(WindowPlugin())  
    }
}
