import Foundation
import AppKit

// MARK: - 浏览器 AppleScript 执行器（v46）

/// 通用浏览器 AppleScript 封装
/// 支持 Safari / Chrome / Arc / Edge 四种浏览器
/// 核心设计：
/// - 异步执行，不阻塞主线程
/// - 异常捕获：浏览器未安装/未运行时返回空数组而非崩溃
/// - 防抖策略：避免频繁调用
/// - 统一数据模型 BrowserTabInfo
struct BrowserTabInfo {
    let title: String
    let url: String
    let browser: String          // "Safari" / "Chrome" / "Arc" / "Edge"
    let windowIndex: Int         // AppleScript 窗口索引（1-based）
    let tabIndex: Int            // AppleScript 标签索引（1-based）
}

enum BrowserScriptRunner {

    // MARK: - 支持的浏览器

    /// AppleScript 使用的应用名称（必须与系统一致）
    static let supportedBrowsers: [(name: String, displayName: String, bundleID: String)] = [
        ("Safari",          "Safari",           "com.apple.Safari"),
        ("Google Chrome",   "Chrome",           "com.google.Chrome"),
        ("Arc",             "Arc",              "company.thebrowser.Browser"),
        ("Microsoft Edge",  "Edge",             "com.microsoft.edgemac"),
        ("Tabbit Browser",  "Tabbit",           "com.tab-browser.Tabbit"),
        ("Brave Browser",   "Brave",            "com.brave.Browser"),
        ("Opera",           "Opera",            "com.operasoftware.Opera"),
        ("Firefox",         "Firefox",          "org.mozilla.firefox"),
        ("Vivaldi",         "Vivaldi",          "com.vivaldi.Vivaldi"),
    ]

    // MARK: - 获取所有标签页

    /// 获取所有已安装且运行中的浏览器的标签页
    /// - Returns: 所有标签页的平铺列表
    static func fetchAllTabs() async -> [BrowserTabInfo] {
        await withTaskGroup(of: [BrowserTabInfo].self) { group in
            for browser in supportedBrowsers {
                group.addTask {
                    // 先检查浏览器是否在运行
                    let runningApps = NSWorkspace.shared.runningApplications
                    let isRunning = runningApps.contains { $0.bundleIdentifier == browser.bundleID }
                    NovaLog.write("BrowserScript", "检查 \(browser.displayName): isRunning=\(isRunning)")
                    guard isRunning else { return [] }

                    let tabs = await fetchTabs(for: browser.name, displayName: browser.displayName)
                    NovaLog.write("BrowserScript", "\(browser.displayName) 获取到 \(tabs.count) 个标签")
                    return tabs
                }
            }

            var allTabs: [BrowserTabInfo] = []
            for await tabs in group {
                allTabs.append(contentsOf: tabs)
            }
            NovaLog.write("BrowserScript", "所有浏览器标签总数: \(allTabs.count)")
            return allTabs
        }
    }

    /// 获取指定浏览器的标签页
    static func fetchTabs(for appName: String, displayName: String) async -> [BrowserTabInfo] {
        // Safari 和 Chromium 系的脚本不同
        if appName == "Safari" {
            return await fetchSafariTabs(displayName: displayName)
        } else {
            return await fetchChromiumTabs(appName: appName, displayName: displayName)
        }
    }

    // MARK: - Safari 标签获取

    private static func fetchSafariTabs(displayName: String) async -> [BrowserTabInfo] {
        // 关键：用累积 idx + (idx as string) 显式转换
        // 不要用 "index of w" 直接 & 拼接，AppleScript 旧版本会报 -2741 语法错误
        let script = """
        tell application "Safari"
            set out to {}
            set winIdx to 0
            repeat with w in every window
                set winIdx to winIdx + 1
                set tabIdx to 0
                repeat with t in every tab of w
                    set tabIdx to tabIdx + 1
                    set tTitle to name of t
                    set tURL to URL of t
                    set end of out to (winIdx as string) & "\t" & (tabIdx as string) & "\t" & tTitle & "\t" & tURL
                end repeat
            end repeat
            set AppleScript's text item delimiters to "\n"
            set outText to out as string
            set AppleScript's text item delimiters to ""
            return outText
        end tell
        """

        let results = await runAppleScript(script)
        return parseTabResults(results, browser: displayName)
    }

    // MARK: - Chromium 系标签获取（Chrome / Arc / Edge）

    private static func fetchChromiumTabs(appName: String, displayName: String) async -> [BrowserTabInfo] {
        // 关键：与 Safari 一致，用累积 idx + 显式 (idx as string)
        // 原版用 "id of w" 在某些 Chromium 版本下返回字符串导致 Int 解析失败
        let script = """
        tell application "\(appName)"
            set out to {}
            set winIdx to 0
            repeat with w in every window
                set winIdx to winIdx + 1
                set tabIdx to 0
                repeat with t in every tab of w
                    set tabIdx to tabIdx + 1
                    set tTitle to title of t
                    set tURL to URL of t
                    set end of out to (winIdx as string) & "\t" & (tabIdx as string) & "\t" & tTitle & "\t" & tURL
                end repeat
            end repeat
            set AppleScript's text item delimiters to "\n"
            set outText to out as string
            set AppleScript's text item delimiters to ""
            return outText
        end tell
        """

        let results = await runAppleScript(script)
        return parseTabResults(results, browser: displayName)
    }

    // MARK: - 关闭标签页

    /// 关闭指定浏览器的指定标签页
    static func closeTab(browser: String, windowIndex: Int, tabIndex: Int) async -> Bool {
        let appName = supportedBrowsers.first(where: { $0.displayName == browser })?.name ?? browser

        let script: String
        if appName == "Safari" {
            script = """
            tell application "Safari"
                close tab \(tabIndex) of window \(windowIndex)
            end tell
            """
        } else {
            // Chromium 系：与 fetchTabs 一致，用累积 idx 引用窗口
            script = """
            tell application "\(appName)"
                close tab \(tabIndex) of window \(windowIndex)
            end tell
            """
        }

        return await runAppleScriptBool(script)
    }

    // MARK: - 激活并切到指定 tab

    /// 激活浏览器并切到指定 tab（不重新打开新窗口）
    /// - Returns: true 表示成功切换
    static func activateTab(browser: String, windowIndex: Int, tabIndex: Int) async -> Bool {
        guard let entry = supportedBrowsers.first(where: { $0.displayName == browser }) else {
            NovaLog.write("BrowserScript", "activateTab 失败: 未知浏览器 \(browser)")
            return false
        }
        let appName = entry.name

        let script: String
        if appName == "Safari" {
            script = """
            tell application "Safari"
                activate
                set current tab of window \(windowIndex) to tab \(tabIndex) of window \(windowIndex)
            end tell
            """
        } else {
            // Chromium 系（Chrome / Edge / Arc / Tabbit / Brave / Opera / Vivaldi）
            // 1) 激活应用  2) 设置目标 window active  3) 设置 active tab index
            script = """
            tell application "\(appName)"
                activate
                set index of window \(windowIndex) to 1
                tell window \(windowIndex) to set active tab index to \(tabIndex)
            end tell
            """
        }

        return await runAppleScriptBool(script)
    }

    // MARK: - 关闭窗口

    /// 通过 AppleScript 关闭指定应用的窗口
    static func closeWindow(appName: String, windowIndex: Int = 1) async -> Bool {
        let script = """
        tell application "\(appName)"
            close window \(windowIndex)
        end tell
        """
        return await runAppleScriptBool(script)
    }

    // MARK: - AppleScript 执行引擎

    /// 执行 AppleScript 并返回文本结果
    @discardableResult
    private static func runAppleScript(_ source: String) async -> [String] {
        await Task.detached(priority: .utility) {
            // 用 osascript 子进程替代 NSAppleScript
            // NSAppleScript 在 macOS 27 beta 上会触发 SIGTRAP 崩溃
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus != 0 {
                    let errMsg = String(data: errData, encoding: .utf8) ?? "未知错误"
                    NovaLog.write("BrowserScript", "AppleScript 错误 (exit \(process.terminationStatus)): \(errMsg)")
                    let preview = String(source.prefix(200))
                    NovaLog.write("BrowserScript", "  脚本预览: \(preview)...")
                    return [String]()
                }
                
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                guard let raw = String(data: outData, encoding: .utf8) else {
                    return [String]()
                }
                
                // 按行解析结果
                let lines = raw.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                return lines
            } catch {
                NovaLog.write("BrowserScript", "osascript 启动失败: \(error)")
                return [String]()
            }
        }.value
    }

    /// 执行 AppleScript 返回成功/失败
    private static func runAppleScriptBool(_ source: String) async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    /// 公开的 AppleScript 执行入口（用于主动触发授权弹窗等场景）
    @discardableResult
    static func runAppleScriptOnce(_ source: String) async -> [String] {
        await runAppleScript(source)
    }

    // MARK: - 结果解析

    /// 解析 tab-separated "winIdx\ttabIdx\ttitle\turl" 格式的结果
    private static func parseTabResults(_ results: [String], browser: String) -> [BrowserTabInfo] {
        results.compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4,
                  let winIdx = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let tabIdx = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
                NovaLog.write("BrowserScript", "解析失败: \(line)")
                return nil
            }
            let title = parts[2].trimmingCharacters(in: .whitespaces)
            let url = parts[3].trimmingCharacters(in: .whitespaces)
            return BrowserTabInfo(
                title: title.isEmpty ? "无标题" : title,
                url: url.isEmpty ? "about:blank" : url,
                browser: browser,
                windowIndex: winIdx,
                tabIndex: tabIdx
            )
        }
    }
}
