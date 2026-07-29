import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

struct MainLauncherView: View {
    enum NovaPanel: String, CaseIterable {
        case launcher = "启动台"
        case clipboard = "剪贴板"
        case windows = "窗口管理"

        var icon: String {
            switch self {
            case .launcher: return "sparkle.magnifyingglass"
            case .clipboard: return "doc.on.clipboard"
            case .windows: return "macwindow"
            }
        }

        /// 是否 PRO 专属面板（v1.0）
        var isPro: Bool {
            switch self {
            case .clipboard, .windows: return true
            case .launcher: return false
            }
        }
    }

    @StateObject private var viewModel = MainViewModel()
    @StateObject private var groupVM = GroupViewModel()
    @StateObject private var userPrefs = UserPreferences.shared
    @StateObject private var pluginManager = ViewPluginManager.shared
    @State private var searchText: String = ""
    @State private var iconSize: CGFloat = 64
    @State private var gridColumns: Int = 6
    @FocusState private var isSearchFocused: Bool
    @State private var prefsCancellable: AnyCancellable?
    @State private var appearanceCancellable: AnyCancellable?
    @State private var accentColorCancellable: AnyCancellable?
    @State private var blurCancellable: AnyCancellable?
    @State private var sourceFilter: SourceFilter = .all
    @State private var accentColorHex: String = "#007AFF"
    @State private var accentColor: Color = .blue
    @State private var blurRadius: Double = 0.8  // macOS 27: 默认高模糊强度
    @State private var currentAppearance: ColorScheme = .light
    @State private var isFullscreen: Bool = UserPreferences.shared.useFullscreenMode
    @State private var wallpaperImage: NSImage? = nil
    @State private var activePanel: NovaPanel = .launcher
    @State private var windowWidth: CGFloat = 0

    @Environment(\.colorScheme) var colorScheme
    @State private var arrowX: CGFloat = -1
    @State private var arrowSyncTimer: Timer?

    private static var openPanelHolders: [PanelHolder] = []

    let onClose: () -> Void
    let onOpenSettings: () -> Void
    let onShowMenu: () -> Void

    enum SourceFilter: String, CaseIterable {
        case all = "全部"
        case system = "系统自带"
        case user = "用户安装"
    }

    private var glassOpacityMultiplier: Double {
        let normalized = max(0, min(1, blurRadius))
        return 0.15 + 0.85 * pow(normalized, 0.5)
    }

    private var gridColumnsArray: [GridItem] {
        Array(repeating: GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 16), count: 1)
    }

    var body: some View {
        ZStack {
            // ── Performance: Single-pass glass background (was 6 separate layers) ──
            // Combines: NSVisualEffectView + highlight + shadow + border in one layer
            FusionArrowShape(arrowWidth: 40, arrowHeight: 12, cornerRadius: 6, arrowXOffset: arrowX)
                .fill(.clear)
                .liquidGlass(
                    material: .hudWindow,
                    tintColor: accentColor,
                    tintOpacity: 0.06,       // reduced: less CPU overhead
                    blurRadius: blurRadius * 80.0  // reduced from 100: 20% lighter blur
                )
                .compositingGroup()           // GPU: isolate this layer
                .shadow(color: Color.black.opacity(0.12), radius: 20, y: 8)

            // Content
            VStack(spacing: 0) {
                headerBar
                Divider().opacity(0.06)
                panelButtonsRow

                if activePanel == .launcher {
                    // 左侧边栏 + 右侧内容区
                    HStack(spacing: 0) {
                        sidebarView
                            .frame(width: sidebarWidth)
                        
                        // Drag handle to resize sidebar
                        Divider()
                            .opacity(0.06)
                            .frame(width: 4)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.resizeLeftRight.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newWidth = sidebarWidth + value.translation.width
                                        sidebarWidth = min(max(newWidth, 140), 280)
                                    }
                            )
                        
                        VStack(spacing: 0) {
                            // 系统分组子标签（全部应用/收藏/最近使用）
                            systemTabsBar
                            Divider().opacity(0.12)
                            
                            if groupVM.activeGroup?.title == "全部应用" || groupVM.activeGroup?.title == "所有应用" {
                                sourceFilterBar
                                Divider().opacity(0.12)
                            }
                            
                            Group {
                                if !viewModel.searchQuery.isEmpty {
                                    searchResultsView
                                } else {
                                    currentGroupContent
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else {
                    Group {
                        switch activePanel {
                        case .clipboard:
                            ClipboardPanelContent()
                        case .windows:
                            WindowPanelContent()
                        default:
                            EmptyView()
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: activePanel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .clipShape(FusionArrowShape(arrowWidth: 40, arrowHeight: 12, cornerRadius: 6, arrowXOffset: arrowX))
        .overlay(alignment: .top) {
            // 指向菜单栏图标的箭头指示器（在 clipShape 外部，不会被裁剪）
            if arrowX >= 0 {
                ArrowIndicator(arrowX: arrowX, accentColor: accentColor)
                    .offset(y: -8)
            }
        }
        .edgesIgnoringSafeArea(.top)
        .onAppear {
            // ESC 键监听：批量删除模式下优先退出，否则隐藏窗口
            escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    if isBatchEditMode {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isBatchEditMode = false
                            deleteConfirmGroupIDs.removeAll()
                        }
                        return nil  // 消费事件
                    }
                    // 非批量模式：隐藏窗口
                    if let window = NSApp.keyWindow, window.isVisible {
                        window.orderOut(nil)
                        return nil
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = escKeyMonitor {
                NSEvent.removeMonitor(monitor)
                escKeyMonitor = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .novaPanelChanged)) { notification in
            if let panel = notification.userInfo?["panel"] as? NovaPanel {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activePanel = panel
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .novaLauncherAccentColorChanged)) { notification in
            if let hex = notification.userInfo?["hex"] as? String {
                accentColor = colorFromHex(hex)
                accentColorHex = hex
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .novaLauncherBlurChanged)) { notification in
            if let blur = notification.userInfo?["blur"] as? Double {
                blurRadius = blur
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .novaLauncherAppearanceChanged)) { notification in
            if let appearance = notification.object as? NSAppearance {
                if appearance.name == .darkAqua {
                    currentAppearance = .dark
                } else {
                    currentAppearance = .light
                }
            }
        }
        // Issue #1/#2 Fix: when DragContext detects a drag ending outside
        // the main window, clean up all local drag state (tab reorder, etc.)
        .onReceive(NotificationCenter.default.publisher(for: .novaCancelAllDrags)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                draggedTabSourceIndex = nil
                groupVM.dragInsertIndex = nil
                draggedSidebarGroupId = nil
                sidebarReorderTargetId = nil
            }
        }
        // Issue #3 Fix: update icon size when settings change
        .onReceive(NotificationCenter.default.publisher(for: .novaPreferencesChanged)) { _ in
            let saved = PersistenceService.shared.loadPreferences()
            iconSize = CGFloat(saved.preferredIconSize)
            gridColumns = saved.gridColumns
        }
        // group color change from icon picker
        .onReceive(NotificationCenter.default.publisher(for: .novaGroupColorChanged)) { notification in
            if let groupId = notification.userInfo?["groupId"] as? String,
               let colorHex = notification.userInfo?["colorHex"] as? String,
               let idx = groupVM.groups.firstIndex(where: { $0.id.uuidString == groupId }) {
                groupVM.groups[idx].colorHex = colorHex
                groupVM.saveGroups()
            }
        }
    }
    .onAppear { loadIconSizeFromPrefs(); startArrowSync() }
    .onDisappear { stopArrowSync() }
    .alert("重命名文件夹", isPresented: Binding(
        get: { renameGroupId != nil },
        set: { if !$0 { renameGroupId = nil } }
    )) {
        TextField("文件夹名称", text: $renameGroupText)
        Button("确定") {
            if let gid = renameGroupId,
               let idx = groupVM.groups.firstIndex(where: { $0.id == gid }) {
                let trimmed = renameGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    groupVM.renameGroup(at: idx, to: trimmed)
                }
            }
            renameGroupId = nil
        }
        Button("取消", role: .cancel) { renameGroupId = nil }
    } message: {
        Text("为该文件夹输入新名称")
    }
    .alert("删除文件夹", isPresented: Binding(
        get: { pendingDeleteGroupIndex != nil },
        set: { if !$0 { pendingDeleteGroupIndex = nil } }
    )) {
        Button("取消", role: .cancel) {
            pendingDeleteGroupIndex = nil
        }
        Button("确定删除", role: .destructive) {
            if let idx = pendingDeleteGroupIndex {
                groupVM.deleteGroup(at: idx)
            }
            pendingDeleteGroupIndex = nil
        }
    } message: {
        Text("确定要删除文件夹「\(pendingDeleteGroupTitle)」吗？文件夹内的图标将返回全部应用列表。此操作不可撤销。")
    }
    .alert("批量删除文件夹", isPresented: $showBatchDeleteAlert) {
        Button("取消", role: .cancel) {
            showBatchDeleteAlert = false
        }
        Button("确定删除", role: .destructive) {
            groupVM.deleteGroups(withIDs: deleteConfirmGroupIDs)
            deleteConfirmGroupIDs.removeAll()
            if groupVM.groups.filter({ !$0.isSystem }).isEmpty {
                isBatchEditMode = false
            }
            showBatchDeleteAlert = false
        }
    } message: {
        Text("确定要删除选中的 \(deleteConfirmGroupIDs.count) 个文件夹吗？文件夹内的图标将返回全部应用列表。此操作不可撤销。")
    }
    }

    private func startArrowSync() {
        stopArrowSync()
        syncArrowPosition()
        arrowSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            syncArrowPosition()
        }
    }

    private func stopArrowSync() {
        arrowSyncTimer?.invalidate()
        arrowSyncTimer = nil
    }

    private func syncArrowPosition() {
        let newValue = AppDelegate.sharedArrowXPosition
        if newValue != arrowX && newValue >= 0 {
            arrowX = newValue
        }
    }

    private func handleWindowHover(phase: HoverPhase) {
        switch phase {
        case .active(let location):
            updateCursor(at: location)
        case .ended:
            NSCursor.arrow.set()
        }
    }

    private func updateCursor(at location: CGPoint) {
        let windowSize = AppDelegate.sharedWindowSize
        let windowWidth = windowSize.width
        let windowHeight = windowSize.height
        let edgeSize: CGFloat = 8
        let nearLeft = location.x < edgeSize
        let nearRight = location.x > windowWidth - edgeSize
        let nearTop = location.y > windowHeight - edgeSize
        let nearBottom = location.y < edgeSize
        let isTopLeft = nearLeft && nearTop
        let isTopRight = nearRight && nearTop
        let isBottomLeft = nearLeft && nearBottom
        let isBottomRight = nearRight && nearBottom
        let isCorner = isTopLeft || isTopRight || isBottomLeft || isBottomRight

        if isCorner {
            if isTopLeft || isBottomRight {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.resizeLeftRight.set()
            }
        } else if nearLeft || nearRight {
            NSCursor.resizeLeftRight.set()
        } else if nearTop || nearBottom {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    @ViewBuilder
    private var backgroundMaterial: some View {
        if blurRadius < 0.25 {
            Color.white.opacity(0.001)
        } else if blurRadius < 0.5 {
            Rectangle().fill(.ultraThinMaterial).opacity(0.5)
        } else if blurRadius < 0.75 {
            Rectangle().fill(.regularMaterial).opacity(0.7)
        } else {
            Rectangle().fill(.thickMaterial).opacity(0.9)
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func loadAccentColorFromPrefs() {
        let saved = PersistenceService.shared.loadPreferences()
        accentColor = colorFromHex(saved.customAccentColor)
    }

    private func loadBlurFromPrefs() {
        blurRadius = UserPreferences.shared.blurIntensity
        if let mode = UserPreferences.shared.themeMode as SerializablePreferences.ThemeMode? {
            currentAppearance = (mode == .dark) ? .dark : .light
        }
    }

    private func loadWallpaper() {
        guard isFullscreen else { return }
        if let url = NSWorkspace.shared.desktopImageURL(for: NSScreen.main ?? NSScreen.screens[0]),
           let image = NSImage(contentsOf: url) {
            wallpaperImage = image
        } else {
            wallpaperImage = nil
        }
    }

    private func loadIconSizeFromPrefs() {
        let saved = PersistenceService.shared.loadPreferences()
        iconSize = CGFloat(saved.preferredIconSize)
    }

    private func loadGridColumnsFromPrefs() {
        let saved = PersistenceService.shared.loadPreferences()
        gridColumns = saved.gridColumns
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Logo + brand（交通灯按钮已删除）
            HStack(spacing: 10) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(color: accentColor.opacity(0.2), radius: 4)
                    
                    Text("NovaLaunch")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.88))
                }
            .padding(.trailing, 8)

            Spacer()

            // Glass search bar
            SearchBar(
                text: $viewModel.searchQuery,
                isFocused: $isSearchFocused
            )
            .frame(maxWidth: 240)

            // Icon size toggle
            HStack(spacing: 2) {
                ForEach([48.0, 64.0, 80.0], id: \.self) { size in
                    Button {
                        iconSize = size
                        let saved = PersistenceService.shared.loadPreferences()
                        var updated = saved
                        updated.preferredIconSize = size
                        PersistenceService.shared.savePreferences(updated)
                        UserPreferences.shared.preferredIconSize = size
                        NotificationCenter.default.post(name: .novaPreferencesChanged, object: nil)
                    } label: {
                        Image(systemName: iconSize == size ? "square.fill" : "square")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(iconSize == size ? accentColor : Color.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.glassUltraThin))

            // Tool buttons
            HStack(spacing: 6) {
                Button { viewModel.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("刷新应用列表")

                Button { onOpenSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("设置")

                Button { onShowMenu() } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("更多选项")
            }
            .foregroundStyle(Color.primary.opacity(0.55))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(ColorTheme.glassUltraThin)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.06), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // 双击标题栏 → 窗口最大化/还原（保留任务栏可见）
            AppDelegate.sharedLauncherWindow?.zoom(nil)
        }
    }

    @State private var showingAddGroupPanel = false
    @State private var newGroupName = ""
    @State private var renameGroupId: UUID? = nil
    @State private var renameGroupText = ""

    private func showAddGroupPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "新建分组"
        panel.level = NSWindow.Level(rawValue: 100000)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let label = NSTextField(labelWithString: "请输入新分组的名称：")
        label.frame = NSRect(x: 20, y: 158, width: 340, height: 20)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.secondaryLabelColor
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        containerView.addSubview(label)

        let textField = NSTextField(frame: NSRect(x: 20, y: 120, width: 340, height: 32))
        textField.placeholderString = "新分组名称"
        textField.bezelStyle = .roundedBezel
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.isEditable = true
        textField.isSelectable = true
        textField.usesSingleLineMode = true
        containerView.addSubview(textField)

        let errorLabel = NSTextField(labelWithString: "已存在同名分组，请重新输入")
        errorLabel.frame = NSRect(x: 20, y: 88, width: 340, height: 22)
        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.textColor = NSColor.systemRed
        errorLabel.isBezeled = false
        errorLabel.isEditable = false
        errorLabel.drawsBackground = false
        errorLabel.isHidden = true
        errorLabel.lineBreakMode = .byTruncatingTail
        containerView.addSubview(errorLabel)

        let panelHolder = PanelHolder(panel: panel)

        MainLauncherView.openPanelHolders.append(panelHolder)
        let closePanel: () -> Void = { [weak panelHolder] in
            guard let ph = panelHolder else { return }
            ph.panel.orderOut(nil)
            if let idx = MainLauncherView.openPanelHolders.firstIndex(where: { $0 === ph }) {
                MainLauncherView.openPanelHolders.remove(at: idx)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in
            if let idx = MainLauncherView.openPanelHolders.firstIndex(where: { $0 === panelHolder }) {
                MainLauncherView.openPanelHolders.remove(at: idx)
            }
        }

        let groupVMRef = groupVM
        let delegate = TextFieldDelegate(
            onCommit: { [weak textField, weak panelHolder] in
                guard let tf = textField,
                      let ph = panelHolder else { return }
                let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty && !groupVMRef.hasGroup(named: name) {
                    ph.commitHandler?(name)
                }
                closePanel()
            },
            onCancel: { closePanel() }
        )

        let groupVMRef2 = groupVM
        let extendedDelegate = AddGroupTextFieldDelegate(
            baseDelegate: delegate,
            onTextChanged: { [weak panelHolder, weak errorLabel] in
                guard let ph = panelHolder,
                      let err = errorLabel else { return }
                _ = self.validateGroupName(
                    textField: textField,
                    errorLabel: err,
                    panelHolder: ph,
                    groupVM: groupVMRef2
                )
            }
        )
        textField.delegate = extendedDelegate
        panelHolder.fieldDelegate = extendedDelegate

        let cancelButton = NSButton(title: "取消", target: delegate, action: #selector(TextFieldDelegate.cancelAction(_:)))
        cancelButton.frame = NSRect(x: 180, y: 18, width: 90, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.font = NSFont.systemFont(ofSize: 13)
        containerView.addSubview(cancelButton)

        let createButton = NSButton(title: "创建", target: delegate, action: #selector(TextFieldDelegate.commitAction(_:)))
        createButton.frame = NSRect(x: 280, y: 18, width: 90, height: 32)
        createButton.bezelStyle = .roundRect
        createButton.keyEquivalent = "\r"
        createButton.font = NSFont.systemFont(ofSize: 13)
        createButton.setButtonType(.momentaryPushIn)
        createButton.isEnabled = false
        containerView.addSubview(createButton)

        panelHolder.createButton = createButton

        panelHolder.commitHandler = { name in
            self.groupVM.createGroup(title: name)
        }

        panel.contentView = containerView
        presentPanelAboveMain(panel)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak textField] in
            textField?.becomeFirstResponder()
        }
    }

    @discardableResult
    private func validateGroupName(
        textField: NSTextField,
        errorLabel: NSTextField,
        panelHolder: PanelHolder,
        groupVM: GroupViewModel
    ) -> Bool {
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errorLabel.isHidden = true
            panelHolder.createButton?.isEnabled = false
            return false
        }
        if groupVM.hasGroup(named: name) {
            errorLabel.stringValue = "已存在同名分组，请重新输入"
            errorLabel.isHidden = false
            panelHolder.createButton?.isEnabled = false
            return false
        }
        errorLabel.isHidden = true
        panelHolder.createButton?.isEnabled = true
        return true
    }

    func presentPanelAboveMain(_ panel: NSPanel) {
        let mainWindow: NSWindow? = AppDelegate.sharedLauncherWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0 !== AppDelegate.sharedPreferencesWindow && $0.isVisible })

        if let main = mainWindow {
            panel.parent = main
            let mainFrame = main.frame
            let panelSize = panel.frame.size
            let origin = NSPoint(
                x: mainFrame.midX - panelSize.width / 2,
                y: mainFrame.midY - panelSize.height / 2
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        panel.level = NSWindow.Level(rawValue: 100000)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    private func scanProgress(progress: Double) -> some View {
        HStack {
            ProgressView().controlSize(.small)
            Text("正在索引应用…").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(progress * 100))%").font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // 系统分组水平子标签（全部应用/收藏/最近使用）
    private var systemTabsBar: some View {
        let systemGroups = groupVM.groups.filter(\.isSystem)
        return HStack(spacing: 4) {
            ForEach(Array(systemGroups.enumerated()), id: \.element.id) { i, group in
                let globalIndex = groupVM.groups.firstIndex(where: { $0.id == group.id }) ?? i
                let isActive = groupVM.activeGroupIndex == globalIndex
                
                Button {
                    withAnimation(AnimationTheme.tabSwitch) {
                        groupVM.activeGroupIndex = globalIndex
                        sourceFilter = .all
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: group.iconName)
                            .font(.system(size: 11, weight: .medium))
                        Text(group.title)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        Text("\(group.items.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isActive ? accentColor.opacity(0.10) : Color.primary.opacity(0.03))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isActive ? accentColor.opacity(0.25) : Color.clear, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(ColorTheme.glassUltraThin)
        )
    }
    
    private var sourceFilterBar: some View {
        HStack(spacing: 8) {
            Text("筛选:").font(.caption).foregroundStyle(ColorTheme.textSecondary)

            Picker("", selection: $sourceFilter) {
                ForEach(SourceFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            Text("\(filteredBySource(groupVM.activeGroup?.items ?? []).count) 个应用")
                .font(.caption)
                .foregroundStyle(ColorTheme.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func filteredBySource(_ items: [ApplicationItem]) -> [ApplicationItem] {
        switch sourceFilter {
        case .all: return items
        case .system: return items.filter { $0.isSystemApp }
        case .user: return items.filter { !$0.isSystemApp }
        }
    }

    private var panelButtonsRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(NovaPanel.allCases.enumerated()), id: \.element) { _, panel in
                panelSegmentButton(panel: panel)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(ColorTheme.glassUltraThin)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.04), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
    }

    // MARK: - v89: 左侧垂直侧边栏（仅用户文件夹）
    @State private var sidebarWidth: CGFloat = 170
    
    private var sidebarView: some View {
        let userGroups = groupVM.groups.filter { !$0.isSystem }

        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(userGroups.enumerated()), id: \.element.id) { i, group in
                        let globalIndex = groupVM.groups.firstIndex(where: { $0.id == group.id }) ?? (groupVM.groups.filter(\.isSystem).count + i)
                        if isBatchEditMode {
                            batchSelectableRow(group: group, index: globalIndex)
                        } else {
                            sidebarRow(group: group, index: globalIndex)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }

            if userGroups.count > 5 {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.compact.down").font(.system(size: 9, weight: .bold))
                    Text("更多").font(.system(size: 10, weight: .medium))
                    Image(systemName: "chevron.compact.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(.vertical, 2).padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Divider().opacity(0.08)

            if isBatchEditMode {
                batchEditToolbar
            } else {
                Button { showAddGroupPanel() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(accentColor.opacity(0.8))
                        Text("新建文件夹").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.7))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: sidebarWidth)
        .background(Rectangle().fill(ColorTheme.glassUltraThin))
    }
    
    /// 批量编辑模式下的文件夹行（可勾选）
    @ViewBuilder
    private func batchSelectableRow(group: GroupContainer, index: Int) -> some View {
        let isSelected = deleteConfirmGroupIDs.contains(group.id)
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isSelected {
                        deleteConfirmGroupIDs.remove(group.id)
                    } else {
                        deleteConfirmGroupIDs.insert(group.id)
                    }
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? accentColor : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            sidebarRowLabel(group: group,
                isActive: groupVM.activeGroupIndex == index,
                groupColor: colorFromHex(group.colorHex),
                isDropTarget: false,
                isReorderTarget: false)
        }
        .contextMenu {
            Button("删除分组", systemImage: "trash", role: .destructive) {
                pendingDeleteGroupIndex = index
                pendingDeleteGroupTitle = group.title
            }
        }
    }
    
    /// 批量编辑工具栏
    private var batchEditToolbar: some View {
        HStack(spacing: 8) {
            Button {
                showBatchDeleteAlert = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                    Text("删除 (\(deleteConfirmGroupIDs.count))")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(deleteConfirmGroupIDs.isEmpty ? Color.secondary.opacity(0.3) : Color.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(deleteConfirmGroupIDs.isEmpty ? Color.clear : Color.red.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .disabled(deleteConfirmGroupIDs.isEmpty)
            
            Spacer()
            
            Button("取消") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isBatchEditMode = false
                    deleteConfirmGroupIDs.removeAll()
                }
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
    
    @ViewBuilder
    private func sidebarRow(group: GroupContainer, index: Int) -> some View {
        let isActive = groupVM.activeGroupIndex == index
        let groupColor = group.isSystem ? accentColor : colorFromHex(group.colorHex)
        let isReorderTarget = !group.isSystem && sidebarReorderTargetId == group.id
        let isBeingDragged = !group.isSystem && draggedSidebarGroupId == group.id
        let isDropTarget = draggingTabGroup == group.id && DragContext.shared.draggedItem != nil
        
        Button {
            withAnimation(AnimationTheme.tabSwitch) {
                groupVM.activeGroupIndex = index
                sourceFilter = .all
            }
        } label: {
            sidebarRowLabel(group: group, isActive: isActive, groupColor: groupColor, isDropTarget: isDropTarget, isReorderTarget: isReorderTarget)
                .opacity(isBeingDragged ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(true)
        .scaleEffect(dropAnimationGroupId == group.id ? 1.15 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: dropAnimationGroupId)
        .contextMenu {
            if !group.isSystem {
                Button("重命名", systemImage: "pencil") {
                    renameGroupId = group.id
                    renameGroupText = group.title
                }
                Divider()
                Button("批量删除", systemImage: "checklist") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBatchEditMode = true
                        deleteConfirmGroupIDs.removeAll()
                    }
                }
                Button("删除分组", systemImage: "trash", role: .destructive) {
                    pendingDeleteGroupIndex = index
                    pendingDeleteGroupTitle = group.title
                }
            }
        }
        .onDrag {
            guard !group.isSystem else { return NSItemProvider() }
            draggedSidebarGroupId = group.id
            DragContext.shared.activateBoundaryMonitor()
            return NSItemProvider(object: group.id.uuidString as NSString)
        }
        .allowsHitTesting(true)
        .onDrop(of: [.text], delegate: GroupTabDropDelegate(
            targetGroup: group,
            draggedTabGroup: $draggingTabGroup,
            draggedSidebarGroupId: $draggedSidebarGroupId,
            sidebarReorderTargetId: $sidebarReorderTargetId,
            dropAnimationGroupId: $dropAnimationGroupId,
            onDropItem: { item in
                handleMoveToGroup(item: item, targetGroupId: group.id, fromGroup: groupVM.activeGroup ?? group)
            },
            onReorder: { targetId in
                performSidebarReorder(targetId: targetId)
            }
        ))
    }
    
    @ViewBuilder
    private func sidebarRowLabel(group: GroupContainer, isActive: Bool, groupColor: Color, isDropTarget: Bool, isReorderTarget: Bool) -> some View {
        HStack(spacing: 8) {
            // 左侧彩色竖线标签
            RoundedRectangle(cornerRadius: 2)
                .fill(groupColor)
                .frame(width: 3, height: 16)
                .opacity(isActive ? 1.0 : 0.35)
            
            Image(systemName: group.iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(groupColor)
            Text(group.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(group.items.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(isActive ? groupColor : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(isActive ? groupColor.opacity(0.12) : Color.primary.opacity(0.05))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isActive ? groupColor.opacity(0.10) : Color.primary.opacity(0.02))
        )
        .overlay(
            Capsule()
                .strokeBorder(isActive ? groupColor.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 0.75)
        )
        .contentShape(Capsule())
        .modifier(FolderCardStyle(isActive: isActive, groupColor: groupColor, isDropTarget: isDropTarget))
    }
    
    private func sidebarRowContent(group: GroupContainer, iconColor: Color, titleColor: Color, badgeFgCol: Color, badgeBgCol: Color, isActive: Bool, groupColor: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(groupColor)
                .frame(width: 6, height: 6)
                .opacity(isActive ? 1 : 0.35)
            
            Image(systemName: group.iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            
            Text(group.title)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(titleColor)
            
            Spacer()
            
            countBadge(count: group.items.count, fgColor: badgeFgCol, bgColor: badgeBgCol)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? groupColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isActive ? groupColor.opacity(0.2) : Color.clear, lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    private func countBadge(count: Int, fgColor: Color, bgColor: Color) -> some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(fgColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(bgColor))
    }
    
    struct FolderCardStyle: ViewModifier {
        var isActive: Bool
        var groupColor: Color
        var isDropTarget: Bool
        @State private var isHovered: Bool = false

        func body(content: Content) -> some View {
            content
                .scaleEffect(isDropTarget ? 1.08 : (isHovered ? 1.03 : 1.0))
                .brightness(isHovered && !isDropTarget ? 0.03 : 0)
                .shadow(color: isHovered ? Color.black.opacity(0.04) : .clear, radius: 4, y: 2)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isDropTarget)
                .onHover { isHovered = $0 }
        }
    }

    private var sidebarPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(height: 30)
            .padding(.horizontal, 8)
    }

    private var groupTabsRow: some View {
        // Bug #2 Fix: Native NSScrollView for reliable macOS horizontal scrolling.
        // Bug #4: Overflow dropdown — a "▾" button on the right that shows all groups
        // when tabs overflow, so no group is ever inaccessible.
        HStack(spacing: 0) {
            NativeHorizontalScrollView {
                HStack(spacing: 4) {
                    ForEach(Array(groupVM.groups.enumerated()), id: \.element.id) { index, group in
                        if groupVM.dragInsertIndex == index {
                            TabPlaceholderView()
                        }
                        groupTabButton(group: group, index: index)
                    }
                    if let idx = groupVM.dragInsertIndex, idx >= groupVM.groups.count {
                        TabPlaceholderView()
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.vertical, 6)
            }
            .background(
                Rectangle()
                    .fill(ColorTheme.glassUltraThin)
            )
            
            // Overflow dropdown — always visible, shows all groups in a menu
            Menu {
                ForEach(Array(groupVM.groups.enumerated()), id: \.element.id) { index, group in
                    Button {
                        withAnimation(AnimationTheme.tabSwitch) {
                            groupVM.activeGroupIndex = index
                            sourceFilter = .all
                        }
                    } label: {
                        HStack {
                            Image(systemName: group.iconName)
                            Text(group.title)
                            Spacer()
                            Text("\(group.items.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if groupVM.activeGroupIndex == index {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(accentColor)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled(true)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .frame(height: 52)
    }

    private func TabPlaceholderView() -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.3) : accentColor.opacity(0.5),
                         style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            .frame(width: 90, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor.opacity(0.08))
            )
    }

    private var groupTabBar: some View {
        VStack(spacing: 6) {
            panelButtonsRow
            groupTabsRow
        }
    }

    @ViewBuilder
    private func panelSegmentButton(panel: NovaPanel) -> some View {
        let isSelected = (activePanel == panel)
        Button {
            withAnimation(AnimationTheme.tabSwitch) {
                activePanel = panel
                AppDelegate.shared?.activePanel = panel
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: panel.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(panel.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if panel.isPro {
                    Text("PRO")
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTheme.proText)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ColorTheme.proBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [ColorTheme.proBorderStart, ColorTheme.proBorderEnd],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                }
            }
            .foregroundColor(isSelected ? Color.white : Color.primary.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(accentColor.opacity(0.8))
                            .overlay {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            .shadow(color: accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
                    } else {
                        Capsule()
                            .fill(ColorTheme.glassThin)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(true)
        .scaleEffect(isSelected ? 1.0 : 0.98)
        .animation(AnimationTheme.cardHover, value: isSelected)
    }

    @State private var draggingTabGroup: UUID?
    @State private var draggedTabSourceIndex: Int? = nil
    @State private var draggedSidebarGroupId: UUID?
    @State private var sidebarReorderTargetId: UUID?
    // DragGesture state for sidebar folder reorder
    @State private var sidebarDragIdx: Int?
    @State private var sidebarDragTarget: Int?
    // 批量管理
    @State private var isBatchEditMode: Bool = false
    @State private var deleteConfirmGroupIDs: Set<UUID> = []
    // 删除分组确认弹窗
    @State private var pendingDeleteGroupIndex: Int?
    @State private var pendingDeleteGroupTitle: String = ""
    // 批量删除确认
    @State private var showBatchDeleteAlert: Bool = false
    @State private var dropAnimationGroupId: UUID?
    
    /// 跨视图排序状态持久化字典
    /// key: "groupId|filterRawValue"（全部应用）或 "groupId"（其他分组）
    @State private var groupSortModes: [String: GroupDetailView.SortMode] = [:]
    
    /// ESC 键监听器（批量删除模式 + 窗口隐藏）
    @State private var escKeyMonitor: Any?

    private func groupTabButton(group: GroupContainer, index: Int) -> some View {
        Button {
            withAnimation(AnimationTheme.tabSwitch) {
                groupVM.activeGroupIndex = index
                sourceFilter = .all
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: group.iconName).font(.caption)
                    .foregroundStyle(group.isSystem ? .secondary : colorFromHex(group.colorHex))
                Text(group.title).font(.subheadline)
                Text("\(group.items.count)").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tabGlassBackground(for: group, at: index))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(true)
        .contextMenu {
            if !group.isSystem {
                Button("重命名", systemImage: "pencil") {
                    renameGroupId = group.id
                    renameGroupText = group.title
                }
                Divider()
                Button("删除分组", systemImage: "trash", role: .destructive) {
                    pendingDeleteGroupIndex = index
                    pendingDeleteGroupTitle = group.title
                }
            }
        }
        // Bug #3 Root Cause Fix:
        // Two separate .onDrop modifiers on the same View cannot coexist —
        // the outermost (last applied) takes precedence, silently disabling the first.
        // Merged into a single CombinedTabDropDelegate that routes:
        //   - "com.novalaunch.drag.tab" → tab reorder (placeholder + insertion)
        //   - "com.novalaunch.drag.item" → app-item move to target group
        .onDrop(of: [.text], delegate: CombinedTabDropDelegate(
            targetGroup: group,
            targetIndex: index,
            draggedTabGroup: $draggingTabGroup,
            draggedSourceIndex: $draggedTabSourceIndex,
            dragInsertIndex: Binding(
                get: { groupVM.dragInsertIndex },
                set: { groupVM.dragInsertIndex = $0 }
            ),
            onDropItem: { item in
                handleMoveToGroup(item: item, targetGroupId: group.id, fromGroup: groupVM.activeGroup ?? group)
            },
            performReorder: { targetIdx, targetGrp in
                performTabReorder(targetIndex: targetIdx, targetGroup: targetGrp)
            }
        ))
        .modifier(TabDragModifier(
            group: group,
            index: index,
            draggedSourceIndex: $draggedTabSourceIndex,
            onDragStart: {
                draggedTabSourceIndex = index
                groupVM.dragInsertIndex = nil
            },
            onDragEnd: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    draggedTabSourceIndex = nil
                    groupVM.dragInsertIndex = nil
                }
            }
        ))
    }

    @ViewBuilder
    private func tabGlassBackground(for group: GroupContainer, at index: Int) -> some View {
        let isActive = (groupVM.activeGroupIndex == index)
        let isDraggingSelf = (draggedTabSourceIndex == index)
        let isDropTarget = (groupVM.dragInsertIndex == index)
        let groupColor = colorFromHex(group.colorHex)

        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                if isActive { Capsule().fill(groupColor.opacity(0.30)) }
                else if isDraggingSelf { Capsule().fill(groupColor.opacity(0.15)) }
                else if isDropTarget { Capsule().fill(groupColor.opacity(0.20)) }
                else { Capsule().fill(groupColor.opacity(0.08)) }
            }
            .overlay {
                Capsule().fill(LinearGradient(
                    colors: isActive
                        ? [Color.white.opacity(0.45), Color.white.opacity(0.15)]
                        : [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            .overlay {
                let borderOpacity: Double = isActive ? 0.40 : (isDropTarget ? 0.50 : 0.15)
                Capsule().strokeBorder(groupColor.opacity(borderOpacity),
                                 lineWidth: isActive ? 0.5 : (isDropTarget ? 1.0 : 0.5))
            }
    }

    private func performTabReorder(targetIndex: Int, targetGroup: GroupContainer) -> Bool {
        guard let source = draggedTabSourceIndex else { return false }
        guard source != targetIndex else { return false }
        guard !targetGroup.isSystem else { return false }

        var finalTarget = targetIndex
        let lastSystemIdx = groupVM.groups.lastIndex(where: { $0.isSystem }) ?? -1
        if lastSystemIdx >= 0 {
            if finalTarget <= lastSystemIdx { finalTarget = lastSystemIdx + 1 }
            if finalTarget > source && source > lastSystemIdx { finalTarget -= 1 }
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            groupVM.reorderGroups(from: IndexSet([source]), to: finalTarget)
        }
        cleanupTabDrag()
        return true
    }

    private func cleanupTabDrag() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            draggedTabSourceIndex = nil
            groupVM.dragInsertIndex = nil
        }
    }

    // Sidebar group drag reorder
    private func performSidebarReorder(targetId: UUID) {
        guard let sourceId = draggedSidebarGroupId, sourceId != targetId else { return }
        guard let sourceIdx = groupVM.groups.firstIndex(where: { $0.id == sourceId }),
              let targetIdx = groupVM.groups.firstIndex(where: { $0.id == targetId }),
              !groupVM.groups[sourceIdx].isSystem,
              !groupVM.groups[targetIdx].isSystem else { return }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            var finalTarget = targetIdx
            if targetIdx > sourceIdx { finalTarget -= 1 }
            groupVM.reorderGroups(from: IndexSet([sourceIdx]), to: finalTarget)
        }
        cleanupSidebarDrag()
    }
    
    private func cleanupSidebarDrag() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            draggedSidebarGroupId = nil
            sidebarReorderTargetId = nil
        }
    }

    /// 构造排序状态字典的 key
    /// - 全部应用："groupId|filterRawValue" 以便每个分类独立维护排序
    /// - 其他分组："groupId"
    private func sortKey(for group: GroupContainer) -> String {
        if group.title == "全部应用" || group.title == "所有应用" {
            return "\(group.id)|\(sourceFilter.rawValue)"
        }
        return "\(group.id)"
    }

    @ViewBuilder
    private var currentGroupContent: some View {
        if let group = groupVM.activeGroup {
            if group.title == "全部应用" || group.title == "所有应用" {
                GroupDetailView(
                    group: group,
                    items: Binding(
                        get: { filteredBySource(group.items) },
                        set: { newFilteredItems in
                            if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                                let allItems = groupVM.groups[idx].items
                                let newIDs = Set(newFilteredItems.map { $0.bundleIdentifier })
                                let untouchable = allItems.filter { !newIDs.contains($0.bundleIdentifier) }
                                let merged = newFilteredItems + untouchable
                                groupVM.groups[idx] = GroupContainer(
                                    id: group.id, title: group.title, iconName: group.iconName,
                                    colorHex: group.colorHex, items: merged, order: group.order,
                                    isDefault: group.isDefault, isSystem: group.isSystem
                                )
                                groupVM.saveGroups()
                            }
                        }
                    ),
                    iconSize: iconSize,
                    onRemoveItem: { item in
                        if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            groupVM.removeItemFromGroup(item, groupIndex: idx)
                            groupVM.rebuildAllAppsGroup()
                        }
                    },
                    onRename: { newTitle in
                        if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            groupVM.renameGroup(at: idx, to: newTitle)
                        }
                    },
                    onRenameItem: { item, newName in
                        viewModel.renameItem(item, newName: newName)
                    },
                    onIconChange: { newIcon in
                        if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            groupVM.changeGroupIcon(at: idx, to: newIcon)
                        }
                    },
                    onLaunch: { item in
                        viewModel.launch(item)
                    },
                    onMoveToGroup: { item, targetGroupId in
                        handleMoveToGroup(item: item, targetGroupId: targetGroupId, fromGroup: group)
                    },
                    onCreateGroup: { item1, item2 in
                        handleCreateGroup(item1: item1, item2: item2)
                    },
                    allGroups: groupVM.groups,
                    onItemAdded: { _ in groupVM.saveGroups() },
                    onReorder: {
                        if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            groupVM.saveGroups()
                        }
                    },
                    onReorderItems: { fromIdx, toIdx in
                        if let gIdx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            var items = groupVM.groups[gIdx].items
                            // 用 displayed 列表（与 DropDelegate 使用同一索引空间）解析 bundleID
                            let displayed = filteredBySource(items)
                            guard fromIdx < displayed.count, toIdx < displayed.count else { return }
                            let draggedID = displayed[fromIdx].bundleIdentifier
                            let targetID = displayed[toIdx].bundleIdentifier
                            // 在完整列表中定位并重排
                            guard let realFromIdx = items.firstIndex(where: { $0.bundleIdentifier == draggedID }) else { return }
                            let moved = items.remove(at: realFromIdx)
                            let realToIdx = items.firstIndex(where: { $0.bundleIdentifier == targetID }) ?? 0
                            items.insert(moved, at: realToIdx)
                            groupVM.groups[gIdx] = GroupContainer(
                                id: group.id, title: group.title, iconName: group.iconName,
                                colorHex: group.colorHex, items: items, order: group.order,
                                isDefault: group.isDefault, isSystem: group.isSystem
                            )
                            groupVM.saveGroups()
                        }
                    },
                    allowMove: true,
                    accentColor: accentColor,
                    initialSortMode: groupSortModes[sortKey(for: group)] ?? .none,
                    onSortChanged: { mode in
                        groupSortModes[sortKey(for: group)] = mode
                    }
                )
                .id("\(group.id)_\(sourceFilter.rawValue)")
            } else {
                GroupDetailView(
                    group: group,
                    items: Binding(
                        get: { group.items },
                        set: { newItems in
                            if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                                var seen = Set<String>()
                                let deduped = newItems.filter { item in
                                    guard !seen.contains(item.bundleIdentifier) else { return false }
                                    seen.insert(item.bundleIdentifier)
                                    return true
                                }
                                groupVM.groups[idx] = GroupContainer(
                                    id: group.id,
                                    title: group.title,
                                    iconName: group.iconName,
                                    colorHex: group.colorHex,
                                    items: deduped,
                                    order: group.order,
                                    isDefault: group.isDefault,
                                    isSystem: group.isSystem
                                )
                                groupVM.saveGroups()
                            }
                        }
                    ),
                    iconSize: iconSize,
                    onRemoveItem: { item in
                        if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            groupVM.removeItemFromGroup(item, groupIndex: idx)
                            groupVM.rebuildAllAppsGroup()
                        }
                    },
                    onRename: { newTitle in
                        if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            groupVM.renameGroup(at: idx, to: newTitle)
                        }
                    },
                    onRenameItem: { item, newName in
                        viewModel.renameItem(item, newName: newName)
                    },
                    onIconChange: { newIcon in
                        if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            groupVM.changeGroupIcon(at: idx, to: newIcon)
                        }
                    },
                    onLaunch: { item in
                        viewModel.launch(item)
                    },
                    onMoveToGroup: { item, targetGroupId in
                        handleMoveToGroup(item: item, targetGroupId: targetGroupId, fromGroup: group)
                    },
                    onCreateGroup: { item1, item2 in
                        handleCreateGroup(item1: item1, item2: item2)
                    },
                    allGroups: groupVM.groups,
                    onItemAdded: { _ in groupVM.saveGroups() },
                    allowMove: group.title != "最近使用" && group.title != "收藏",
                    onRemoveFromCollection: (group.title == "收藏" || group.title == "最近使用") ? { item in
                        if let idx = groupVM.groups.firstIndex(where: { $0.id == group.id }) {
                            groupVM.removeItemFromGroup(item, groupIndex: idx)
                        }
                    } : nil,
                    accentColor: accentColor,
                    initialSortMode: groupSortModes[sortKey(for: group)] ?? .none,
                    onSortChanged: { mode in
                        groupSortModes[sortKey(for: group)] = mode
                    }
                )
                .id(group.id)
            }
        } else {
            fullAppGrid
        }
    }

    private func handleMoveToGroup(item: ApplicationItem, targetGroupId: UUID, fromGroup: GroupContainer) {
        // 拖到同一分组 → 无需操作（防止图标消失）
        guard targetGroupId != fromGroup.id else { return }
        
        if targetGroupId == UUID() {
            let newGroupId = UUID()
            groupVM.groups.append(GroupContainer(
                id: newGroupId,
                title: "新分组",
                iconName: "folder.fill",
                items: [item],
                order: groupVM.groups.count,
                isDefault: false,
                isSystem: false
            ))
            groupVM.saveGroups()
        } else if let targetIdx = groupVM.groups.firstIndex(where: { $0.id == targetGroupId }) {
            groupVM.addItemToGroup(item, groupIndex: targetIdx)
            // 移动到"收藏" → 复制（保留源位置），其他分组 → 移动
            let isTargetFavorites = groupVM.groups[targetIdx].title == "收藏"
            if !isTargetFavorites {
                if !fromGroup.isDefault {
                    if let fromIdx = groupVM.groups.firstIndex(where: { $0.id == fromGroup.id }) {
                        groupVM.removeItemFromGroup(item, groupIndex: fromIdx)
                    }
                } else {
                    groupVM.rebuildAllAppsGroup()
                }
            }
            groupVM.activeGroupIndex = targetIdx
        }
    }

    private func handleCreateGroup(item1: ApplicationItem, item2: ApplicationItem) {
        let newGroupId = UUID()
        groupVM.groups.append(GroupContainer(
            id: newGroupId,
            title: "新分组",
            iconName: "folder.fill",
            items: [item1, item2],
            order: groupVM.groups.count,
            isDefault: false,
            isSystem: false
        ))
        groupVM.saveGroups()
        // Fix: 从"全部应用"拖入新建分组后，重建"全部应用"以排除已归组的应用
        groupVM.rebuildAllAppsGroup()
        if let newIdx = groupVM.groups.firstIndex(where: { $0.id == newGroupId }) {
            groupVM.activeGroupIndex = newIdx
        }
    }

    private var searchResultsView: some View {
        Group {
            if viewModel.filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("无搜索结果")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("试试搜索: \(viewModel.searchQuery)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("搜索结果").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { viewModel.searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        LazyVGrid(columns: gridColumnsArray, spacing: 20) {
                            ForEach(viewModel.filteredItems) { item in
                                AppIconButton(item: item, size: iconSize) {
                                    viewModel.launch(item)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var fullAppGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumnsArray, spacing: 20) {
                ForEach(filteredBySource(viewModel.filteredItems)) { item in
                    AppIconButton(item: item, size: iconSize) {
                        viewModel.launch(item)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var capsuleTabBar: some View {
        EmptyView()
    }

    @ViewBuilder
    var panelContent: some View {
        switch activePanel {
        case .launcher:
            EmptyView()
        case .clipboard:
            clipboardPanel
        case .windows:
            windowPanel
        }
    }

    private var clipboardPanel: some View {
        ClipboardPanelContent()
    }

    private var windowPanel: some View {
        WindowPanelContent()
    }
}

struct FusionArrowShape: Shape {
    var arrowWidth: CGFloat = 40
    var arrowHeight: CGFloat = 12
    var cornerRadius: CGFloat = 6
    var arrowXOffset: CGFloat = -1  // -1 means center; otherwise pixel offset from left

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let startX: CGFloat
        if arrowXOffset >= 0 {
            startX = arrowXOffset - arrowWidth / 2
        } else {
            startX = (width - arrowWidth) / 2
        }

        path.move(to: CGPoint(x: cornerRadius, y: 0))
        path.addLine(to: CGPoint(x: startX, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: startX + arrowWidth / 2, y: -arrowHeight),
            control: CGPoint(x: startX + arrowWidth * 0.2, y: -arrowHeight)
        )
        path.addQuadCurve(
            to: CGPoint(x: startX + arrowWidth, y: 0),
            control: CGPoint(x: startX + arrowWidth * 0.8, y: -arrowHeight)
        )
        path.addLine(to: CGPoint(x: width - cornerRadius, y: 0))
        path.addArc(
            center: CGPoint(x: width - cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: -90),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: width, y: height - cornerRadius))
        path.addArc(
            center: CGPoint(x: width - cornerRadius, y: height - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: cornerRadius, y: height))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: height - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 180),
            endAngle: Angle(degrees: 270),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

struct ClipboardPanelContent: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared

    var body: some View {
        let entries = clipboardManager.entries
        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.on.clipboard").font(.caption).foregroundStyle(.secondary)
                Text("剪贴板历史").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text("\(entries.count) 条").font(.caption2).foregroundStyle(.tertiary)
                if !entries.isEmpty {
                    Button { ClipboardManager.shared.clearHistory() } label: {
                        Image(systemName: "trash").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 32)).foregroundStyle(.quaternary)
                    Text("暂无剪贴板记录").font(.caption).foregroundStyle(.tertiary)
                    Text("复制任意内容后，此处会自动显示").font(.caption2).foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Divider()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(entries) { entry in
                            ClipboardPanelRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WindowPanelContent: View {
    @ObservedObject private var dashboard = DashboardViewModel.shared
    @State private var appSearchText: String = ""
    @State private var appFilter: AppFilter = .all

    // DragGesture-based reorder (no NSDraggingSession → Finder can't receive)
    @State private var dragSourceIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var dragTranslation: CGFloat = 0

    enum AppFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case browser = "浏览器"
        case other = "其他"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .browser: return "globe"
            case .other: return "app.badge"
            }
        }
    }

    private static let browserBundleIDs: Set<String> = Set(
        BrowserScriptRunner.supportedBrowsers.map { $0.bundleID }
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "macwindow").font(.caption).foregroundStyle(.secondary)
                Text("活跃窗口与浏览器标签").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await dashboard.refreshWindowsAndTabs() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if dashboard.activeWindows.isEmpty && dashboard.browserTabs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow.badge.xmark").font(.system(size: 32)).foregroundStyle(.quaternary)
                    Text("暂无活跃窗口或浏览器标签").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    desktopAppsColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    Divider().opacity(0.15)
                    browserTabsColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var desktopAppsColumn: some View {
        let raw = dashboard.activeWindows
        let filterPass = raw.filter { item in
            switch appFilter {
            case .all: return true
            case .browser:
                guard let bid = item.data?["bundleIdentifier"] else { return false }
                return Self.browserBundleIDs.contains(bid)
            case .other:
                guard let bid = item.data?["bundleIdentifier"] else { return true }
                return !Self.browserBundleIDs.contains(bid)
            }
        }
        let keyword = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let apps: [PluginResultItem] = keyword.isEmpty ? filterPass : filterPass.filter { item in
            item.title.lowercased().contains(keyword) || (item.subtitle.lowercased().contains(keyword))
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow.on.rectangle").font(.caption2).foregroundStyle(.tertiary)
                Text("桌面应用 (\(apps.count))").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("搜索", text: $appSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 60)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.gray.opacity(0.10)))

                Menu {
                    ForEach(AppFilter.allCases) { f in
                        Button { appFilter = f } label: {
                            Label(f.rawValue, systemImage: f.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: appFilter.icon).font(.system(size: 9))
                        Text(appFilter.rawValue).font(.system(size: 10))
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    .foregroundStyle(.primary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.top, 12)

            if apps.isEmpty {
                emptyColumnState(
                    icon: keyword.isEmpty ? "app.badge.checkmark" : "magnifyingglass",
                    text: keyword.isEmpty ? "无活跃窗口" : "无匹配「\(appSearchText)」"
                )
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, item in
                        DesktopAppRow(
                            item: item,
                            isDragSource: dragSourceIndex == index,
                            isDragTarget: dragTargetIndex == index,
                            onActivate: {
                                DashboardViewModel.shared.activateWindow(item)
                                NotificationCenter.default.post(name: .novaHideLauncher, object: nil)
                            },
                            onClose: { DashboardViewModel.shared.closeWindow(item) }
                        )
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                                .onChanged { value in
                                    if dragSourceIndex == nil { dragSourceIndex = index }
                                    dragTranslation = value.translation.height
                                    let rowH: CGFloat = 45
                                    let offset = Int(round(dragTranslation / rowH))
                                    let tgt = min(max(index + offset, 0), apps.count - 1)
                                    if tgt != index { dragTargetIndex = tgt }
                                }
                                .onEnded { _ in
                                    defer { dragSourceIndex = nil; dragTargetIndex = nil; dragTranslation = 0 }
                                    guard let src = dragSourceIndex, let dst = dragTargetIndex, src != dst,
                                          dst < apps.count, src < apps.count else { return }
                                    DashboardViewModel.shared.reorderWindow(sourceID: apps[src].id, targetID: apps[dst].id)
                                }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private var browserTabsColumn: some View {
        let groupedByBrowser = BrowserTabGrouper.groupByBrowser(dashboard.browserTabs)
        let browserWindows = dashboard.activeWindows.filter { item in
            guard let bid = item.data?["bundleIdentifier"] else { return false }
            return Self.browserBundleIDs.contains(bid)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.caption2).foregroundStyle(.tertiary)
                Text("浏览器标签 (\(dashboard.browserTabs.count))").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                if browserWindows.isEmpty && !dashboard.browserTabs.isEmpty {
                    Text("· 浏览器未运行").font(.system(size: 9)).foregroundStyle(.orange.opacity(0.8))
                }
                Spacer()
                if dashboard.browserTabs.isEmpty {
                    Button {
                        requestBrowserPermission()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "key.fill").font(.system(size: 9))
                            Text("授予自动化权限").font(.system(size: 10))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.top, 12)

            if dashboard.browserTabs.isEmpty {
                emptyColumnState(icon: "globe.badge.chevron.backward", text: "未抓到标签 — 点右上角「授予自动化权限」")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedByBrowser) { browserGroup in
                            BrowserSectionView(group: browserGroup)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func requestBrowserPermission() {
        Task {
            let probe = """
            tell application "System Events"
                count processes
            end tell
            """
            _ = await BrowserScriptRunner.runAppleScriptOnce(probe)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await dashboard.refreshWindowsAndTabs()
        }
    }

    private func emptyColumnState(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.quaternary)
            Text(text).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

struct DesktopAppRow: View {
    let item: PluginResultItem
    var isDragSource: Bool = false
    var isDragTarget: Bool = false
    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        Button {
            onActivate?()
        } label: {
            HStack(spacing: 10) {
                iconView.frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 14)).foregroundStyle(.primary).lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                if isHovered {
                    Button { onClose?() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.red.opacity(0.7))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDragSource ? Color.accentColor.opacity(0.25) : (isDragTarget ? Color.accentColor.opacity(0.18) : (isHovered ? Color.accentColor.opacity(0.10) : Color.gray.opacity(0.05))))
            )
        }
        .buttonStyle(.plain)
        .opacity(isDragSource ? 0.4 : 1.0)
        .scaleEffect(isDragSource ? 1.06 : (isDragTarget ? 1.04 : 1.0))
        .shadow(color: isDragSource ? Color.accentColor.opacity(0.4) : .clear, radius: 10, y: 3)
        .zIndex(isDragSource ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: isDragSource)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragTarget)
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering } }
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.icon {
        case .systemName(let name):
            Image(systemName: name).font(.title2).foregroundStyle(.secondary)
        case .appBundleID(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill").font(.title2).foregroundStyle(.secondary)
            }
        case .image(let nsImage):
            Image(nsImage: nsImage).resizable().scaledToFit()
        }
    }
}

// Drop delegate for desktop app reorder
struct DesktopAppDropDelegate: DropDelegate {
    let targetIndex: Int
    let apps: [PluginResultItem]
    @Binding var isDropTarget: Bool
    let onReorder: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard targetIndex < apps.count else { return false }
        return !info.itemProviders(for: ["com.novalaunch.drag.item"]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isDropTarget = true }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isDropTarget = false }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isDropTarget = false }
            DragContext.shared.deactivateBoundaryMonitor()
        }
        // Read source index from custom UTI data representation
        guard let item = info.itemProviders(for: ["com.novalaunch.drag.item"]).first else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var didReorder = false
        item.loadItem(forTypeIdentifier: "com.novalaunch.drag.item", options: nil) { data, _ in
            let s: String? = if let d = data as? Data { String(data: d, encoding: .utf8) } else { data as? String }
            if let sourceStr = s?.trimmingCharacters(in: .whitespaces),
               let srcIdx = Int(sourceStr),
               srcIdx < apps.count, srcIdx != targetIndex {
                onReorder(srcIdx, targetIndex)
                didReorder = true
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
        return didReorder
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct BrowserHostGroup: Identifiable, Hashable {
    let id: String
    let host: String
    let tabs: [PluginResultItem]
}

struct BrowserBrowserGroup: Identifiable, Hashable {
    let id: String
    let browser: String
    let bundleID: String
    let hostGroups: [BrowserHostGroup]
    var totalTabs: Int { hostGroups.reduce(0) { $0 + $1.tabs.count } }
}

enum BrowserTabGrouper {
    static func groupByBrowser(_ tabs: [PluginResultItem]) -> [BrowserBrowserGroup] {
        let byBrowser: [String: [PluginResultItem]] = Dictionary(grouping: tabs) {
            $0.data?["browser"] ?? "其他"
        }

        let supported = BrowserScriptRunner.supportedBrowsers
        let sortedBrowserNames = byBrowser.keys.sorted { a, b in
            let ai = supported.firstIndex(where: { $0.displayName == a })?.distance(to: 0) ?? Int.max
            let bi = supported.firstIndex(where: { $0.displayName == b })?.distance(to: 0) ?? Int.max
            if ai != bi { return ai < bi }
            return a < b
        }

        return sortedBrowserNames.map { browserName in
            let browserTabs = byBrowser[browserName] ?? []
            let bundleID = supported.first(where: { $0.displayName == browserName })?.bundleID
                          ?? supported.first(where: { $0.name == browserName })?.bundleID
                          ?? ""

            var hostDict: [String: [PluginResultItem]] = [:]
            for tab in browserTabs {
                let host = hostOf(tab.data?["url"] ?? "")
                hostDict[host, default: []].append(tab)
            }
            let hostGroups: [BrowserHostGroup] = hostDict.map { (host, list) in
                BrowserHostGroup(id: host, host: host, tabs: list.sorted { $0.title < $1.title })
            }
            .sorted { lhs, rhs in
                if lhs.tabs.count != rhs.tabs.count { return lhs.tabs.count > rhs.tabs.count }
                return lhs.host < rhs.host
            }

            return BrowserBrowserGroup(
                id: browserName,
                browser: browserName,
                bundleID: bundleID,
                hostGroups: hostGroups
            )
        }
    }

    private static func hostOf(_ urlStr: String) -> String {
        guard let url = URL(string: urlStr), let host = url.host, !host.isEmpty else {
            return "其他"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

struct BrowserSectionView: View {
    let group: BrowserBrowserGroup
    @State private var isBrowserExpanded: Bool = true
    @State private var expandedHosts: Set<String>
    @ObservedObject private var faviconLoader = FaviconLoader.shared

    init(group: BrowserBrowserGroup) {
        self.group = group
        _expandedHosts = State(initialValue: Set(group.hostGroups.map { $0.host }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isBrowserExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isBrowserExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 12)
                    AppBundleIconView(bundleID: group.bundleID, fallback: "safari", size: 16)
                    Text(group.browser).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                    Text("\(group.totalTabs)").font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .onAppear {
                for hg in group.hostGroups where hg.host != "其他" {
                    faviconLoader.load(for: hg.host)
                }
            }

            if isBrowserExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(allTabsSorted) { tab in
                        TabPanelRow(item: tab).padding(.leading, 18)
                    }
                }
                .padding(.leading, 6).padding(.top, 2)
            }
        }
    }

    private var allTabsSorted: [PluginResultItem] {
        group.hostGroups.flatMap { $0.tabs }.sorted { $0.title < $1.title }
    }
}

struct AppBundleIconView: View {
    let bundleID: String
    let fallback: String
    let size: CGFloat
    @State private var iconImage: NSImage?

    var body: some View {
        Group {
            if let img = iconImage {
                Image(nsImage: img).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                Image(systemName: fallback).font(.system(size: size * 0.7)).foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .onAppear { loadIcon() }
    }

    private func loadIcon() {
        guard !bundleID.isEmpty, iconImage == nil,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        Task { @MainActor in self.iconImage = img }
    }
}

struct TabPanelRow: View {
    let item: PluginResultItem
    let host: String
    @State private var isHovered = false
    @ObservedObject private var faviconLoader = FaviconLoader.shared

    init(item: PluginResultItem, host: String = "") {
        self.item = item
        self.host = host.isEmpty ? (URL(string: item.data?["url"] ?? "")?.host ?? "") : host
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let img = faviconLoader.cached(for: host) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 2.5))
                } else {
                    Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
            }
            .onAppear { faviconLoader.load(for: host) }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                Text(item.subtitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }

            Spacer()

            if isHovered {
                Button {
                    DashboardViewModel.shared.closeTab(item)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            DashboardViewModel.shared.openTab(item)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

struct ClipboardPanelRow: View {
    let entry: ClipboardEntry
    @State private var isHovered = false

    var body: some View {
        Button {
            ClipboardManager.shared.copyToClipboard(entry)
            NotificationCenter.default.post(name: .novaClipboardCopied, object: nil)
        } label: {
            HStack(spacing: 10) {
                if entry.type == .image, let data = entry.imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage).resizable().scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.truncatedText).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(2)
                    Text(entry.relativeTime).font(.caption).foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

struct WindowPanelRow: View {
    let item: PluginResultItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            switch item.icon {
            case .systemName(let name):
                Image(systemName: name).font(.title3).foregroundStyle(.secondary).frame(width: 44, height: 44)
            case .appBundleID(let bundleID):
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                let icon = NSWorkspace.shared.icon(forFile: url?.path ?? "")
                Image(nsImage: icon).resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .image(let nsImage):
                Image(nsImage: nsImage).resizable().scaledToFit().frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14)).foregroundStyle(.primary).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }

            Spacer()

            if isHovered {
                Button {
                    DashboardViewModel.shared.closeWindow(item)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            DashboardViewModel.shared.activateWindow(item)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - Bug #2 Fix: NativeHorizontalScrollView
/// Bypasses SwiftUI ScrollView(.horizontal) which is fundamentally broken
/// on macOS when inside a VStack — it ignores content overflow regardless
/// of fixedSize, minWidth, or any layout workaround. This wrapper uses a
/// native NSScrollView for guaranteed horizontal scrolling.
struct NativeHorizontalScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.usesPredominantAxisScrolling = true

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView

        // Pin the hosting view to the top of the scroll view
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
        ])

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

struct TabDragModifier: ViewModifier {
    let group: GroupContainer
    let index: Int
    @Binding var draggedSourceIndex: Int?
    let onDragStart: () -> Void
    let onDragEnd: () -> Void

    func body(content: Content) -> some View {
        if group.isSystem {
            content
        } else {
            content
                .onDrag {
                    onDragStart()
                    let provider = NSItemProvider()
                    // Custom UTI + .ownProcess text
                    provider.registerDataRepresentation(
                        forTypeIdentifier: "com.novalaunch.drag.tab",
                        visibility: .all
                    ) { completion in
                        let data = "\(index)".data(using: .utf8) ?? Data()
                        completion(data, nil)
                        return nil
                    }
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.utf8PlainText.identifier,
                        visibility: .ownProcess
                    ) { completion in
                        let data = "\(index)".data(using: .utf8) ?? Data()
                        completion(data, nil)
                        return nil
                    }
                    return provider
                }
        }
    }
}

// MARK: - Bug #3 Root-Cause Fix: CombinedTabDropDelegate
/// SwiftsUI rule: two .onDrop modifiers on the same View cannot coexist —
/// only the outermost (last-applied) one runs. The previous code had separate
/// delegates for app-item drops and tab reorder, but the reorder delegate was
/// always shadowed. This merged delegate routes both UTI types through one entry.
///
/// Bug #3 Additional Fix: validateDrop is intentionally permissive (always
/// returns true). UTI-based filtering inside hasItemsConforming(to:) is
/// unreliable with custom types on macOS Ventura/Sonoma/Sequoia. We filter
/// downstream in performDrop/dropEntered via DragContext state instead.
struct CombinedTabDropDelegate: DropDelegate {
    let targetGroup: GroupContainer
    let targetIndex: Int
    @Binding var draggedTabGroup: UUID?
    @Binding var draggedSourceIndex: Int?
    @Binding var dragInsertIndex: Int?
    let onDropItem: (ApplicationItem) -> Void
    let performReorder: (Int, GroupContainer) -> Bool

    func performDrop(info: DropInfo) -> Bool {
        // Route 1: Tab reorder — signaled by active draggedSourceIndex
        if draggedSourceIndex != nil {
            return performReorder(targetIndex, targetGroup)
        }
        // Route 2: App-item drop — signaled by active DragContext
        defer { DragContext.shared.draggedTabGroup = nil }
        guard let draggedItem = DragContext.shared.draggedItem else { return false }
        DragContext.shared.endDrag()
        onDropItem(draggedItem)
        return true
    }

    func dropEntered(info: DropInfo) {
        // Track both types: tab reorder and app-item move
        if let source = draggedSourceIndex, source != targetIndex {
            dragInsertIndex = targetIndex
        }
        if DragContext.shared.draggedItem != nil {
            draggedTabGroup = targetGroup.id
            DragContext.shared.draggedTabGroup = targetGroup.id
        }
    }

    func dropExited(info: DropInfo) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if dragInsertIndex == targetIndex { dragInsertIndex = nil }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if draggedTabGroup == targetGroup.id { draggedTabGroup = nil }
            if DragContext.shared.draggedTabGroup == targetGroup.id {
                DragContext.shared.draggedTabGroup = nil
            }
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Deprecated: GroupTabDropDelegate (no longer used; replaced by CombinedTabDropDelegate)
struct GroupTabDropDelegate: DropDelegate {
    let targetGroup: GroupContainer
    @Binding var draggedTabGroup: UUID?
    @Binding var draggedSidebarGroupId: UUID?
    @Binding var sidebarReorderTargetId: UUID?
    @Binding var dropAnimationGroupId: UUID?
    let onDropItem: (ApplicationItem) -> Void
    let onReorder: (UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        if let dragId = draggedSidebarGroupId, dragId != targetGroup.id, !targetGroup.isSystem {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                dropAnimationGroupId = nil
            }
            onReorder(targetGroup.id)
            draggedSidebarGroupId = nil
            sidebarReorderTargetId = nil
            return true
        }
        defer { DragContext.shared.draggedTabGroup = nil }
        guard let draggedItem = DragContext.shared.draggedItem else { return false }
        guard !DragContext.shared.sourceIsSystem || DragContext.shared.sourceIsDefault else { return false }
        DragContext.shared.endDrag()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            dropAnimationGroupId = nil
        }
        onDropItem(draggedItem)
        return true
    }

    func dropEntered(info: DropInfo) {
        if draggedSidebarGroupId != nil {
            withAnimation(.easeInOut(duration: 0.15)) {
                sidebarReorderTargetId = targetGroup.id
            }
            if !targetGroup.isSystem {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    dropAnimationGroupId = targetGroup.id
                }
            }
        } else if DragContext.shared.draggedTabGroup != nil {
            draggedTabGroup = targetGroup.id
            DragContext.shared.draggedTabGroup = targetGroup.id
        }
        if DragContext.shared.draggedItem != nil && !targetGroup.isSystem {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                dropAnimationGroupId = targetGroup.id
            }
        }
    }

    func dropExited(info: DropInfo) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if sidebarReorderTargetId == targetGroup.id {
                withAnimation(.easeInOut(duration: 0.15)) { sidebarReorderTargetId = nil }
            }
            if draggedTabGroup == targetGroup.id { draggedTabGroup = nil }
            if DragContext.shared.draggedTabGroup == targetGroup.id { DragContext.shared.draggedTabGroup = nil }
        }
        if dropAnimationGroupId == targetGroup.id {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                dropAnimationGroupId = nil
            }
        }
    }

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

struct PluginResultRow: View {
    let item: PluginResultItem
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    @State private var isHovered = false
    @State private var isClosing = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    switch item.icon {
                    case .systemName(let name):
                        Image(systemName: name).font(.title3).foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    case .appBundleID(let bundleID):
                        let icon = NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path ?? "")
                        Image(nsImage: icon).resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    case .image(let nsImage):
                        Image(nsImage: nsImage).resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(item.title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                            if item.isClosable {
                                Image(systemName: "bolt.fill").font(.system(size: 8))
                                    .foregroundStyle(.orange.opacity(0.6))
                            }
                        }
                        Text(item.subtitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if item.isClosable, let close = onClose {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) { isClosing = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { close() }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isHovered ? Color.red.opacity(0.8) : Color.primary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .opacity(isHovered ? 1.0 : 0.5)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - 指向菜单栏的箭头指示器
struct ArrowIndicator: View {
    let arrowX: CGFloat
    let accentColor: Color
    
    var body: some View {
        Path { path in
            let w: CGFloat = 14
            let h: CGFloat = 8
            path.move(to: CGPoint(x: arrowX - w/2, y: 0))
            path.addLine(to: CGPoint(x: arrowX, y: -h))
            path.addLine(to: CGPoint(x: arrowX + w/2, y: 0))
            path.closeSubpath()
        }
        .fill(accentColor.opacity(0.6))
        .shadow(color: accentColor.opacity(0.3), radius: 3, y: -1)
    }
}

// MARK: - Traffic Light Buttons (macOS 风格)

/// 模拟 macOS 原生红黄绿交通灯按钮
/// - 关闭 → performClose
/// - 最小化 → performMiniaturize
/// - 全屏 → toggleFullScreen
struct TrafficLightButtons: View {
    let onClose: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            TrafficButton(color: Color(red: 1.0, green: 0.23, blue: 0.19),
                          icon: "xmark",
                          action: onClose)
            TrafficButton(color: Color(red: 1.0, green: 0.74, blue: 0.02),
                          icon: "minus",
                          action: { AppDelegate.sharedLauncherWindow?.performMiniaturize(nil) })
            TrafficButton(color: Color(red: 0.15, green: 0.80, blue: 0.25),
                          icon: "arrow.up.left.and.arrow.down.right",
                          action: { AppDelegate.sharedLauncherWindow?.zoom(nil) })
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct TrafficButton: View {
    let color: Color
    let icon: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                if isHovered {
                    Image(systemName: icon)
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 原生窗口拖动区域

/// 用 `mouseDownCanMoveWindow = true` 标记标题栏为拖动区域
/// 这是 macOS 原生无标题栏窗口的标准做法，无闪屏，无手势冲突
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView {
        let v = DragHandleNSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        return v
    }
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}
}

class DragHandleNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}