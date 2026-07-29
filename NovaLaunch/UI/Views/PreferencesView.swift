import SwiftUI
import AppKit
import Carbon

// MARK: - PreferencesView

struct PreferencesView: View {
    @StateObject private var prefs = PreferencesViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Light pink glass background — macOS Sequoia style
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.90, blue: 0.95).opacity(0.6),
                        Color(red: 1.00, green: 0.80, blue: 0.90).opacity(0.4),
                        Color(red: 0.95, green: 0.85, blue: 1.00).opacity(0.3),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blur(radius: 30)

                Rectangle()
                    .fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("NovaLaunch 设置")
                        .font(.headline)
                    Spacer()
                    Button("完成") {
                        prefs.save()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)

                Divider().opacity(0.3)

                TabView {
                    ScrollView(.vertical, showsIndicators: false) { generalTab }
                        .tabItem { Text("通用") }
                    ScrollView(.vertical, showsIndicators: false) { appearanceTab }
                        .tabItem { Text("界面") }
                    ScrollView(.vertical, showsIndicators: false) { searchTab }
                        .tabItem { Text("搜索") }
                    ScrollView(.vertical, showsIndicators: false) { hotkeyTab }
                        .tabItem { Text("热键") }
                    ScrollView(.vertical, showsIndicators: false) { backupTab }
                        .tabItem { Text("备份") }
                    aboutTab
                        .tabItem { Text("关于") }
                }
                .frame(minHeight: 500)
                .background(TabLabelCenterFix())
            }  // end VStack
        }  // end ZStack
        .frame(width: 640, height: 620)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("启动") {
                Toggle("开机自动启动", isOn: $prefs.launchAtLogin)
                Toggle("菜单栏常驻", isOn: $prefs.menuBarOnly)
            }
            
            Section("图标大小") {
                HStack {
                    Text("应用图标")
                    Slider(value: $prefs.iconSize, in: 32...96, step: 8) {
                        Text("\(Int(prefs.iconSize))pt")
                    } minimumValueLabel: {
                        Text("32")
                            .font(.caption2)
                    } maximumValueLabel: {
                        Text("96")
                            .font(.caption2)
                    }
                    .frame(width: 280)
                    .onChange(of: prefs.iconSize) { newValue in
                        // 实时同步到主程序
                        prefs.applyIconSize(newValue)
                    }
                    Text("\(Int(prefs.iconSize))pt")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40)
                }

                Stepper("网格列数：\(prefs.gridColumns) 列", value: $prefs.gridColumns, in: 3...12)
                    .onChange(of: prefs.gridColumns) { newValue in
                        prefs.applyGridColumns(newValue)
                    }
            }

            Section("减少动画") {
                Toggle("启用系统偏好设置", isOn: $prefs.reduceMotion)
                if !prefs.reduceMotion {
                    Text("在「系统设置 → 辅助功能 → 显示」中关闭")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section("主题模式") {
                HStack(spacing: 12) {
                    Text("外观")
                        .frame(width: 80, alignment: .leading)
                    Picker("外观", selection: $prefs.themeMode) {
                        Text("跟随系统").tag(SerializablePreferences.ThemeMode.system)
                        Text("浅色").tag(SerializablePreferences.ThemeMode.light)
                        Text("深色").tag(SerializablePreferences.ThemeMode.dark)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                    .labelsHidden()
                    .onChange(of: prefs.themeMode) { newValue in
                        applyAppearanceChange(theme: newValue, accent: prefs.selectedAccentColor.hex, blur: prefs.blurIntensity)
                    }
                }
            }

            Section("强调色") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                    ForEach(prefs.accentColors, id: \.name) { color in
                        accentColorButton(color)
                    }
                }
                .frame(height: 60)
            }

            Section("毛玻璃强度") {
                Slider(value: $prefs.blurIntensity, in: 0...1) {
                    Text("")
                }
                .onChange(of: prefs.blurIntensity) { newValue in
                    applyAppearanceChange(theme: prefs.themeMode, accent: prefs.selectedAccentColor.hex, blur: newValue)
                }
                HStack {
                    Text("清晰")
                        .font(.caption2)
                    Spacer()
                    Text("模糊")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    resetAppearance()
                } label: {
                    Label("恢复默认外观", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func applyAppearanceChange(theme: SerializablePreferences.ThemeMode, accent: String, blur: Double) {
        // 关键修复（v18）：只应用外观设置，不触发 novaPreferencesChanged
        // 之前 applyAppearance() 内部会调用 save() → 发送 novaPreferencesChanged
        // → GroupDetailView 收到后调用 loadPagingSettings() → contentVersion++ → 重建页面
        // → 导致"滚动浏览模式自动变成分屏浏览"的 bug
        // 现在直接发外观通知，不走 save() 流程
        UserPreferences.shared.themeMode = theme
        UserPreferences.shared.accentColorName = accent
        UserPreferences.shared.blurIntensity = blur

        // 1. 主题模式
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

        // 2. 强调色
        NotificationCenter.default.post(
            name: .novaLauncherAccentColorChanged,
            object: nil,
            userInfo: ["hex": accent]
        )

        // 3. 毛玻璃强度
        NotificationCenter.default.post(
            name: .novaLauncherBlurChanged,
            object: nil,
            userInfo: ["blur": blur]
        )

        // 只保存到磁盘，不发 novaPreferencesChanged（避免触发分屏重建）
        UserPreferences.shared.saveSilently()
    }

    private func resetAppearance() {
        prefs.themeMode = .system
        prefs.selectedAccentColor = AccentColor.presets[0]
        prefs.blurIntensity = 0.5
        applyAppearanceChange(theme: .system, accent: AccentColor.presets[0].hex, blur: 0.5)
    }

    private func accentColorButton(_ color: AccentColor) -> some View {
        Button {
            prefs.selectedAccentColor = color
            applyAppearanceChange(theme: prefs.themeMode, accent: color.hex, blur: prefs.blurIntensity)
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .strokeBorder(.white, lineWidth: prefs.selectedAccentColor.name == color.name ? 3 : 0)
                )
                .shadow(color: prefs.selectedAccentColor.name == color.name ? .black.opacity(0.3) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
        .help(color.name)
    }

    // MARK: - Search

    private var searchTab: some View {
        Form {
            Section("搜索策略") {
                Toggle("精准包含匹配", isOn: $prefs.enableExactSearch)
                Toggle("前缀匹配", isOn: $prefs.enablePrefixSearch)
                Toggle("拼音首字母匹配（中文）", isOn: $prefs.enablePinyinSearch)
                Toggle("模糊容错（Levenshtein）", isOn: $prefs.enableFuzzySearch)
            }

            Section("模糊阈值") {
                Stepper("允许编辑距离：\(prefs.fuzzyThreshold)", value: $prefs.fuzzyThreshold, in: 1...5)
                Text("阈值越小匹配越严格，2 为默认推荐值")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Hotkey

    private var hotkeyTab: some View {
        Form {
            Section("全局热键") {
                HStack {
                    Text("唤醒启动台")
                    Spacer()
                    if prefs.isRecordingHotkey {
                        Text(prefs.recordingText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Button(action: { startHotkeyRecording() }) {
                            Text(prefs.hotkeyDisplay)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("点击热键区域，然后按下新的组合键")
                    .font(.caption)
                    .foregroundStyle(prefs.isRecordingHotkey ? .orange : .secondary)
            }

            Section("搜索热键") {
                Toggle("聚焦时直接搜索", isOn: $prefs.searchOnFocus)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if prefs.isRecordingHotkey {
                    recordHotkey(event)
                    return nil
                }
                return event
            }
        }
    }

    // MARK: - v35：热键录制辅助

    private func startHotkeyRecording() {
        prefs.isRecordingHotkey = true
        prefs.recordingText = "按下新组合键..."
    }

    private func recordHotkey(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let keyCode = UInt32(event.keyCode)

        // 至少需要一个修饰键（避免误录普通按键）
        guard !modifiers.isEmpty else {
            prefs.recordingText = "请包含至少一个修饰键（⌘⇧⌥^）"
            return
        }

        // 转换为 Carbon 掩码
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }

        // 保存新配置
        prefs.hotkeyModifiers = carbonModifiers
        prefs.hotkeyCode = keyCode
        let config = HotkeyConfig(modifiers: carbonModifiers, keyCode: keyCode)
        prefs.hotkeyDisplay = config.displayString

        // 结束录制
        prefs.isRecordingHotkey = false
    }

    // MARK: - Backup

    private var backupTab: some View {
        Form {
            Section("布局数据备份") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("导出布局数据")
                            .font(.body)
                        Text("将文件夹结构、应用排列、偏好设置等保存为文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        prefs.exportLayout()
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("导入布局数据")
                            .font(.body)
                        Text("从备份文件恢复布局，或从其他设备迁移")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        prefs.importLayout()
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Section("说明") {
                Text("导出文件包含：文件夹分组、应用排列顺序、偏好设置和搜索配置。不包含浏览器标签和剪贴板历史等隐私数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 4) {
                Text("NovaLaunch")
                    .font(.title.bold())
                Text("版本 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("新一代 macOS 智能启动台\nSwift 5.9 + SwiftUI 4.0 原生构建")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            Text("© 2026 NovaLaunch. 保留所有权利。\n严格遵守 MIT / Apache 2.0 开源协议，无 GPL 传染风险。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TabLabelCenterFix (AppKit interop)

/// Fixes NSSegmentedControl label centering by forcing equal-width segment distribution.
private struct TabLabelCenterFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The NSSegmentedControl may not exist yet during initial layout,
        // so we retry with increasing delays up to a few times.
        attemptFix(from: nsView, attempt: 0)
    }

    private func attemptFix(from view: NSView, attempt: Int) {
        guard attempt < 5 else { return } // Give up after 5 attempts

        let delay: TimeInterval = [0, 0.05, 0.15, 0.35, 0.75][attempt]

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view = view] in
            guard let view = view else { return }

            // Walk up to window's contentView, then walk down for the segmented control
            var root = view
            while let parent = root.superview { root = parent }

            guard let seg = findSegControl(in: root),
                  seg.segmentCount > 1 else {
                attemptFix(from: view, attempt: attempt + 1)
                return
            }

            // Already fixed? Skip re-application.
            if seg.segmentDistribution == .fillEqually { return }

            seg.segmentDistribution = .fillEqually
            let labels = ["通用", "界面", "搜索", "热键", "备份", "关于"]
            for i in 0..<min(labels.count, seg.segmentCount) {
                seg.setLabel(labels[i], forSegment: i)
            }
            seg.needsDisplay = true
        }
    }

    private func findSegControl(in view: NSView) -> NSSegmentedControl? {
        if let seg = view as? NSSegmentedControl, seg.segmentCount > 1 {
            return seg
        }
        for sub in view.subviews {
            if let found = findSegControl(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - AccentColor

struct AccentColor: Hashable {
    let name: String
    let color: Color
    let hex: String

    static let presets: [AccentColor] = [
        AccentColor(name: "蓝色", color: .blue, hex: "#007AFF"),
        AccentColor(name: "紫色", color: .purple, hex: "#AF52DE"),
        AccentColor(name: "粉色", color: .pink, hex: "#FF2D55"),
        AccentColor(name: "红色", color: .red, hex: "#FF3B30"),
        AccentColor(name: "橙色", color: .orange, hex: "#FF9500"),
        AccentColor(name: "黄色", color: .yellow, hex: "#FFCC00"),
        AccentColor(name: "绿色", color: .green, hex: "#34C759"),
        AccentColor(name: "青色", color: .cyan, hex: "#5AC8FA"),
    ]
}

// MARK: - HotCornerAction

enum HotCornerAction: String, CaseIterable, Identifiable, Codable {
    case none
    case launchpad
    case missionControl
    case desktop
    case notificationCenter
    case lockScreen
    case startScreenSaver
    case disableScreenSaver
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "无操作"
        case .launchpad: return "启动台"
        case .missionControl: return "调度中心"
        case .desktop: return "显示桌面"
        case .notificationCenter: return "通知中心"
        case .lockScreen: return "锁定屏幕"
        case .startScreenSaver: return "启动屏保"
        case .disableScreenSaver: return "禁用屏保"
        }
    }
}

// MARK: - PreferencesViewModel

final class PreferencesViewModel: ObservableObject {
    @Published var iconSize: Double = 64
    @Published var gridColumns: Int = 6
    @Published var reduceMotion: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var menuBarOnly: Bool = true
    @Published var themeMode: SerializablePreferences.ThemeMode = .system
    @Published var blurIntensity: Double = 0.5
    @Published var selectedAccentColor: AccentColor = AccentColor.presets[0]
    @Published var enableExactSearch: Bool = true
    @Published var enablePrefixSearch: Bool = true
    @Published var enablePinyinSearch: Bool = true
    @Published var enableFuzzySearch: Bool = true
    @Published var fuzzyThreshold: Int = 2
    @Published var hotkeyDisplay: String = "⌥ Space"
    @Published var searchOnFocus: Bool = true
    @Published var hasConflict: Bool = false

    // 多屏分页设置
    @Published var usePagingMode: Bool = true

    
    @Published var useFullscreenMode: Bool = false

    
    @Published var enablePinchGesture: Bool = true
    @Published var isLiquidGlassEnabled: Bool = false


    @Published var appLanguage: String = "zh-Hans"
    
    
    @Published var enableF4Key: Bool = false
    
    
    @Published var enableFourFingerSwipe: Bool = false
    
    
    @Published var hotCornerTL: HotCornerAction = .none
    @Published var hotCornerTR: HotCornerAction = .none
    @Published var hotCornerBL: HotCornerAction = .none
    @Published var hotCornerBR: HotCornerAction = .none
    
    
    @Published var isRecordingHotkey: Bool = false
    @Published var recordingText: String = "点击录制新热键..."
    @Published var hotkeyModifiers: UInt32 = 2048  // optionKey
    @Published var hotkeyCode: UInt32 = 49

    // 补充字段（SerializablePreferences 需要的）
    var accentColorName: String { selectedAccentColor.name }
    var launchCountEnabled: Bool { true }

    var accentColors: [AccentColor] { AccentColor.presets }

    init() {
        let saved = PersistenceService.shared.loadPreferences()
        iconSize = saved.preferredIconSize
        gridColumns = saved.gridColumns
        reduceMotion = saved.reduceMotion
        themeMode = saved.themeMode
        fuzzyThreshold = 2
        hotkeyDisplay = saved.defaultHotKey
        usePagingMode = saved.usePagingMode

        
        useFullscreenMode = saved.useFullscreenMode
        enablePinchGesture = saved.enablePinchGesture
        isLiquidGlassEnabled = saved.isLiquidGlassEnabled
        hotkeyModifiers = saved.hotkeyModifiers
        hotkeyCode = saved.hotkeyCode
        // 从已加载的配置生成显示文本
        let config = HotkeyConfig(modifiers: hotkeyModifiers, keyCode: hotkeyCode)
        hotkeyDisplay = config.displayString

        if let color = AccentColor.presets.first(where: { $0.hex == saved.customAccentColor }) {
            selectedAccentColor = color
        }
        
        // load new fields
        appLanguage = saved.appLanguage
        enableF4Key = saved.enableF4Key
        enableFourFingerSwipe = saved.enableFourFingerSwipe
        hotCornerTL = saved.hotCornerTL
        hotCornerTR = saved.hotCornerTR
        hotCornerBL = saved.hotCornerBL
        hotCornerBR = saved.hotCornerBR
    }

    func save() {
        let prefs = SerializablePreferences(
            preferredIconSize: iconSize,
            gridColumns: gridColumns,
            defaultHotKey: hotkeyDisplay,
            enableFuzzySearch: enableFuzzySearch,
            accentColorName: accentColorName,
            reduceMotion: reduceMotion,
            launchCountEnabled: launchCountEnabled,
            themeMode: themeMode,
            customAccentColor: selectedAccentColor.hex,
            usePagingMode: usePagingMode,
            
            hotkeyModifiers: hotkeyModifiers,
            hotkeyCode: hotkeyCode,
            useFullscreenMode: useFullscreenMode,
            enablePinchGesture: enablePinchGesture,
            appLanguage: appLanguage,
            enableF4Key: enableF4Key,
            enableFourFingerSwipe: enableFourFingerSwipe,
            isLiquidGlassEnabled: isLiquidGlassEnabled,
            hotCornerTL: hotCornerTL,
            hotCornerTR: hotCornerTR,
            hotCornerBL: hotCornerBL,
            hotCornerBR: hotCornerBR
        )
        PersistenceService.shared.savePreferences(prefs)

        // 同步到 UserPreferences 并广播通知让主界面立即更新
        UserPreferences.shared.preferredIconSize = iconSize
        UserPreferences.shared.gridColumns = gridColumns
        UserPreferences.shared.reduceMotion = reduceMotion
        
        UserPreferences.shared.useFullscreenMode = useFullscreenMode
        UserPreferences.shared.enablePinchGesture = enablePinchGesture
        UserPreferences.shared.isLiquidGlassEnabled = isLiquidGlassEnabled
        UserPreferences.shared.hotkeyModifiers = hotkeyModifiers
        UserPreferences.shared.hotkeyCode = hotkeyCode

        
        HotkeyManager.shared.register(with: HotkeyConfig(modifiers: hotkeyModifiers, keyCode: hotkeyCode))

        
        PinchGestureManager.shared.setEnabled(enablePinchGesture)

        // 发送通知让 MainLauncherView 实时更新
        NotificationCenter.default.post(name: .novaPreferencesChanged, object: nil)
    }
    
    // MARK: - v1.1: Language (Immediate)
    
    func applyLanguageImmediate(_ lang: String) {
        let current = Bundle.main.preferredLocalizations.first ?? "en"
        let language: String
        
        switch lang {
        case "system":
            language = Locale.preferredLanguages.first ?? "en"
        case "zh-Hans":
            language = "zh-Hans"
        case "zh-Hant-HK":
            language = "zh-Hant-HK"
        case "zh-Hant-TW":
            language = "zh-Hant-TW"
        case "en":
            language = "en"
        default:
            language = lang
        }
        
        // Save language preference
        let saved = PersistenceService.shared.loadPreferences()
        var updated = saved
        updated.appLanguage = lang
        PersistenceService.shared.savePreferences(updated)
        
        // Set AppleLanguages
        if language != current {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
        
        // Restart app to apply language change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-n", Bundle.main.bundlePath]
            try? task.run()
            NSApp.terminate(nil)
        }
    }
    
    // MARK: - v1.1: Layout Backup
    
    func exportLayout() {
        let savePanel = NSSavePanel()
        savePanel.title = "导出布局数据"
        savePanel.nameFieldStringValue = "NovaLaunch_布局备份_\(dateString()).novalaunch"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        
        // Fix: present as sheet on preferences window to appear on top
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            savePanel.begin { _ in }
            return
        }
        
        savePanel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            let data = LayoutBackupData(
                groups: PersistenceService.shared.loadGroups(),
                preferences: PersistenceService.shared.loadPreferences(),
                analytics: PersistenceService.shared.loadAnalytics()
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            do {
                let jsonData = try encoder.encode(data)
                try jsonData.write(to: url)
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "导出成功"
                    alert.informativeText = "布局数据已保存到：\(url.lastPathComponent)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "好的")
                    alert.beginSheetModal(for: window)
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "导出失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "好的")
                    alert.beginSheetModal(for: window)
                }
            }
        }
    }
    
    func importLayout() {
        let openPanel = NSOpenPanel()
        openPanel.title = "导入布局数据"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            openPanel.begin { _ in }
            return
        }
        
        openPanel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = openPanel.url else { return }
            
            do {
                let jsonData = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let data = try decoder.decode(LayoutBackupData.self, from: jsonData)
                
                // Restore data
                PersistenceService.shared.saveGroups(data.groups)
                PersistenceService.shared.savePreferences(data.preferences)
                PersistenceService.shared.saveAnalytics(data.analytics)
                
                // Reload preferences into view model
                let saved = data.preferences
                self.iconSize = saved.preferredIconSize
                self.gridColumns = saved.gridColumns
                self.hotkeyDisplay = saved.defaultHotKey
                self.themeMode = saved.themeMode
                self.appLanguage = saved.appLanguage
                self.enableF4Key = saved.enableF4Key
                self.enableFourFingerSwipe = saved.enableFourFingerSwipe
                self.hotCornerTL = saved.hotCornerTL
                self.hotCornerTR = saved.hotCornerTR
                self.hotCornerBL = saved.hotCornerBL
                self.hotCornerBR = saved.hotCornerBR
                self.usePagingMode = saved.usePagingMode
                self.enablePinchGesture = saved.enablePinchGesture
                
                if let color = AccentColor.presets.first(where: { $0.hex == saved.customAccentColor }) {
                    self.selectedAccentColor = color
                }
                
                DispatchQueue.main.async {
                    // Notify UI to refresh
                    NotificationCenter.default.post(name: .novaPreferencesChanged, object: nil)
                    
                    let alert = NSAlert()
                    alert.messageText = "导入成功"
                    alert.informativeText = "布局数据已恢复。请重新启动 NovaLaunch 以完全应用更改。"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "好的")
                    alert.beginSheetModal(for: window)
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "导入失败"
                    alert.informativeText = "文件格式不正确：\(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "好的")
                    alert.beginSheetModal(for: window)
                }
            }
        }
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    /// 实时应用图标大小（不等待"完成"按钮）
    func applyIconSize(_ size: Double) {
        // 1. 同步到全局单例（内存）
        UserPreferences.shared.preferredIconSize = size
        // 2. 关键修复：同步保存到磁盘，否则 MainLauncherView 读取磁盘数据时还是旧值
        let saved = PersistenceService.shared.loadPreferences()
        var updated = saved
        updated.preferredIconSize = size
        PersistenceService.shared.savePreferences(updated)
        // 3. 发送通知让主程序立即更新
        NotificationCenter.default.post(name: .novaPreferencesChanged, object: nil)
    }

    /// 实时应用网格列数
    func applyGridColumns(_ columns: Int) {
        UserPreferences.shared.gridColumns = columns
        // 关键修复：同步保存到磁盘
        let saved = PersistenceService.shared.loadPreferences()
        var updated = saved
        updated.gridColumns = columns
        PersistenceService.shared.savePreferences(updated)
        NotificationCenter.default.post(name: .novaPreferencesChanged, object: nil)
    }

    /// 实时应用分屏模式（滚动/分屏）
    func applyUsePagingMode(_ value: Bool) {
        let saved = PersistenceService.shared.loadPreferences()
        var updated = saved
        updated.usePagingMode = value
        PersistenceService.shared.savePreferences(updated)
        NotificationCenter.default.post(name: .novaPreferencesChanged, object: nil)
    }
}

// 通知名称扩展
extension Notification.Name {
    static let novaPreferencesChanged = Notification.Name("com.novalaunch.preferencesChanged")
}

#if DEBUG
struct PreferencesView_Preview: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
#endif
