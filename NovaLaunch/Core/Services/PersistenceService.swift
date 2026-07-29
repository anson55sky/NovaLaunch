import Foundation
import Combine

/// 数据持久化服务（Phase 1: UserDefaults | Phase 2+: Core Data）
/// 严格遵守合规要求：全使用 Apple 原生 API，无 GPL/AGPL 依赖。
final class PersistenceService {
    static let shared = PersistenceService()

    private let defaults = UserDefaults.standard
    private let groupsKey = "com.novalaunch.groups"
    private let analyticsKey = "com.novalaunch.analytics"
    private let prefsKey = "com.novalaunch.preferences"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Groups

    func saveGroups(_ groups: [AppGroup]) {
        do {
            let data = try encoder.encode(groups)
            defaults.set(data, forKey: groupsKey)
        } catch {
            NovaLog.write("Persistence", "Failed to save groups: \(error)")
        }
    }

    func loadGroups() -> [AppGroup] {
        guard let data = defaults.data(forKey: groupsKey) else { return [] }
        do {
            return try decoder.decode([AppGroup].self, from: data)
        } catch {
            NovaLog.write("Persistence", "Failed to load groups: \(error)")
            return []
        }
    }

    // MARK: - Analytics

    func saveAnalytics(_ analytics: [String: LaunchRecord]) {
        do {
            let data = try encoder.encode(analytics)
            defaults.set(data, forKey: analyticsKey)
        } catch {
            NovaLog.write("Persistence", "Failed to save analytics: \(error)")
        }
    }

    func loadAnalytics() -> [String: LaunchRecord] {
        guard let data = defaults.data(forKey: analyticsKey) else { return [:] }
        do {
            return try decoder.decode([String: LaunchRecord].self, from: data)
        } catch {
            return [:]
        }
    }

    // MARK: - User Preferences

    func savePreferences(_ prefs: SerializablePreferences) {
        do {
            let data = try encoder.encode(prefs)
            defaults.set(data, forKey: prefsKey)
        } catch {
            NovaLog.write("Persistence", "Failed to save preferences: \(error)")
        }
    }

    func loadPreferences() -> SerializablePreferences {
        guard let data = defaults.data(forKey: prefsKey) else {
            return SerializablePreferences()
        }
        do {
            return try decoder.decode(SerializablePreferences.self, from: data)
        } catch {
            return SerializablePreferences()
        }
    }

    // MARK: - Items (Phase 2 — 完整扫描结果缓存)

    func saveItems(_ items: [ApplicationItem]) {
        do {
            let data = try encoder.encode(items)
            defaults.set(data, forKey: "com.novalaunch.items")
        } catch {
            NovaLog.write("Persistence", "Failed to save items: \(error)")
        }
    }

    func loadItems() -> [ApplicationItem] {
        guard let data = defaults.data(forKey: "com.novalaunch.items") else { return [] }
        do {
            return try decoder.decode([ApplicationItem].self, from: data)
        } catch {
            return []
        }
    }
}

// MARK: - LaunchRecord (使用统计)

struct LaunchRecord: Codable, Hashable {
    let bundleIdentifier: String
    var launchCount: Int
    var lastLaunchedDate: Date

    mutating func record() {
        launchCount += 1
        lastLaunchedDate = Date()
    }
}

// MARK: - SerializablePreferences

struct SerializablePreferences: Codable {
    var preferredIconSize: Double = 64
    var gridColumns: Int = 6
    var defaultHotKey: String = "Option+Space"
    var enableFuzzySearch: Bool = true
    var accentColorName: String = "AccentBlue"
    var reduceMotion: Bool = false
    var launchCountEnabled: Bool = true
    var lastRefreshDate: Date = Date()

    // Phase 2 扩展
    var themeMode: ThemeMode = .system
    var customAccentColor: String = "#007AFF"

    // Phase 3 扩展：多屏分页设置
    /// true = 多屏分页（带双指拨动），false = 滚动浏览
    var usePagingMode: Bool = true

    
    var hotkeyModifiers: UInt32 = 2048  // optionKey
    var hotkeyCode: UInt32 = 49  // Space

    
    var useFullscreenMode: Bool = false

    
    var enablePinchGesture: Bool = true

    
    var appLanguage: String = "zh-Hans"

    
    var enableF4Key: Bool = false

    
    var enableFourFingerSwipe: Bool = false

    // iOS 27 液态玻璃风格开关
    var isLiquidGlassEnabled: Bool = false

    var hotCornerTL: HotCornerAction = .none
    var hotCornerTR: HotCornerAction = .none
    var hotCornerBL: HotCornerAction = .none
    var hotCornerBR: HotCornerAction = .none

    enum ThemeMode: String, Codable, CaseIterable {
        case light, dark, system
    }
}

// MARK: - LayoutBackupData (v1.1: Export/Import)

struct LayoutBackupData: Codable {
    var groups: [AppGroup]
    var preferences: SerializablePreferences
    var analytics: [String: LaunchRecord]
    
    var version: String = "1.0.0"
    var exportDate: Date = Date()
}
