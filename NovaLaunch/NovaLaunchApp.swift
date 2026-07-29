import SwiftUI

@main
struct NovaLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 关键修复：菜单栏应用不应该有默认窗口
    // 之前使用 WindowGroup { EmptyView() } 会导致：
    // 每次启动自动弹出一个空白窗口（用户反馈的"空白页弹窗"）
    // 修复方案：完全移除 Scene，由 AppDelegate 通过 NSStatusItem + NSPopover 管理所有 UI
    var body: some Scene {
        // 不定义任何 Scene，完全由 AppDelegate 控制窗口
        // 这样就避免了 SwiftUI 自动创建空白窗口
        Settings {
            EmptyView()
        }
    }
}
