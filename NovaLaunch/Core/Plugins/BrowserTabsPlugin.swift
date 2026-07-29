import Foundation
import SwiftUI
import AppKit

// MARK: - 浏览器标签页插件（v46 升级：真实 AppleScript）

/// 浏览器标签页聚合插件
/// 支持 Safari / Chrome / Arc / Edge
/// 使用 BrowserScriptRunner 执行 AppleScript 获取标签页
/// 防抖策略：缓存结果，避免每次搜索都执行脚本
final class BrowserTabsPlugin: SearchPluginProtocol {
    let id = "com.novalaunch.browsertabs"
    let name = "浏览器标签"
    let icon = "globe"
    let keywords = ["chrome", "safari", "edge", "arc", "tab", "浏览器", "标签"]
    let isDynamic = true  

    /// 标签页缓存（防抖：避免每次搜索都执行 AppleScript）
    private var cachedTabs: [BrowserTabInfo] = []
    private var lastFetchTime: Date = .distantPast
    private let cacheInterval: TimeInterval = 5.0  // 5 秒缓存

    func search(query: String) async -> [PluginResultItem] {
        #if DEBUG
        print("[BrowserTabsPlugin] search called with query: '\(query)'")
        #endif

        await refreshCacheIfNeeded()

        #if DEBUG
        print("[BrowserTabsPlugin] cachedTabs count: \(cachedTabs.count)")
        #endif

        
        if query.isEmpty {
            return cachedTabs.map { tab in makeTabItem(tab) }
        }

        let lowerQuery = query.lowercased()
        let trimmedQuery = lowerQuery.hasPrefix(".") ? String(lowerQuery.dropFirst()) : lowerQuery
        let isKeywordMatch = keywords.contains(where: { trimmedQuery.hasPrefix($0.lowercased()) })

        let filtered = isKeywordMatch ? cachedTabs : cachedTabs.filter { tab in
            tab.title.lowercased().contains(lowerQuery) ||
            tab.url.lowercased().contains(lowerQuery) ||
            tab.browser.lowercased().contains(lowerQuery)
        }

        return filtered.map { tab in makeTabItem(tab) }
    }

    private func makeTabItem(_ tab: BrowserTabInfo) -> PluginResultItem {
        PluginResultItem(
            id: "tab-\(tab.browser)-\(tab.windowIndex)-\(tab.tabIndex)",
            title: tab.title,
            subtitle: "\(tab.browser) · \(tab.url)",
            icon: .systemName(browserIcon(tab.browser)),
            pluginID: id,
            action: "open",
            data: [
                "url": tab.url,
                "browser": tab.browser,
                "windowIndex": "\(tab.windowIndex)",
                "tabIndex": "\(tab.tabIndex)"
            ],
            isClosable: true
        )
    }

    func handle(action: String, item: PluginResultItem) async {
        if action == "open" || action == "default" {
            // 优先：直接切到原浏览器的原 tab（避免在默认浏览器重新打开新窗口）
            let browser = item.data?["browser"] ?? ""
            if let winStr = item.data?["windowIndex"],
               let tabStr = item.data?["tabIndex"],
               let winIndex = Int(winStr),
               let tabIndex = Int(tabStr),
               await BrowserScriptRunner.activateTab(
                   browser: browser, windowIndex: winIndex, tabIndex: tabIndex
               ) {
                return  // 成功切换到原 tab，不再 fallback
            }
            // 兜底：如果激活失败才用默认浏览器打开 URL
            if let urlStr = item.data?["url"], let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    ///
    func close(item: PluginResultItem) async -> Bool {
        guard let browser = item.data?["browser"],
              let winStr = item.data?["windowIndex"],
              let tabStr = item.data?["tabIndex"],
              let winIndex = Int(winStr),
              let tabIndex = Int(tabStr) else { return false }

        return await BrowserScriptRunner.closeTab(browser: browser, windowIndex: winIndex, tabIndex: tabIndex)
    }

    // MARK: - 缓存管理

    private func refreshCacheIfNeeded() async {
        let now = Date()
        guard now.timeIntervalSince(lastFetchTime) > cacheInterval else { return }

        cachedTabs = await BrowserScriptRunner.fetchAllTabs()
        lastFetchTime = now
    }

    private func browserIcon(_ browser: String) -> String {
        switch browser.lowercased() {
        case "chrome": return "globe"
        case "safari": return "safari"
        case "arc": return "globe"
        case "edge": return "globe"
        default: return "globe"
        }
    }
}

