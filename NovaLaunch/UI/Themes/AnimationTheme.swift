import SwiftUI
import AppKit

/// macOS 27 Liquid Glass 动画系统
///
/// 液态玻璃动画特征：
/// - 流动感：interactiveSpring 让移动像液体一样有惯性
/// - 呼吸感：缓慢的 opacity 变换，像光穿透玻璃
/// - 弹性：soft spring 带来优雅的回弹
enum AnimationTheme {
    // MARK: - 基础动画
    
    /// 标准缓动（元素出现/消失）
    static let standard: Animation = .easeInOut(duration: 0.30)
    /// 弹性弹簧（交互反馈）
    static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.78, blendDuration: 0)

    /// 系统开启"减少运动"时禁用动画
    static func safe(_ animation: Animation = AnimationTheme.standard) -> Animation {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .linear(duration: 0.05)
            : animation
    }

    // MARK: - 面板动画
    
    /// 面板出现 — 轻柔弹出（液态玻璃浮出感）
    public static let panelAppear: Animation = .spring(response: 0.35, dampingFraction: 0.82)
    /// 面板消失 — 柔缓消退
    public static let panelDismiss: Animation = .easeOut(duration: 0.22)
    /// 箭头跟随鼠标 — 略带惯性的流畅追踪
    public static let pointerMove: Animation = .spring(response: 0.28, dampingFraction: 0.78)
    /// 标签切换 — 轻快
    public static let tabSwitch: Animation = .spring(response: 0.25, dampingFraction: 0.85)
    /// 状态栏图标反馈
    public static let statusBarIconPress: Animation = .spring(response: 0.15, dampingFraction: 0.72)
    /// 快速吸附
    public static let snap: Animation = .interactiveSpring(response: 0.22, dampingFraction: 0.88)
    
    // MARK: - 拖拽专属动画（保持曲线一致，避免起停突兀）
    
    /// 拖拽起手 / 落位回弹 — 被拖项轻微下沉成"空洞"，曲线与位移一致
    public static let dragLift: Animation = .spring(response: 0.20, dampingFraction: 0.80)
    /// 相邻图标让位偏移 — 连贯自然，阻尼偏软避免震颤
    public static let dragShift: Animation = .spring(response: 0.30, dampingFraction: 0.82)
    
    // MARK: - macOS 27 玻璃特有动画
    
    /// 玻璃层的呼吸效果 — 极慢的 opacity 脉动
    public static let glassBreathe: Animation = .easeInOut(duration: 4.0)
    /// 卡片 hover 上浮 — 轻量优雅
    public static let cardHover: Animation = .spring(response: 0.32, dampingFraction: 0.80)
    /// 按钮按压 — 微弹
    public static let buttonPress: Animation = .spring(response: 0.18, dampingFraction: 0.70)
    /// 内容切换 — 柔和淡入淡出
    public static let contentFade: Animation = .easeInOut(duration: 0.35)
    /// 列表出现 — 级联延迟
    public static func listStagger(index: Int) -> Animation {
        .spring(response: 0.30, dampingFraction: 0.82)
        .delay(Double(index) * 0.03)
    }
}

