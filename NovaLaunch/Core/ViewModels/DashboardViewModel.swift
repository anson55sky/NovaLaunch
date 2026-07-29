import Foundation
import Combine
import AppKit
import SwiftUI

// MARK: - 仪表盘视图模型（v47）

/// 聚合剪贴板、窗口、标签页数据，为空状态仪表盘提供数据源
/// 设计原则：
/// - 预加载：启动器打开时即开始后台刷新，确保仪表盘显示即内容
/// - 剪贴板直接读取 ClipboardPlugin 的单例实例（避免重复监听）
/// - 窗口/标签页按需刷新
@MainActor
final class DashboardViewModel: ObservableObject {
    static let shared = DashboardViewModel()

    @Published var clipboardEntries: [ClipboardEntry] = []
    @Published var activeWindows: [PluginResultItem] = []
    @Published var browserTabs: [PluginResultItem] = []
    @Published var isReady: Bool = false

    private var refreshTimer: Timer?

    ///
    private var clipboardManager: ClipboardManager { ClipboardManager.shared }

    private var windowPlugin: WindowPlugin? {
        SearchPluginManager.shared.plugins
            .first(where: { $0.id == "com.novalaunch.window" }) as? WindowPlugin
    }

    private var browserPlugin: BrowserTabsPlugin? {
        SearchPluginManager.shared.plugins
            .first(where: { $0.id == "com.novalaunch.browsertabs" }) as? BrowserTabsPlugin
    }

    private init() {}

    func startPreloading() {
        Task { await refreshAll() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshWindowsAndTabs()
            }
        }
    }

    func stopPreloading() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshAll() async {
        await refreshClipboard()
        await refreshWindowsAndTabs()
        isReady = true
    }

    func refreshClipboard() async {
        clipboardEntries = Array(clipboardManager.entries.prefix(8))
    }

    func refreshWindowsAndTabs() async {
        NovaLog.write("DashboardVM", "refreshWindowsAndTabs 开始")
        if let plugin = windowPlugin {
            let items = await plugin.search(query: "")
            activeWindows = Array(items.prefix(20))
            NovaLog.write("DashboardVM", "获取到窗口数量: \(activeWindows.count)")
        } else {
            NovaLog.write("DashboardVM", "windowPlugin 未找到！")
        }
        if let plugin = browserPlugin {
            let items = await plugin.search(query: "")
            browserTabs = Array(items.prefix(20))
            NovaLog.write("DashboardVM", "获取到标签页数量: \(browserTabs.count)")
        } else {
            NovaLog.write("DashboardVM", "browserPlugin 未找到！")
        }
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        clipboardManager.copyToClipboard(entry)
        NotificationCenter.default.post(name: .novaClipboardCopied, object: nil)
    }

    func deleteClipboardEntry(_ entry: ClipboardEntry) {
        withAnimation(.easeOut(duration: 0.2)) {
            clipboardEntries.removeAll { $0.id == entry.id }
        }
        clipboardManager.deleteEntry(entry)
    }

    ///
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary)
    }

    func activateWindow(_ item: PluginResultItem) {
        Task { await SearchPluginManager.shared.handle(action: "activate", item: item) }
    }

    func closeWindow(_ item: PluginResultItem) {
        withAnimation(.easeOut(duration: 0.2)) {
            activeWindows.removeAll { $0.id == item.id }
        }
        Task { _ = await SearchPluginManager.shared.handleClose(item: item) }
    }

    func openTab(_ item: PluginResultItem) {
        Task { await SearchPluginManager.shared.handle(action: "open", item: item) }
    }

    func closeTab(_ item: PluginResultItem) {
        withAnimation(.easeOut(duration: 0.2)) {
            browserTabs.removeAll { $0.id == item.id }
        }
        Task { _ = await SearchPluginManager.shared.handleClose(item: item) }
    }

    // Drag reorder support
    func moveWindow(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < activeWindows.count,
              destination >= 0, destination < activeWindows.count else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            activeWindows.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
        }
    }

    // Reorder by item ID — works with filtered views where indices differ from activeWindows
    func reorderWindow(sourceID: String, targetID: String) {
        guard let srcIdx = activeWindows.firstIndex(where: { $0.id == sourceID }),
              let dstIdx = activeWindows.firstIndex(where: { $0.id == targetID }),
              srcIdx != dstIdx else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let toOffset = dstIdx > srcIdx ? dstIdx + 1 : dstIdx
            activeWindows.move(fromOffsets: IndexSet(integer: srcIdx), toOffset: toOffset)
        }
    }

    func moveTab(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < browserTabs.count,
              destination >= 0, destination < browserTabs.count else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            browserTabs.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
        }
    }
}

extension ClipboardEntry {
    var truncatedText: String {
        if type == .image { return "图片" }
        if content.count <= 60 { return content }
        return String(content.prefix(57)) + "..."
    }

    var relativeTime: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        return "\(Int(interval / 86400))天前"
    }
}
