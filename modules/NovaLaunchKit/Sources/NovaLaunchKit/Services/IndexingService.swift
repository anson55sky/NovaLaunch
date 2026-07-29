// 整体搬迁自 NovaLaunch/Core/Services/IndexingService.swift
// 唯一变化：所有声明加 public，加 Sendable
import Foundation
import AppKit
import Combine
import CoreServices

// MARK: - IndexingStatus

public enum IndexingStatus: Equatable, Sendable {
    case idle
    case scanning(progress: Double, currentPath: String)
    case completed(count: Int)
    case failed(error: String)
}

// MARK: - IndexingService

/// 应用扫描与索引服务
/// 职责：遍历 /Applications 及用户目录，发现所有 .app 包并转换为 ApplicationItem。
/// 设计原则：
///  - 使用 Combine 的 CurrentValueSubject 广播状态流，供 ViewModel 订阅。
///  - 扫描工作位于后台 OperationQueue，避免阻塞主线程。
///  - 结果通过 NSMetadataQuery / FileManager 双重校验，保证完整性。
public final class IndexingService: @unchecked Sendable {

    // MARK: Singleton

    public static let shared = IndexingService()
    private init() {}

    // MARK: Output Subjects

    public let statusSubject = CurrentValueSubject<IndexingStatus, Never>(.idle)
    public let itemsSubject = CurrentValueSubject<[ApplicationItem], Never>([])

    // MARK: Private State

    private let scanQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.novalaunch.indexing"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var cancellables = Set<AnyCancellable>()

    // MARK: Public API

    /// 启动一次全量扫描。若已有扫描在进行中，则跳过并保持当前状态。
    public func startFullScan() {
        scanQueue.cancelAllOperations()
        statusSubject.send(.idle)
        statusSubject.send(.scanning(progress: 0, currentPath: "/Applications"))

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            let items = self.performScan()
            DispatchQueue.main.async {
                self.itemsSubject.send(items)
                self.statusSubject.send(.completed(count: items.count))
            }
        }
        operation.queuePriority = .high
        scanQueue.addOperation(operation)
    }

    /// 增量扫描：仅当已有结果时使用，比全量扫描更快
    /// 适合文件监听器触发的轻量级刷新
    public func startIncrementalScan() {
        // 只在空闲时启动增量扫描，避免与全量扫描冲突
        if case .scanning = statusSubject.value { return }

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            let items = self.performScan()
            DispatchQueue.main.async {
                // 检查是否有变化
                let oldItems = self.itemsSubject.value
                let oldBundleIDs = Set(oldItems.map { $0.bundleIdentifier })
                let newBundleIDs = Set(items.map { $0.bundleIdentifier })

                if oldBundleIDs != newBundleIDs || oldItems.count != items.count {
                    self.itemsSubject.send(items)
                    print("NovaLaunch: 检测到应用变化，已更新 (\(items.count) 个应用)")
                }
            }
        }
        operation.queuePriority = .normal
        scanQueue.addOperation(operation)
    }

    /// 强制重置到 idle 状态（用于重置扫描队列）
    public func reset() {
        scanQueue.cancelAllOperations()
        statusSubject.send(.idle)
    }

    /// 增量刷新：接收单个 URL，转换为 ApplicationItem 并合并到结果中。
    public func refreshItem(at url: URL) -> ApplicationItem? {
        guard let item = Self.makeItem(from: url) else { return nil }
        var current = itemsSubject.value
        if let index = current.firstIndex(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
            current[index] = item
        } else {
            current.append(item)
        }
        itemsSubject.send(current)
        return item
    }

    // MARK: Scan Implementation

    private func performScan() -> [ApplicationItem] {
        let searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
            NSSearchPathForDirectoriesInDomains(.applicationDirectory,
                                                .userDomainMask,
                                                true).first ?? ""
        ].filter { !$0.isEmpty }

        var collected: [URL] = []
        let manager = FileManager.default

        for base in searchPaths {
            autoreleasepool {
                let baseURL = URL(fileURLWithPath: base)
                guard let enumerator = manager.enumerator(at: baseURL,
                                                          includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                          errorHandler: nil) else { return }

                for case let url as URL in enumerator {
                    // 进度上报
                    let progress = min(1.0, Double(collected.count) / 300.0)
                    DispatchQueue.main.async { [weak self] in
                        self?.statusSubject.send(.scanning(progress: progress,
                                                           currentPath: base))
                    }
                    if url.pathExtension.lowercased() == "app" {
                        collected.append(url)
                        enumerator.skipDescendants()
                    }
                }
            }
        }

        // 去重 & 构建 ApplicationItem
        var seen: Set<String> = []
        var items: [ApplicationItem] = []
        for url in collected {
            autoreleasepool {
                guard let item = Self.makeItem(from: url) else { return }
                guard !seen.contains(item.bundleIdentifier) else { return }
                seen.insert(item.bundleIdentifier)
                items.append(item)
            }
        }
        return items
    }

    // MARK: Builder

    private static func makeItem(from url: URL) -> ApplicationItem? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]

        let bundleIdentifier = (info[kCFBundleIdentifierKey as String] as? String)
            ?? "unknown.\(url.lastPathComponent)"

        // 多源获取应用显示名（关键：确保与系统 Finder 完全一致）
        // 优先级顺序：用户自定义 > LS显示名 > Bundle本地化 > 文件名
        let displayName: String = {
            // 1. 优先使用 LaunchServices 提供的本地化显示名（与 Finder 完全一致）
            if let lsName = Self.lsDisplayName(for: url), !lsName.isEmpty {
                return Self.cleanDisplayName(lsName)
            }
            // 2. 优先使用系统的本地化显示名
            if let localized = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
               !localized.isEmpty {
                return Self.cleanDisplayName(localized)
            }
            if let localizedName = bundle?.localizedInfoDictionary?["CFBundleName"] as? String,
               !localizedName.isEmpty {
                return Self.cleanDisplayName(localizedName)
            }
            // 3. 使用 bundle 的 localizedString for key
            if let key = bundle?.localizedString(forKey: "CFBundleDisplayName", value: nil, table: nil) as String?,
               !key.isEmpty, key != "CFBundleDisplayName" {
                return Self.cleanDisplayName(key)
            }
            // 4. 使用 Info.plist 中的 CFBundleDisplayName
            if let display = info["CFBundleDisplayName"] as? String, !display.isEmpty {
                return Self.cleanDisplayName(display)
            }
            // 5. 使用 CFBundleName
            if let name = info[kCFBundleNameKey as String] as? String, !name.isEmpty {
                return Self.cleanDisplayName(name)
            }
            // 6. 使用文件名（去掉 .app）
            return url.deletingPathExtension().lastPathComponent
        }()

        // 应用来源：判断系统自带还是用户安装
        let source: ApplicationItem.AppSource = {
            if url.path.hasPrefix("/System/Applications") || url.path.hasPrefix("/System/Library/CoreServices/Applications") {
                return .system
            }
            return .user
        }()

        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info[kCFBundleVersionKey as String] as? String)
            ?? "1.0.0"

        return ApplicationItem(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            name: url.deletingPathExtension().lastPathComponent,
            bundlePath: url.path,
            executableURL: bundle?.executableURL,
            version: version,
            category: Self.inferCategory(from: info),
            source: source
        )
    }

    private static func inferCategory(from info: [String: Any]) -> ApplicationItem.AppCategory {
        let category = info["LSApplicationCategoryType"] as? String ?? ""
        switch category {
        case let c where c.contains("productivity"): return .productivity
        case let c where c.contains("graphics") || c.contains("video"): return .creativity
        case let c where c.contains("developer"): return .developer
        case let c where c.contains("utilities"): return .utilities
        case let c where c.contains("games"): return .games
        default: return .other
        }
    }

    /// 使用 LaunchServices 获取与 Finder 完全一致的应用显示名
    private static func lsDisplayName(for url: URL) -> String? {
        let urlRef = url as CFURL
        var displayNameRef: Unmanaged<CFString>?
        let status = LSCopyDisplayNameForURL(urlRef, &displayNameRef)

        if status == noErr, let unmanaged = displayNameRef {
            let displayName = unmanaged.takeRetainedValue() as String
            if !displayName.isEmpty {
                return displayName
            }
        }

        // 兜底：尝试从 .localized 子目录读取
        let localizedSubdirs = [
            "zh-Hans.lproj", "zh_CN.lproj", "zh-CN.lproj", "zh.lproj",
            "en.lproj", "Base.lproj"
        ]
        for subdir in localizedSubdirs {
            let infoPlistStringsURL = url.appendingPathComponent("Contents/Resources/\(subdir)/InfoPlist.strings")
            if FileManager.default.fileExists(atPath: infoPlistStringsURL.path) {
                if let dict = NSDictionary(contentsOf: infoPlistStringsURL) as? [String: Any] {
                    if let display = dict["CFBundleDisplayName"] as? String, !display.isEmpty {
                        return display
                    }
                    if let name = dict["CFBundleName"] as? String, !name.isEmpty {
                        return name
                    }
                }
            }
        }

        return nil
    }

    /// 清理显示名（去掉 .app 后缀，去除多余空白）
    private static func cleanDisplayName(_ name: String) -> String {
        var cleaned = name
        if cleaned.hasSuffix(".app") {
            cleaned = String(cleaned.dropLast(4))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
