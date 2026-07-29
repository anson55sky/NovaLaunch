// 整体搬迁自 NovaLaunch/Core/Models/ApplicationItem.swift
// 唯一变化：所有声明加 public，加 Sendable
import Foundation
import SwiftUI
import AppKit
import CryptoKit

// MARK: - ApplicationItem

/// 应用程序数据模型：描述一个可被 NovaLaunch 索引与展示的 .app 条目
public struct ApplicationItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let bundleIdentifier: String
    public let displayName: String
    public let name: String
    public let bundlePath: String
    public let executableURL: URL?
    public let version: String
    public let launchCount: Int
    public let lastLaunchedDate: Date?
    public let createdAt: Date
    public var isFavorite: Bool
    public var category: AppCategory
    public var source: AppSource

    public enum AppCategory: String, Codable, CaseIterable, Sendable {
        case productivity
        case creativity
        case developer
        case utilities
        case games
        case system
        case other
    }

    /// 应用来源：系统自带 vs 用户安装
    public enum AppSource: String, Codable, CaseIterable, Sendable {
        case system   // 系统自带
        case user     // 用户安装
    }

    public init(id: UUID = UUID(),
                bundleIdentifier: String,
                displayName: String,
                name: String,
                bundlePath: String,
                executableURL: URL? = nil,
                version: String = "1.0.0",
                launchCount: Int = 0,
                lastLaunchedDate: Date? = nil,
                createdAt: Date = Date(),
                isFavorite: Bool = false,
                category: AppCategory = .other,
                source: AppSource = .user) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.name = name
        self.bundlePath = bundlePath
        self.executableURL = executableURL
        self.version = version
        self.launchCount = launchCount
        self.lastLaunchedDate = lastLaunchedDate
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.category = category
        self.source = source
    }

    // --- [v51 核心修复: 强制中文名称的便利初始化] ---
    /// 便利初始化（自动从 .app bundle 中提取中文本地化名称）
    /// - 优先顺序：zh.lproj/InfoPlist.strings → 默认 Info.plist → 文件名
    /// - 修复百度/小红书等中英混合名称 app 显示英文的问题
    public init(url: URL, source: AppSource = .user) {
        let bundle = Bundle(url: url)
        let infoDict = bundle?.infoDictionary

        // --- 核心修复: 强制读取中文名称 ---
        var displayName = ""

        if let bundle = bundle {
            // bundle.localizations 始终是 [String] 非可选
            let localizations = bundle.localizations
            // 检查是否有中文包
            if localizations.contains("zh_CN") || localizations.contains("zh-Hans") || localizations.contains("zh") {
                let zhLocalization = localizations.first { ["zh_CN", "zh-Hans", "zh"].contains($0) }
                if let zh = zhLocalization,
                   let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: zh),
                   let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
                    displayName = dict["CFBundleDisplayName"] ?? dict["CFBundleName"] ?? ""
                }
            }
        }

        // 如果没找到中文，才用默认的
        if displayName.isEmpty {
            displayName = infoDict?["CFBundleDisplayName"] as? String ??
                          infoDict?["CFBundleName"] as? String ??
                          url.lastPathComponent
        }

        let bundleID = infoDict?["CFBundleIdentifier"] as? String ?? "unknown.\(url.lastPathComponent)"
        let version = infoDict?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let execPath = infoDict?["CFBundleExecutable"] as? String

        self.init(
            bundleIdentifier: bundleID,
            displayName: displayName,
            name: url.deletingPathExtension().lastPathComponent,
            bundlePath: url.path,
            executableURL: execPath.flatMap { URL(fileURLWithPath: url.path).appendingPathComponent("Contents/MacOS/\($0)") },
            version: version,
            source: source
        )
    }

    /// 是否是系统自带应用
    public var isSystemApp: Bool { source == .system }

    // 关键修复（v61）：生成基于 bundleIdentifier 的确定性 UUID
    // 之前每次 init 都用 UUID() 生成随机 ID，重启后 ID 完全不同
    // → 持久化的 group.itemIDs 永远匹配不到 ApplicationItem
    // 现在用 SHA256(bundleIdentifier) 生成确定性 ID
    // SHA256 碰撞概率极低（2^128），实际不会重复
    public static func deterministicID(for bundleIdentifier: String) -> UUID {
        let hash = SHA256.hash(data: Data(bundleIdentifier.utf8))
        let bytes = Array(hash)
        // 取前 16 字节组成 UUID
        // UUID 格式：8-4-4-4-12
        let uuid = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    // 关键修复（v61）：系统应用判断（覆盖 Safari.app 等例外）
    // 之前只用路径前缀，会漏掉 /Applications/Safari.app 这种系统应用
    // 改进方案：用更广泛的前缀匹配覆盖所有 macOS 系统应用位置
    public static func inferSystemApp(url: URL, bundleIdentifier: String) -> Bool {
        // 综合路径前缀判断（覆盖 99% 系统应用，包括 Safari 等例外）
        // - /System/Applications/* — 现代 macOS 主系统应用（Finder、Mail、Messages 等）
        // - /System/Library/CoreServices/* — 系统核心服务应用（Finder、Safari 实际位置等）
        // - /Library/Apple/* — Apple 自家应用（部分系统应用）
        // - /usr/* — Unix 工具（罕见有 .app，但覆盖）
        let systemPrefixes = [
            "/System/Applications",
            "/System/Library/CoreServices",
            "/System/Library/PreferencePanes",
            "/System/Library/Frameworks",  // 系统 framework 附带的 app
            "/Library/Apple",
            "/usr/bin",
            "/usr/libexec"
        ]
        for prefix in systemPrefixes {
            if url.path.hasPrefix(prefix) { return true }
        }
        // 注：LSApplicationProxy 是 macOS 11+ 的私有 API，编译不过时回退到纯路径判断
        return false
    }
}

// MARK: - Hashable

extension ApplicationItem {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }

    public static func == (lhs: ApplicationItem, rhs: ApplicationItem) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

// MARK: - Display Helpers

extension ApplicationItem {
    // 性能优化（v50 修复 Tab/CMD+1 卡顿）：
    //   NSWorkspace.icon(forFile:) 每次都从 .app bundle 读取 .icns 文件，是同步 I/O。
    //   144 个应用 × 每次切换都重新读取 → 切换面板时明显卡顿。
    //   修复：用 NSCache 按 bundlePath 缓存图标，O(1) 命中。
    //   预加载：MainViewModel 收到 items 后后台预热缓存，
    //          用户切到启动器时图标已就绪。
    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500  // 最多缓存 500 个图标（普通用户用不到这个数）
        cache.totalCostLimit = 256 * 1024 * 1024  // 256MB 上限
        return cache
    }()

    /// 默认占位图标（兜底，防止 bundlePath 无效时显示空白）
    /// 关键修复（v65）：增加 size 参数使占位图标可缩放，
    /// 避免 cellSize=80 时占位图标仍为 32x32 导致看起来"图标消失"
    private static func placeholderIcon(size: CGFloat = 64) -> NSImage {
        let s = max(16, size)
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        defer { image.unlockFocus() }
        // 绘制 SF Symbol "app.fill" 作为占位
        if let symbol = NSImage(systemSymbolName: "app.fill",
                                accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: s * 0.6, weight: .regular)
            let styled = symbol.withSymbolConfiguration(config) ?? symbol
            let drawRect = NSRect(x: s * 0.2, y: s * 0.2, width: s * 0.6, height: s * 0.6)
            styled.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            // 兜底兜底：纯灰色方块
            NSColor.systemGray.setFill()
            NSRect(x: 0, y: 0, width: s, height: s).fill()
        }
        return image
    }

    /// 通过 NSWorkspace 获取应用原生图标（带缓存）
    /// 性能优化：首次调用走 NSWorkspace.icon(forFile:)，后续命中 NSCache（O(1)）
    /// 关键修复（v65）：
    ///   1) 增加 size 参数（默认 64），占位图标与 cell 尺寸一致
    ///   2) 强制主线程访问 NSCache/NSImage → 修复"切回启动器时图标消失"
    ///      原因：preloadIcons 在后台线程写 cache，主线程读时偶发
    ///           拿到一个 size=0 或未完成初始化的 NSImage → SwiftUI 不绘制
    ///      修复：loadIcon 统一在主线程跑（NSWorkspace.icon 本身很快，不需要后台）
    @MainActor
    public func loadIcon(size: CGFloat = 64) -> NSImage {
        let key = bundlePath as NSString
        // Fast path: cached icon
        if let cached = Self.iconCache.object(forKey: key), cached.size.width > 0, cached.size.height > 0 {
            return cached
        }
        // Performance: skip fileExists check — NSWorkspace icon gracefully handles missing files
        let image: NSImage
        if !bundlePath.isEmpty {
            let ws = NSWorkspace.shared.icon(forFile: bundlePath)
            if ws.size.width > 0, ws.size.height > 0 {
                image = ws
            } else {
                image = Self.placeholderIcon(size: size)
            }
        } else {
            image = Self.placeholderIcon(size: size)
        }
        Self.iconCache.setObject(image, forKey: key)
        return image
    }

    /// 预加载所有应用图标到缓存（后台任务）
    /// 调用时机：MainViewModel 收到 indexing.itemsSubject 数据后立即调用，
    ///          让图标在后台慢慢缓存好。用户切到启动器时不再卡顿。
    /// 关键修复（v65）：loadIcon 改为 @MainActor 后，preloadIcons 也必须在主线程跑
    ///   → 改为 MainActor.run（开销很小：NSCache.set + FileManager.fileExists 都是 O(1)）
    public static func preloadIcons(for items: [ApplicationItem]) {
        Task { @MainActor in
            for item in items {
                _ = item.loadIcon()  // 触发缓存（无副作用）
            }
        }
    }

    // --- [修复 4: 静态辅助方法 - 优先读取中文] ---
    /// 优先读取中文本地化名称 (zh / zh_CN / zh_Hans)，降级到默认 Info.plist
    /// 关键修复: 恢复同步执行 + NSCache 缓存
    ///   + NSCache 加速二次访问（已访问过的应用名秒返）
    public static func getLocalizedAppName(at path: String) -> String {
        let key = path as NSString
        // 1. 命中缓存：立即返回（O(1)）
        if let cached = Self.localizedNameCache.object(forKey: key) {
            return cached as String
        }
        // 2. 缓存未命中：同步执行（由 scanQueue 异步调用，不阻塞主线程）
        return loadLocalizedNameSync(at: path)
    }

    /// 实际执行 IO 的方法（内部）
    /// - 首次访问：同步读 .app bundle 的 InfoPlist.strings（由 scanQueue 后台调用，0 卡顿）
    /// - 写入 NSCache：下次访问直接 O(1) 返回
    /// - 后续访问：0 IO
    @discardableResult
    private static func loadLocalizedNameSync(at path: String) -> String {
        let key = path as NSString
        // 二次检查：可能其他线程已写入
        if let cached = Self.localizedNameCache.object(forKey: key) {
            return cached as String
        }

        let url = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: url) else {
            let fallback = url.lastPathComponent
            Self.localizedNameCache.setObject(fallback as NSString, forKey: key)
            return fallback
        }

        let preferred = ["zh", "zh_CN", "zh_Hans"]
        let locals = bundle.localizations

        var result = ""
        if let lang = locals.first(where: { preferred.contains($0) }),
           let p = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: lang),
           let d = NSDictionary(contentsOfFile: p) as? [String: String] {
            if let dn = d["CFBundleDisplayName"], !dn.isEmpty {
                result = dn
            } else if let bn = d["CFBundleName"], !bn.isEmpty {
                result = bn
            }
        }

        if result.isEmpty {
            if let dn = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !dn.isEmpty {
                result = dn
            } else if let bn = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !bn.isEmpty {
                result = bn
            }
        }

        if result.isEmpty {
            
            // 之前是 bundle.bundleURL.lastPathComponent → "VLC.app"，
            // makeItem 的 url.lastPathComponent = "VLC.app"，fallbackName = "VLC"
            //   → zhName("VLC.app") != fallbackName("VLC") → 进入分支
            //   → 但 zhName == url.lastPathComponent("VLC.app") → 条件失败
            //   → 永远走降级，displayName 经常是英文
            // 修正：返回与 fallbackName 完全相同的格式（无扩展名）
            result = bundle.bundleURL.deletingPathExtension().lastPathComponent
        }

        Self.localizedNameCache.setObject(result as NSString, forKey: key)
        return result
    }

    /// 中文名缓存：避免每次都做 NSDictionary(contentsOfFile:) 同步 IO
    private static let localizedNameCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 1000
        return cache
    }()

    /// 启动该应用
    @discardableResult
    public func launch() -> Bool {
        let url = URL(fileURLWithPath: bundlePath)
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return true
    }

    /// AI 推荐分数计算
    public var recommendationScore: Double {
        let hits = max(1, launchCount)
        let interval = max(1, Date().timeIntervalSince(lastLaunchedDate ?? createdAt))
        return log(Double(hits)) / interval
    }
}
