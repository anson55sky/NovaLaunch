import Foundation
import AppKit
import Carbon

final class UserPreferences: ObservableObject {
    @Published var preferredIconSize: CGFloat = 64
    @Published var gridColumns: Int = 6
    @Published var defaultHotKey: String = "Option+Space"
    @Published var enableFuzzySearch: Bool = true
    @Published var accentColorName: String = "AccentBlue"
    @Published var reduceMotion: Bool = false
    @Published var launchCountEnabled: Bool = true
    @Published var lastRefreshDate: Date = Date()

    // Phase 2 扩展
    @Published var blurIntensity: Double = 0.5
    @Published var themeMode: SerializablePreferences.ThemeMode = .system

    
    @Published var hotkeyModifiers: UInt32 = UInt32(optionKey)
    @Published var hotkeyCode: UInt32 = 49

    
    @Published var useFullscreenMode: Bool = false

    
    @Published var enablePinchGesture: Bool = true
    @Published var isLiquidGlassEnabled: Bool = false

    // Launchpad 图标大小
    @Published var launchpadIconSize: IconSize = .normal
    enum IconSize: String, CaseIterable {
        case small = "小"
        case normal = "中"
        case large = "大"
    }

    static let shared = UserPreferences()

    func load() {
        let saved = PersistenceService.shared.loadPreferences()
        preferredIconSize = saved.preferredIconSize
        gridColumns = saved.gridColumns
        enableFuzzySearch = saved.enableFuzzySearch
        themeMode = saved.themeMode
        
        hotkeyModifiers = saved.hotkeyModifiers
        hotkeyCode = saved.hotkeyCode
        
        useFullscreenMode = saved.useFullscreenMode
        
        enablePinchGesture = saved.enablePinchGesture
        isLiquidGlassEnabled = saved.isLiquidGlassEnabled
    }

    func save() {
        let prefs = SerializablePreferences(
            preferredIconSize: preferredIconSize,
            gridColumns: gridColumns,
            defaultHotKey: defaultHotKey,
            enableFuzzySearch: enableFuzzySearch,
            accentColorName: accentColorName,
            reduceMotion: reduceMotion,
            launchCountEnabled: launchCountEnabled,
            themeMode: themeMode,
            
            hotkeyModifiers: hotkeyModifiers,
            hotkeyCode: hotkeyCode,
            useFullscreenMode: useFullscreenMode,
            enablePinchGesture: enablePinchGesture,
            isLiquidGlassEnabled: isLiquidGlassEnabled
        )
        PersistenceService.shared.savePreferences(prefs)
        // 通知主界面立即更新
        NotificationCenter.default.post(name: .novaPreferencesChanged, object: nil)
    }

    /// 关键修复（v18）：静默保存（只写磁盘，不发通知）
    func saveSilently() {
        let prefs = SerializablePreferences(
            preferredIconSize: preferredIconSize,
            gridColumns: gridColumns,
            defaultHotKey: defaultHotKey,
            enableFuzzySearch: enableFuzzySearch,
            accentColorName: accentColorName,
            reduceMotion: reduceMotion,
            launchCountEnabled: launchCountEnabled,
            themeMode: themeMode,
            
            hotkeyModifiers: hotkeyModifiers,
            hotkeyCode: hotkeyCode,
            useFullscreenMode: useFullscreenMode,
            enablePinchGesture: enablePinchGesture
        )
        PersistenceService.shared.savePreferences(prefs)
        // 不发送 novaPreferencesChanged 通知
    }

    /// 直接应用外观设置（主题/强调色/毛玻璃）到主程序
    /// 关键：只修改主程序，不影响设置窗口和全局
    func applyAppearance(theme: SerializablePreferences.ThemeMode, accentHex: String, blur: Double) {
        // 1. 主题模式 → 发送到主程序
        let appearance: NSAppearance
        switch theme {
        case .system:
            appearance = NSAppearance(named: .aqua)!
        case .light:
            appearance = NSAppearance(named: .aqua)!
        case .dark:
            appearance = NSAppearance(named: .darkAqua)!
        }
        NotificationCenter.default.post(name: .novaLauncherAppearanceChanged, object: appearance)

        // 2. 强调色 → 发送到主程序
        NotificationCenter.default.post(
            name: .novaLauncherAccentColorChanged,
            object: nil,
            userInfo: ["hex": accentHex]
        )

        // 3. 毛玻璃强度 → 发送到主程序
        NotificationCenter.default.post(
            name: .novaLauncherBlurChanged,
            object: nil,
            userInfo: ["blur": blur]
        )

        // 保存到本地偏好
        themeMode = theme
        accentColorName = accentHex
        blurIntensity = blur
        save()
    }

    // MARK: - 自定义应用名称

    private let customNamesKey = "NovaLaunch.customAppNames"
    private var customNamesCache: [String: String] = [:]

    init() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        loadCustomNames()
    }

    private func loadCustomNames() {
        if let dict = UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String] {
            customNamesCache = dict
        }
    }

    /// 设置应用的自定义显示名称
    func setCustomName(for bundleId: String, name: String) {
        customNamesCache[bundleId] = name
        UserDefaults.standard.set(customNamesCache, forKey: customNamesKey)
    }

    /// 获取应用的自定义显示名称
    func customName(for bundleId: String) -> String? {
        return customNamesCache[bundleId]
    }
}
