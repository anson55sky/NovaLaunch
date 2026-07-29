import SwiftUI

/// macOS 27 Liquid Glass 色彩系统
///
/// 设计理念：
/// - 液态玻璃是主要材质，不是纯色
/// - 颜色半透明，层层叠加产生深度
/// - 光线穿透玻璃形成彩色折射和阴影
/// - 整体感受：空灵、轻盈、流动
enum ColorTheme {
    // MARK: - 玻璃表面
    
    /// 极轻玻璃 — 用于底层/背景
    static let glassUltraThin = Color.white.opacity(0.08)
    /// 轻薄玻璃 — 用于卡片/面板
    static let glassThin = Color.white.opacity(0.15)
    /// 标准玻璃 — 用于主要容器
    static let glassStandard = Color.white.opacity(0.25)
    /// 厚玻璃 — 用于强调区域、弹出层
    static let glassThick = Color.white.opacity(0.40)
    
    // MARK: - 暗色模式玻璃
    static let glassDarkUltraThin = Color.black.opacity(0.06)
    static let glassDarkThin = Color.black.opacity(0.12)
    static let glassDarkStandard = Color.black.opacity(0.18)
    static let glassDarkThick = Color.black.opacity(0.30)
    
    // MARK: - 强调色系（鲜艳半透明）
    
    /// 主色调 — 天蓝
    static let accentBlue = Color(red: 0.24, green: 0.56, blue: 0.98)
    /// 辅助色 — 薄荷绿
    static let accentMint = Color(red: 0.15, green: 0.82, blue: 0.65)
    /// 暖色 — 珊瑚
    static let accentCoral = Color(red: 0.98, green: 0.45, blue: 0.45)
    /// 优雅紫
    static let accentLavender = Color(red: 0.55, green: 0.40, blue: 0.95)
    /// 金色（PRO 专用）
    static let accentGold = Color(red: 0.95, green: 0.72, blue: 0.15)
    
    // MARK: - 玻璃色调微调
    
    /// 天蓝玻璃色调
    static let glassTintBlue = Color(red: 0.24, green: 0.56, blue: 0.98).opacity(0.08)
    /// 薄荷绿玻璃色调
    static let glassTintMint = Color(red: 0.15, green: 0.82, blue: 0.65).opacity(0.06)
    /// 暖色调玻璃
    static let glassTintWarm = Color(red: 0.98, green: 0.45, blue: 0.45).opacity(0.05)
    
    // MARK: - 文字
    
    /// 主文字 — 在玻璃上需保持可读性
    static let textPrimary = Color.primary.opacity(0.92)
    /// 次要文字
    static let textSecondary = Color.secondary.opacity(0.72)
    /// 三级文字/占位符
    static let textTertiary = Color.secondary.opacity(0.45)
    
    // MARK: - 玻璃描边
    
    /// 玻璃边缘高光
    static let glassHighlight = Color.white.opacity(0.55)
    /// 玻璃边缘暗线
    static let glassShadow = Color.black.opacity(0.08)
    
    // MARK: - PRO 徽章
    
    /// PRO 底色（浅红）
    static let proBackground = Color(red: 0.90, green: 0.30, blue: 0.35)
    /// PRO 文字（白色）
    static let proText = Color.white
    /// PRO 边框（金色渐变起止）
    static let proBorderStart = Color(red: 0.95, green: 0.70, blue: 0.10)
    static let proBorderEnd = Color(red: 0.98, green: 0.85, blue: 0.30)
}

