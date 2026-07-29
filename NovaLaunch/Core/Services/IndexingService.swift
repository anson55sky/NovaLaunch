import Foundation
import AppKit
import Combine
import CoreServices

public enum IndexingStatus: Equatable, Sendable {
    case idle
    case scanning(progress: Double, currentPath: String)
    case completed(count: Int)
    case failed(error: String)
}

public final class IndexingService: @unchecked Sendable {

    public static let shared = IndexingService()
    private init() {}

    public let statusSubject = CurrentValueSubject<IndexingStatus, Never>(.idle)
    public let itemsSubject = CurrentValueSubject<[ApplicationItem], Never>([])

    private let scanQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.novalaunch.indexing"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var cancellables = Set<AnyCancellable>()

    public func startFullScan() {
        scanQueue.cancelAllOperations()
        statusSubject.send(.idle)
        statusSubject.send(.scanning(progress: 0, currentPath: "/Applications"))

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            let start = Date()
            let items = self.performScan()
            let elapsed = Date().timeIntervalSince(start)
            NovaLog.write("Indexing", "performScan done: \(items.count) items in \(String(format: "%.2f", elapsed))s")
            DispatchQueue.main.async {
                self.itemsSubject.send(items)
                self.statusSubject.send(.completed(count: items.count))
                PersistenceService.shared.saveItems(items)
            }
        }
        operation.queuePriority = .high
        scanQueue.addOperation(operation)
    }

    public func startIncrementalScan() {
        if case .scanning = statusSubject.value { return }

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            let items = self.performScan()
            DispatchQueue.main.async {
                let oldItems = self.itemsSubject.value
                let oldBundleIDs = Set(oldItems.map { $0.bundleIdentifier })
                let newBundleIDs = Set(items.map { $0.bundleIdentifier })

                if oldBundleIDs != newBundleIDs || oldItems.count != items.count {
                    self.itemsSubject.send(items)
                    NovaLog.write("Indexing", "检测到应用变化，已更新 (\(items.count) 个应用)")
                }
            }
        }
        operation.queuePriority = .normal
        scanQueue.addOperation(operation)
    }

    public func reset() {
        scanQueue.cancelAllOperations()
        statusSubject.send(.idle)
    }

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

    private static func makeItem(from url: URL) -> ApplicationItem? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]

        let bundleIdentifier = (info[kCFBundleIdentifierKey as String] as? String)
            ?? "unknown.\(url.lastPathComponent)"

        let displayName = Self.getLocalizedAppName(for: url)

        let source: ApplicationItem.AppSource = ApplicationItem.inferSystemApp(url: url, bundleIdentifier: bundleIdentifier) ? .system : .user

        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info[kCFBundleVersionKey as String] as? String)
            ?? "1.0.0"

        let deterministicID = ApplicationItem.deterministicID(for: bundleIdentifier)

        return ApplicationItem(
            id: deterministicID,
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

    private static func getLocalizedAppName(for url: URL) -> String {
        let urlRef = url as CFURL

        // Bug #1 Root Cause Fix:
        // LSCopyDisplayNameForURL is deprecated and DOES NOT return localized names
        // (e.g., "WeChat.app" instead of "微信.app") regardless of thread context.
        //
        // The correct approach is MDItemCopyAttribute(kMDItemDisplayName) which reads
        // from the Spotlight metadata index — the same source Finder uses.
        // Example: returns "微信.app" for WeChat, "计算器.app" for Calculator.
        if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, urlRef),
           let rawName = MDItemCopyAttribute(mdItem, kMDItemDisplayName) {
            let name = (rawName as? String) ?? ""
            if !name.isEmpty {
                return cleanDisplayName(name)
            }
        }

        // Fallback 1: Bundle localized Info.plist (may contain English defaults)
        if let bundle = Bundle(url: url) {
            if let localized = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
               !localized.isEmpty {
                return cleanDisplayName(localized)
            }
            if let localized = bundle.localizedInfoDictionary?["CFBundleName"] as? String,
               !localized.isEmpty {
                return cleanDisplayName(localized)
            }
        }

        // Fallback 2: FileManager displayName at path
        let sysName = FileManager.default.displayName(atPath: url.path)
        if !sysName.isEmpty {
            let stripped = sysName.hasSuffix(".app") ? String(sysName.dropLast(4)) : sysName
            return cleanDisplayName(stripped.isEmpty ? url.deletingPathExtension().lastPathComponent : stripped)
        }

        // Fallback 3: Extract from path
        return cleanDisplayName(url.deletingPathExtension().lastPathComponent)
    }

    private static func cleanDisplayName(_ name: String) -> String {
        var cleaned = name
        if cleaned.hasSuffix(".app") {
            cleaned = String(cleaned.dropLast(4))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
