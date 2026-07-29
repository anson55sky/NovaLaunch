import Foundation
import AppKit
import SwiftUI

/// 异步加载并缓存网站 favicon
/// - 数据源：Google S2 Favicon API（`https://www.google.com/s2/favicons?domain=host&sz=64`）
/// - 内存缓存：按 host 缓存 NSImage
/// - 失败兜底：返回 nil（UI 显示 globe SF Symbol）
@MainActor
final class FaviconLoader: ObservableObject {
    static let shared = FaviconLoader()

    /// host → NSImage
    private var cache: [String: NSImage] = [:]
    /// 正在请求的 host
    private var inFlight: Set<String> = []

    private init() {}

    /// 同步返回缓存（如有），否则返回 nil
    func cached(for host: String) -> NSImage? {
        cache[host]
    }

    /// 触发后台下载；下载完成后 @Published cache 触发 UI 刷新
    func load(for host: String) {
        let normalized = normalizeHost(host)
        guard !normalized.isEmpty,
              cache[normalized] == nil,
              !inFlight.contains(normalized) else { return }
        inFlight.insert(normalized)

        Task.detached(priority: .utility) { [weak self] in
            let image = await FaviconLoader.fetch(host: normalized)
            await MainActor.run {
                self?.inFlight.remove(normalized)
                if let image = image {
                    self?.cache[normalized] = image
                    self?.objectWillChange.send()
                }
            }
        }
    }

    /// 真正执行网络请求（在后台线程）
    nonisolated private static func fetch(host: String) async -> NSImage? {
        // 1) 先尝试站点根的 /favicon.ico
        let primaryURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
        if let img = await downloadImage(from: primaryURL) {
            return img
        }
        // 2) 兜底：直接拉 host/favicon.ico
        if let direct = URL(string: "https://\(host)/favicon.ico"),
           let img = await downloadImage(from: direct) {
            return img
        }
        return nil
    }

    nonisolated private static func downloadImage(from url: URL?) async -> NSImage? {
        guard let url = url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let image = NSImage(data: data),
              image.size.width > 1
        else { return nil }
        return image
    }

    private func normalizeHost(_ raw: String) -> String {
        guard !raw.isEmpty, raw != "其他" else { return "" }
        return raw
    }
}
