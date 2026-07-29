// NovaLaunch/UI/Components/AdaptiveFolderTint.swift
import SwiftUI
import AppKit

/// 基于应用列表的自适应取色视图（用于 NovaLaunch 分组）
struct AdaptiveGroupTint: View {
    let items: [ApplicationItem]
    @State private var tintColor: Color = Color.gray.opacity(0.15)

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(
                colors: [tintColor, Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .task(id: items.map(\.id)) {
                tintColor = await IconColorSampler.sampleTint(for: items)
            }
            .animation(.easeInOut(duration: 0.6), value: tintColor)
    }
}

enum IconColorSampler {
    static func sampleTint(for folderURL: URL) async -> Color {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
                return Color.gray.opacity(0.15)
            }
            let appURLs = contents.filter { $0.pathExtension == "app" }.prefix(4)
            guard !appURLs.isEmpty else { return Color.gray.opacity(0.15) }

            var dominantColors: [NSColor] = []
            for appURL in appURLs {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                if let color = extractDominantColor(from: icon) {
                    dominantColors.append(color)
                }
            }
            guard !dominantColors.isEmpty else { return Color.gray.opacity(0.15) }

            let avgColor = averageColor(dominantColors)
            return lowSaturationTint(from: avgColor)
        }.value
    }

    /// 从 ApplicationItem 列表中采样主色调
    static func sampleTint(for items: [ApplicationItem]) async -> Color {
        await Task.detached(priority: .userInitiated) {
            guard !items.isEmpty else { return Color.gray.opacity(0.15) }

            // 取前 4 个应用的图标进行采样
            let sampleItems = items.prefix(4)
            var dominantColors: [NSColor] = []

            for item in sampleItems {
                // 关键修复（v65）：loadIcon 是 @MainActor，背景线程需要 hop 过去
                let icon = await MainActor.run { item.loadIcon() }
                if let color = extractDominantColor(from: icon) {
                    dominantColors.append(color)
                }
            }

            guard !dominantColors.isEmpty else { return Color.gray.opacity(0.15) }
            let avgColor = averageColor(dominantColors)
            return lowSaturationTint(from: avgColor)
        }.value
    }

    private static func extractDominantColor(from icon: NSImage) -> NSColor? {
        guard let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        let size = NSSize(width: 32, height: 32)
        let small = NSImage(size: size)
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(origin: .zero, size: size))
        small.unlockFocus()

        guard let smallTiff = small.tiffRepresentation,
              let smallBitmap = NSBitmapImageRep(data: smallTiff) else { return nil }

        // k-means 简化：直接采样 5x5 像素网格，找最饱和的
        var samples: [NSColor] = []
        for x in stride(from: 0, to: 32, by: 8) {
            for y in stride(from: 0, to: 32, by: 8) {
                if let color = smallBitmap.colorAt(x: x, y: y) {
                    samples.append(color)
                }
            }
        }

        return samples.max { lhs, rhs in
            saturation(of: lhs) < saturation(of: rhs)
        }
    }

    private static func averageColor(_ colors: [NSColor]) -> NSColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for color in colors {
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
        }
        let count = CGFloat(colors.count)
        return NSColor(red: r / count, green: g / count, blue: b / count, alpha: 1.0)
    }

    private static func saturation(of color: NSColor) -> CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return s
    }

    private static func lowSaturationTint(from color: NSColor) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let srgbColor = color.usingColorSpace(.sRGB)
        srgbColor?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard srgbColor != nil else {
            return Color.gray.opacity(0.15)
        }
        let hue = h
        let saturation = max(s * 0.3, 0.05)  // 低饱和度，最小 0.05
        let brightness: CGFloat = 0.85
        let alpha: CGFloat = 0.18
        let nsColor = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        return Color(nsColor: nsColor)
    }
}
