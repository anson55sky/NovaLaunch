import SwiftUI
import AppKit

// MARK: - 液态玻璃背景（v41 升级：极致通透 + 三层叠加）
//
// 设计目标：
//   - 底层：NSVisualEffectView（hudWindow material，behindWindow blendingMode）
//           → 让 macOS 桌面内容透出，真正做到"极致通透"
//   - 中层：CIFilter 钩子（高斯模糊 + 折射 + 色调）
//           → 当前实现保留 API 表面，具体渲染由 v40 的内层 Rectangle + 渐变承担
//   - 顶层：Metal 着色器（动态光斑、噪点）
//           → 后续 Task 12 集成，本任务先不实现
//
// 关键技术点：
//   - NSVisualEffectView + blendingMode(.behindWindow) 是 v41 极致通透关键
//   - 顶层 tint 用 .blendMode(.softLight) 让色温更自然（不是直接覆盖）
//   - isEmphasized = true 在 hudWindow material 下提供更强的玻璃效果
//   - 所有 API 均在 macOS 14 范围内，零降级

public struct LiquidGlassBackground: NSViewRepresentable {

    // MARK: - 参数

    public var material: Material
    public var blurRadius: Double
    public var refractionStrength: Double
    public var tintColor: Color
    public var tintOpacity: Double
    public var enableMetal: Bool

    public init(
        material: Material = .hudWindow,
        blurRadius: Double = 30,
        refractionStrength: Double = 0.4,
        tintColor: Color = .blue,
        tintOpacity: Double = 0.15,
        enableMetal: Bool = true
    ) {
        self.material = material
        self.blurRadius = blurRadius
        self.refractionStrength = refractionStrength
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.enableMetal = enableMetal
    }

    // MARK: - 材质映射

    public enum Material {
        case hudWindow
        case popover
        case menu
        case sidebar
        case contentBackground

        fileprivate var nsMaterial: NSVisualEffectView.Material {
            switch self {
            case .hudWindow: return .hudWindow
            case .popover: return .popover
            case .menu: return .menu
            case .sidebar: return .sidebar
            case .contentBackground: return .contentBackground
            }
        }
    }

    // MARK: - NSViewRepresentable

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        let intensity = CGFloat(min(1.0, max(0.0, blurRadius / 100.0)))

        // Performance: isEmphasized=false to skip extra blur pass; cap at hudWindow
        switch intensity {
        case 0..<0.3:
            nsView.material = .contentBackground
            nsView.isEmphasized = false
            nsView.state = .followsWindowActiveState
        case 0.3..<0.6:
            nsView.material = .popover
            nsView.isEmphasized = false
            nsView.state = .active
        case 0.6..<0.85:
            nsView.material = .hudWindow
            nsView.isEmphasized = false
            nsView.state = .active
        default:
            nsView.material = .hudWindow           // perf: never use underWindowBackground
            nsView.isEmphasized = false
            nsView.state = .active
        }

        // tint — lighter weight
        let nsColor = NSColor(tintColor).usingColorSpace(.deviceRGB) ?? NSColor.controlBackgroundColor
        nsView.layer?.backgroundColor = nsColor.withAlphaComponent(0.02 + intensity * 0.08).cgColor
    }
}

// MARK: - SwiftUI 修饰器

/// 液态玻璃背景修饰器：
///   - 底层：LiquidGlassBackground（NSVisualEffectView 极致通透玻璃）
///   - 顶层：tintColor 用 .blendMode(.softLight) 做色温微调（不直接覆盖）
public struct LiquidGlassModifier: ViewModifier {
    public var material: LiquidGlassBackground.Material
    public var tintColor: Color
    public var tintOpacity: Double
    public var blurRadius: Double  

    public init(
        material: LiquidGlassBackground.Material = .hudWindow,
        tintColor: Color = .blue,
        tintOpacity: Double = 0.15,
        blurRadius: Double = 30
    ) {
        self.material = material
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.blurRadius = blurRadius
    }

    public func body(content: Content) -> some View {
        let intensity = min(1.0, max(0.0, blurRadius / 100.0))
        let overlayOpacity = tintOpacity * (0.3 + 1.7 * intensity)
        return content
            .background(LiquidGlassBackground(
                material: material,
                blurRadius: blurRadius,
                tintColor: tintColor,
                tintOpacity: tintOpacity
            ))
            .overlay(
                
                // 让用户拖动 slider 时能明显看到颜色深度变化
                tintColor.opacity(overlayOpacity)
                    .blendMode(.softLight)
                    .allowsHitTesting(false)
            )
    }
}

public extension View {
    func liquidGlass(
        material: LiquidGlassBackground.Material = .hudWindow,
        tintColor: Color = .blue,
        tintOpacity: Double = 0.15,
        blurRadius: Double = 30
    ) -> some View {
        modifier(LiquidGlassModifier(
            material: material,
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            blurRadius: blurRadius
        ))
    }
}

// MARK: - View 扩展（便捷调用）

public extension View {
    /// 应用液态玻璃背景（v41 升级）
    /// - Parameters:
    ///   - material: NSVisualEffectView 材质（默认 .hudWindow）
    ///   - tintColor: 顶层色调（默认 .blue）
    ///   - tintOpacity: 色调不透明度（默认 0.15，softLight 混合模式下视觉更自然）
    /// - Returns: 带液态玻璃背景的视图
    func liquidGlass(
        material: LiquidGlassBackground.Material = .hudWindow,
        tintColor: Color = .blue,
        tintOpacity: Double = 0.15
    ) -> some View {
        modifier(LiquidGlassModifier(
            material: material,
            tintColor: tintColor,
            tintOpacity: tintOpacity
        ))
    }
}
