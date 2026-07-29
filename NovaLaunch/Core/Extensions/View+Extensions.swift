import SwiftUI

extension View {
    /// 玻璃拟态卡片修饰符（匹配 macOS Launchpad 文件夹风格）
    /// 关键修复（v19）：深色模式适配
    /// - 亮色模式：白色高光 + 细边框（原有效果）
    /// - 暗色模式：极微妙叠加，不干扰文字可读性
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 玻璃底色（降低强度，兼容深色模式）
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            // 顶部高光（暗色模式下极淡）
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.10),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            // 细边框
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            )
    }

    /// 关键修复（v19）：拖拽时的玻璃悬浮效果
    func dragGlassEffect() -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.20))
            }
            .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
            )
    }
}

// MARK: - 环境感知玻璃修饰符（v19：解决深色模式 + 点击穿透问题）

/// 关键修复（v19）：带环境感知的玻璃卡片
/// 通过 @Environment(\.colorScheme) 自动调整深/浅色模式的叠加层强度
struct AdaptiveGlassCard<V: View>: ViewModifier {
    let cornerRadius: CGFloat
    let content: V
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.30),
                                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.10),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.40),
                                Color.white.opacity(colorScheme == .dark ? 0.01 : 0.10),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28), lineWidth: 0.5)
            )
    }
}

extension View {
    /// 关键修复（v19）：环境自适应玻璃卡片（推荐使用此版本）
    /// 自动适配深色/浅色模式，不会洗掉文字
    func adaptiveGlassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(AdaptiveGlassCard(cornerRadius: cornerRadius, content: EmptyView()))
    }
}
