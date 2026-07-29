import Foundation
import AppKit
import SwiftUI

// MARK: - 系统窗口管理插件（v46）

/// 窗口管理插件
/// 数据源：NSWorkspace.shared.runningApplications
/// 过滤：只保留有 UI 的应用（.activationPolicy == .regular）
/// 交互：点击跳转到窗口；关闭按钮关闭窗口
final class WindowPlugin: SearchPluginProtocol {
    let id = "com.novalaunch.window"
    let name = "运行中窗口"
    let icon = "macwindow"
    let keywords = ["window", "win", "窗口", "运行", "running"]
    let isDynamic = true  

    func search(query: String) async -> [PluginResultItem] {
        #if DEBUG
        print("[WindowPlugin] search called with query: '\(query)'")
        #endif

        let runningApps = NSWorkspace.shared.runningApplications
        let visibleApps = runningApps.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != nil
        }

        #if DEBUG
        print("[WindowPlugin] found \(visibleApps.count) visible apps: \(visibleApps.map { $0.localizedName ?? "?" }.joined(separator: ", "))")
        #endif

        
        if query.isEmpty {
            return visibleApps.map { app in makeWindowItem(app) }
        }

        let lowerQuery = query.lowercased()
        let trimmedQuery = lowerQuery.hasPrefix(".") ? String(lowerQuery.dropFirst()) : lowerQuery
        let isKeywordMatch = keywords.contains(where: { trimmedQuery.hasPrefix($0.lowercased()) })

        let filtered = isKeywordMatch ? visibleApps : visibleApps.filter { app in
            (app.localizedName?.lowercased().contains(lowerQuery) ?? false) ||
            (app.bundleIdentifier?.lowercased().contains(lowerQuery) ?? false)
        }

        return filtered.map { app in makeWindowItem(app) }
    }

    private func makeWindowItem(_ app: NSRunningApplication) -> PluginResultItem {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "未知应用"
        let pid = app.processIdentifier
        return PluginResultItem(
            id: "window-\(pid)",
            title: appName,
            subtitle: "PID: \(pid) · \(app.bundleIdentifier ?? "")",
            icon: .appBundleID(app.bundleIdentifier ?? ""),
            pluginID: id,
            action: "activate",
            data: [
                "bundleIdentifier": app.bundleIdentifier ?? "",
                "pid": "\(pid)",
                "appName": appName
            ],
            isClosable: true
        )
    }

    func handle(action: String, item: PluginResultItem) async {
        if action == "activate" || action == "default" {
            // 激活应用窗口
            if let bundleID = item.data?["bundleIdentifier"] {
                let runningApps = NSWorkspace.shared.runningApplications
                if let app = runningApps.first(where: { $0.bundleIdentifier == bundleID }) {
                    app.activate()
                }
            }
        }
    }

    ///
    func close(item: PluginResultItem) async -> Bool {
        guard let bundleID = item.data?["bundleIdentifier"],
              let appName = item.data?["appName"] else { return false }

        // 尝试用 AppleScript 关闭窗口
        let success = await BrowserScriptRunner.closeWindow(appName: appName)

        if !success {
            // AppleScript 失败时，尝试用 NSRunningApplication terminate
            let runningApps = NSWorkspace.shared.runningApplications
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleID }) {
                app.terminate()
                return true
            }
        }

        return success
    }
}

