import SwiftUI

// MARK: - iOS 27 Liquid Glass (v2 — 拆分版)

struct LiquidGlassBaseModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

struct LiquidGlassEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .drawingGroup()
    }
}

struct LiquidGlassHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .brightness(isHovered ? 0.1 : 0.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func liquidGlassBase() -> some View { modifier(LiquidGlassBaseModifier()) }
    func liquidGlassEdge() -> some View { modifier(LiquidGlassEdgeModifier()) }
    func liquidGlassHover() -> some View { modifier(LiquidGlassHoverModifier()) }

    @ViewBuilder
    func conditionalLiquidGlass(_ enabled: Bool) -> some View {
        if enabled { self.liquidGlassBase().liquidGlassEdge() } else { self }
    }
}
