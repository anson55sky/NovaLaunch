import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GroupDetailView: View {
    let group: GroupContainer
    @Binding var items: [ApplicationItem]
    let iconSize: CGFloat
    let onRemoveItem: (ApplicationItem) -> Void
    let onRename: (String) -> Void
    let onRenameItem: (ApplicationItem, String) -> Void
    let onIconChange: (String) -> Void
    let onLaunch: (ApplicationItem) -> Void
    let onMoveToGroup: (ApplicationItem, UUID) -> Void
    let onCreateGroup: (ApplicationItem, ApplicationItem) -> Void
    let allGroups: [GroupContainer]
    let onItemAdded: (ApplicationItem) -> Void
    let onReorder: (() -> Void)?
    let onReorderItems: ((Int, Int) -> Void)?  // 全部应用重排：(fromIndex, toIndex)
    let allowMove: Bool
    let onRemoveFromCollection: ((ApplicationItem) -> Void)?
    let accentColor: Color

    @State private var isEditing = false
    @State private var editTitle: String = ""
    @State private var selectedIcon: String = "folder.fill"
    @State private var showingIconPicker = false
    @State private var dropTargetIndex: Int?
    @StateObject private var dragContext = DragContext.shared

    @State private var currentPage: Int = 0
    @State private var usePagingMode: Bool = false  // 删除分页，固定滚动模式
    @State private var cachedWindowWidth: CGFloat = 0
    @State private var cachedWindowHeight: CGFloat = 0
    @State private var gridColumns: Int = 6
    @State private var contentVersion: Int = 0

    enum SortMode: String, CaseIterable {
        case none = "默认"
        case nameAsc = "名称 A→Z"
        case nameDesc = "名称 Z→A"
        case dateAddedNewest = "添加日期 最新"
        case dateAddedOldest = "添加日期 最早"
        case recentlyUsed = "最近使用"
        case mostLaunched = "启动最多"
    }
    @State private var sortMode: SortMode = .none
    @State private var sortedItems: [ApplicationItem]? = nil
    var onSortChanged: ((SortMode) -> Void)?

    private var displayItems: [ApplicationItem] {
        sortedItems ?? items
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: max(2, gridColumns))
    }

    init(group: GroupContainer, items: Binding<[ApplicationItem]>, iconSize: CGFloat,
         onRemoveItem: @escaping (ApplicationItem) -> Void,
         onRename: @escaping (String) -> Void,
         onRenameItem: @escaping (ApplicationItem, String) -> Void,
         onIconChange: @escaping (String) -> Void,
         onLaunch: @escaping (ApplicationItem) -> Void,
         onMoveToGroup: @escaping (ApplicationItem, UUID) -> Void,
         onCreateGroup: @escaping (ApplicationItem, ApplicationItem) -> Void,
         allGroups: [GroupContainer],
         onItemAdded: @escaping (ApplicationItem) -> Void,
         onReorder: (() -> Void)? = nil,
         onReorderItems: ((Int, Int) -> Void)? = nil,
         allowMove: Bool = true,
         onRemoveFromCollection: ((ApplicationItem) -> Void)? = nil,
         accentColor: Color = .blue,
         initialSortMode: SortMode = .none,
         onSortChanged: ((SortMode) -> Void)? = nil) {
        self.group = group
        self._items = items
        self.iconSize = iconSize
        self.onRemoveItem = onRemoveItem
        self.onRename = onRename
        self.onRenameItem = onRenameItem
        self.onIconChange = onIconChange
        self.onLaunch = onLaunch
        self.onMoveToGroup = onMoveToGroup
        self.onCreateGroup = onCreateGroup
        self.allGroups = allGroups
        self.onItemAdded = onItemAdded
        self.onReorder = onReorder
        self.onReorderItems = onReorderItems
        self.allowMove = allowMove
        self.onRemoveFromCollection = onRemoveFromCollection
        self.accentColor = accentColor
        self._sortMode = State(initialValue: initialSortMode)
        self.onSortChanged = onSortChanged
    }

    var body: some View {
        VStack(spacing: 0) {
            groupHeader
            Divider()
            ZStack {
                if displayItems.isEmpty {
                    emptyGroupView
                } else {
                    appGrid
                }
            }
            .contextMenu {
                Divider()
                Menu {
                    Button { applySort(.nameAsc) } label: { Label("名称 A→Z", systemImage: "a.z") }
                    Button { applySort(.nameDesc) } label: { Label("名称 Z→A", systemImage: "z.a") }
                } label: { Label("按名称排序", systemImage: "textformat.abc") }
                Menu {
                    Button { applySort(.dateAddedNewest) } label: { Label("最新在前", systemImage: "clock.arrow.circlepath") }
                    Button { applySort(.dateAddedOldest) } label: { Label("最早在前", systemImage: "clock.arrow.circlepath") }
                } label: { Label("按添加日期排序", systemImage: "calendar") }
                Menu {
                    Button { applySort(.recentlyUsed) } label: { Label("最近使用", systemImage: "clock") }
                    Button { applySort(.mostLaunched) } label: { Label("启动最多", systemImage: "flame") }
                } label: { Label("按使用频率排序", systemImage: "chart.bar") }
                Divider()
                Button { applySort(.none) } label: { Label("恢复默认顺序", systemImage: "arrow.counterclockwise") }
            }
        }
        .onAppear {
            // 跨视图排序持久化：init 时 initialSortMode 已赋值，
            // onAppear 负责将非 .none 的排序应用到实际数据
            if sortMode != .none && sortedItems == nil {
                applySort(sortMode)
            }
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 12) {
            Button { showingIconPicker = true } label: {
                Image(systemName: group.iconName)
                    .font(.title2)
                    .foregroundStyle(group.isSystem ? accentColor : colorFromHex(group.colorHex))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).help("更换图标")

            if isEditing {
                TextField("分组名称", text: $editTitle)
                    .textFieldStyle(.plain).font(.title3.bold())
                    .onSubmit { onRename(editTitle); isEditing = false }
                Button("保存") { isEditing = false; onRename(editTitle) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Text(group.title).font(.title3.bold())
                Button { editTitle = group.title; isEditing = true } label: {
                    Image(systemName: "pencil").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("重命名")
            }
            Spacer()
            Text("\(displayItems.count) 个应用").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .sheet(isPresented: $showingIconPicker) { iconPickerSheet }
    }

    private func itemsPerPage(pageWidth: CGFloat, pageHeight: CGFloat) -> Int {
        let pagingHeight = AppDelegate.sharedPagingAreaSize.height
        let pagingWidth = AppDelegate.sharedPagingAreaSize.width
        let safeHeight = max(120, pagingHeight)
        let safeWidth = max(200, pagingWidth)
        let iconPadding: CGFloat = 8
        let cellWidth: CGFloat = max(40, CGFloat(iconSize) + iconPadding * 2)
        let cellSpacing: CGFloat = 16
        let pagePadding: CGFloat = 20
        let pageContentWidth = max(0, safeWidth - pagePadding * 2)
        let cols = max(1, Int((pageContentWidth + cellSpacing) / (cellWidth + cellSpacing)))
        let labelHeight: CGFloat = 22
        let innerPadding: CGFloat = 8
        let outerPadding: CGFloat = 8
        let cellHeight = CGFloat(iconSize) + labelHeight + innerPadding + outerPadding
        let rows = max(1, Int(floor((safeHeight - pagePadding) / (cellHeight + cellSpacing))))
        return cols * rows
    }

    private func pagedItems(pageWidth: CGFloat, pageHeight: CGFloat) -> [[ApplicationItem]] {
        let perPage = max(1, itemsPerPage(pageWidth: pageWidth, pageHeight: pageHeight))
        let chunks = displayItems.chunked(into: perPage)
        return chunks.isEmpty ? [[]] : chunks
    }

    private var currentPageSize: CGSize { AppDelegate.sharedWindowSize }

    private var appGrid: some View {
        scrolledGrid
            .onReceive(NotificationCenter.default.publisher(for: .novaPreferencesChanged)) { _ in loadPagingSettings() }
            .onAppear { loadPagingSettings() }
    }

    private func applySort(_ mode: SortMode) {
        sortMode = mode
        onSortChanged?(mode)
        let base = items
        var result: [ApplicationItem]
        switch mode {
        case .none:
            sortedItems = nil
            if currentPage != 0 { currentPage = 0 }
            contentVersion += 1
            return
        case .nameAsc:
            result = base.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameDesc:
            result = base.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        case .dateAddedNewest:
            result = base.sorted { $0.createdAt > $1.createdAt }
        case .dateAddedOldest:
            result = base.sorted { $0.createdAt < $1.createdAt }
        case .recentlyUsed:
            result = base.sorted {
                let date0 = $0.lastLaunchedDate ?? $0.createdAt
                let date1 = $1.lastLaunchedDate ?? $1.createdAt
                if date0 != date1 { return date0 > date1 }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .mostLaunched:
            result = base.sorted {
                if $0.launchCount != $1.launchCount { return $0.launchCount > $1.launchCount }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        withAnimation(AnimationTheme.spring) { sortedItems = result }
        if currentPage != 0 { currentPage = 0 }
        contentVersion += 1
    }

    private func loadPagingSettings() {
        let saved = PersistenceService.shared.loadPreferences()
        var versionBump = false
        if saved.usePagingMode != usePagingMode { usePagingMode = saved.usePagingMode }
        if saved.gridColumns != gridColumns { gridColumns = saved.gridColumns; versionBump = true }
        if versionBump { contentVersion += 1 }
    }

    private var scrolledGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                    appIconView(item: item, index: index)
                }
            }
            .padding(20)
        }
        .animation(AnimationTheme.panelAppear, value: displayItems.count)
    }

    private func pagedGridView(pagedItems chunkedItems: [[ApplicationItem]]) -> some View {
        VStack(spacing: 8) {
            PagingScrollView(
                pageCount: chunkedItems.count,
                currentPage: $currentPage,
                contentVersion: contentVersion
            ) { pageIndex, pageWidth, pageHeight in
                pagedGrid(items: chunkedItems[pageIndex], pageIndex: pageIndex, pageWidth: pageWidth, pageHeight: pageHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            compactPageIndicator(pageCount: chunkedItems.count)
        }
        .animation(AnimationTheme.panelAppear, value: displayItems.count)
    }

    private func compactPageIndicator(pageCount: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(currentPage + 1) / \(pageCount)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(0..<pageCount, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(idx == currentPage ? accentColor : Color.secondary.opacity(0.3))
                        .frame(width: idx == currentPage ? 16 : 6, height: 3)
                        .onTapGesture { withAnimation(AnimationTheme.tabSwitch) { currentPage = idx } }
                }
            }
            .frame(maxWidth: 140)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().fill(Color.white.opacity(0.08)) }
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func appIconView(item: ApplicationItem, index: Int, cellSize: CGFloat? = nil) -> some View {
        let actualSize: CGFloat = cellSize.map { min($0, max(iconSize, 32)) } ?? iconSize
        // 计算插入方向偏移 — 仅被覆盖的目标图标偏移动效
        let offset: CGFloat = dropTargetIndex == index ? {
            switch dragContext.insertDirection {
            case .shiftLeft: return -22
            case .shiftRight: return 22
            case .none: return 0
            }
        }() : 0
        let isDragged = dragContext.draggedItem?.id == item.id
        let isDropTarget = dropTargetIndex == index
        let isCreatePending = group.isDefault && dragContext.hoveredTargetIndex == index
        DraggableAppIcon(
            item: item, size: actualSize,
            isDragged: isDragged,
            isDropTarget: isDropTarget,
            isCreatePending: isCreatePending,
            dropTargetIndex: $dropTargetIndex,
            selfIndex: index,
            action: { onLaunch(item) },
            insertOffsetX: offset
        )
        .equatable()
        .contextMenu {
            Button { onLaunch(item) } label: { Label("打开", systemImage: "arrow.right.circle") }
            Divider()
            Button { showRenamePanel(for: item) } label: { Label("重命名", systemImage: "pencil") }
            if allowMove {
                Divider()
                Menu("移动到") {
                    ForEach(allGroups.filter { $0.id != group.id && $0.title != "最近使用" && $0.title != "全部应用" }) { targetGroup in
                        Button(targetGroup.title) { onMoveToGroup(item, targetGroup.id) }
                    }
                    if allGroups.filter({ $0.id != group.id && $0.title != "最近使用" && $0.title != "全部应用" }).isEmpty {
                        Button("创建新分组") { onMoveToGroup(item, UUID()) }
                    }
                }
            }
            if let removeFromCollection = onRemoveFromCollection {
                Divider()
                Button(group.title == "最近使用" ? "从最近使用删除" : "从收藏删除",
                       systemImage: "star.slash", role: .destructive) {
                    removeFromCollection(item)
                }
            }
            // 用户文件夹：右键删除（从文件夹中移除，非卸载）
            if !group.isSystem && !group.isDefault {
                Divider()
                Button("从文件夹删除", systemImage: "folder.badge.minus", role: .destructive) {
                    onRemoveItem(item)
                }
            }
            Divider()
            Button(role: .destructive) { uninstallApp(item) } label: { Label("卸载", systemImage: "trash") }
        }
        .onDrag {
            // 拖拽开始清除排序，确保视觉顺序 = items 顺序
            sortMode = .none
            sortedItems = nil
            onSortChanged?(.none)
            
            DragContext.shared.startDrag(item, fromGroupId: group.id, sourceIsDefault: group.isDefault, sourceIsSystem: group.isSystem)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: "com.novalaunch.drag.item", visibility: .all) { completion in
                let data = item.bundleIdentifier.data(using: .utf8) ?? Data()
                completion(data, nil); return nil
            }
            provider.registerObject(item.bundleIdentifier as NSString, visibility: .all)
            provider.suggestedName = item.displayName
            return provider
        }
        .onDrop(of: [.text, .utf8PlainText, .plainText], delegate: AppIconDropDelegate(
            target: item, targetIndex: index, group: group, items: $items,
            draggedItem: $dragContext.draggedItem, dropTargetIndex: $dropTargetIndex,
            onCreateGroup: onCreateGroup, onMoveToGroup: onMoveToGroup,
            onReorder: onReorder, onReorderItems: onReorderItems,
            onDidReorder: {
                sortMode = .none
                sortedItems = nil
                onSortChanged?(.none)
            },
            viewSize: actualSize + 4
        ))
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.8)).animation(
                .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.025)),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        ))
    }

    @ViewBuilder
    private func pagedGrid(items pageItems: [ApplicationItem], pageIndex: Int, pageWidth: CGFloat, pageHeight: CGFloat) -> some View {
        if pageItems.isEmpty {
            ZStack {
                Color.clear
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 48)).foregroundStyle(.secondary.opacity(0.5))
                    Text("拖入应用到此处").font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(width: pageWidth, height: pageHeight)
        } else {
            let iconPadding: CGFloat = 8
            let cellWidth = max(40, CGFloat(iconSize) + iconPadding * 2)
            let cellSpacing: CGFloat = 16
            let pagePadding: CGFloat = 20
            let safeWidth = max(200, pageWidth)
            let pageContentWidth = max(0, safeWidth - pagePadding * 2)
            let cols = max(1, Int((pageContentWidth + cellSpacing) / (cellWidth + cellSpacing)))
            let labelHeight: CGFloat = 22
            let innerPadding: CGFloat = 8
            let outerPadding: CGFloat = 8
            let cellHeight = CGFloat(iconSize) + labelHeight + innerPadding + outerPadding
            let rows = max(1, (pageItems.count + cols - 1) / cols)
            VStack(alignment: .center, spacing: cellSpacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(alignment: .center, spacing: cellSpacing) {
                        ForEach(0..<cols, id: \.self) { col in
                            let index = row * cols + col
                            if index < pageItems.count {
                                appIconView(item: pageItems[index], index: pageIndex * cols * rows + index, cellSize: cellWidth)
                                    .frame(width: cellWidth, height: cellHeight)
                            } else {
                                Color.clear.frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                }
            }
            .padding(pagePadding)
            .frame(width: safeWidth, alignment: .topLeading)
        }
    }

    private func showRenamePanel(for item: ApplicationItem) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = "重命名应用"
        panel.level = NSWindow.Level(rawValue: 100000)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let label = NSTextField(labelWithString: "为「\(item.displayName)」设置自定义名称：")
        label.frame = NSRect(x: 20, y: 116, width: 380, height: 20)
        label.font = NSFont.systemFont(ofSize: 12); label.textColor = NSColor.secondaryLabelColor
        label.isBezeled = false; label.isEditable = false; label.drawsBackground = false
        containerView.addSubview(label)
        let textField = NSTextField(frame: NSRect(x: 20, y: 72, width: 380, height: 32))
        textField.stringValue = item.displayName; textField.placeholderString = "新名称"
        textField.bezelStyle = .roundedBezel; textField.font = NSFont.systemFont(ofSize: 14)
        textField.isEditable = true; textField.isSelectable = true; textField.usesSingleLineMode = true
        containerView.addSubview(textField)
        let panelHolder = PanelHolder(panel: panel)
        let closePanel: () -> Void = { [weak panelHolder] in panelHolder?.panel.orderOut(nil) }
        let delegate = TextFieldDelegate(
            onCommit: { [weak textField] in
                guard let tf = textField else { return }
                let newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newName.isEmpty { panelHolder.commitHandler?(newName) }
                closePanel()
            },
            onCancel: { closePanel() }
        )
        textField.delegate = delegate
        panelHolder.fieldDelegate = delegate
        let cancelButton = NSButton(title: "取消", target: delegate, action: #selector(TextFieldDelegate.cancelAction(_:)))
        cancelButton.frame = NSRect(x: 220, y: 20, width: 90, height: 32)
        cancelButton.bezelStyle = .rounded; cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.font = NSFont.systemFont(ofSize: 13)
        containerView.addSubview(cancelButton)
        let saveButton = NSButton(title: "保存", target: delegate, action: #selector(TextFieldDelegate.commitAction(_:)))
        saveButton.frame = NSRect(x: 320, y: 20, width: 90, height: 32)
        saveButton.bezelStyle = .roundRect; saveButton.keyEquivalent = "\r"
        saveButton.font = NSFont.systemFont(ofSize: 13); saveButton.setButtonType(.momentaryPushIn)
        containerView.addSubview(saveButton)
        panelHolder.commitHandler = { newName in
            onRenameItem(item, newName)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                let newItem = ApplicationItem(
                    id: item.id, bundleIdentifier: item.bundleIdentifier, displayName: newName,
                    name: item.name, bundlePath: item.bundlePath, executableURL: item.executableURL,
                    version: item.version, launchCount: item.launchCount,
                    lastLaunchedDate: item.lastLaunchedDate, createdAt: item.createdAt,
                    isFavorite: item.isFavorite, category: item.category, source: item.source
                )
                items[idx] = newItem
            }
        }
        panel.contentView = containerView
        let launcherWindow = AppDelegate.sharedLauncherWindow
        let mainWindow: NSWindow? = launcherWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0 !== AppDelegate.sharedPreferencesWindow && $0.isVisible })
        if let main = mainWindow {
            panel.parent = main
            let mainFrame = main.frame; let panelSize = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: mainFrame.midX - panelSize.width / 2, y: mainFrame.midY - panelSize.height / 2))
        } else { panel.center() }
        panel.makeKeyAndOrderFront(nil); panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true); panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak textField] in
            guard let tf = textField else { return }
            tf.becomeFirstResponder()
            if let editor = tf.currentEditor() { editor.selectedRange = NSRange(location: 0, length: tf.stringValue.count) }
        }
    }

    private func uninstallApp(_ item: ApplicationItem) {
        let alert = NSAlert()
        alert.messageText = "确认卸载 \(item.displayName)？"
        alert.informativeText = "此操作将删除应用程序文件，且无法撤销。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "卸载")
        alert.alertStyle = .warning
        if alert.runModal() == .alertSecondButtonReturn {
            do { try FileManager.default.removeItem(atPath: item.bundlePath); onRemoveItem(item) }
            catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "卸载失败"; errorAlert.informativeText = error.localizedDescription
                errorAlert.runModal()
            }
        }
    }

    private var emptyGroupView: some View {
        VStack(spacing: 16) {
            Image(systemName: group.iconName).font(.system(size: 48)).foregroundStyle(.tertiary)
            Text("拖拽应用到此处").font(.headline).foregroundStyle(.secondary)
            Text("或右键从其他分组添加应用").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if group.isDefault || group.isSystem {
                Color.clear.background(.ultraThinMaterial)
            } else {
                ZStack { AdaptiveGroupTint(items: displayItems); Color.clear.background(.ultraThinMaterial) }
            }
        }
    }

    private var iconPickerSheet: some View {
        NavigationStack {
            TabView {
                // 图标选择
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                        ForEach(SFSymbolIcons.all, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                                onIconChange(icon)
                                showingIconPicker = false
                            } label: {
                                Image(systemName: icon).font(.title2).frame(width: 52, height: 52)
                                    .background(selectedIcon == icon ? accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding()
                }
                .tabItem { Label("图标", systemImage: "star") }
                
                // 颜色选择
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(FolderColors.presets, id: \.hex) { preset in
                            Button {
                                onIconChange(selectedIcon)
                                NotificationCenter.default.post(
                                    name: .novaGroupColorChanged,
                                    object: nil,
                                    userInfo: ["groupId": group.id.uuidString, "colorHex": preset.hex]
                                )
                                showingIconPicker = false
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                                    )
                                    .shadow(color: preset.color.opacity(0.4), radius: 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding()
                }
                .tabItem { Label("颜色", systemImage: "paintpalette") }
            }
            .navigationTitle("自定义文件夹")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showingIconPicker = false } } }
        }
        .frame(width: 380, height: 440)
    }
}

// 颜色选择器预设色卡
enum FolderColors {
    static let presets: [(hex: String, color: Color)] = [
        ("#007AFF", Color(red: 0.00, green: 0.48, blue: 1.00)),
        ("#FF3B30", Color(red: 1.00, green: 0.23, blue: 0.19)),
        ("#FF9500", Color(red: 1.00, green: 0.58, blue: 0.00)),
        ("#FFCC00", Color(red: 1.00, green: 0.80, blue: 0.00)),
        ("#34C759", Color(red: 0.20, green: 0.78, blue: 0.35)),
        ("#00C7BE", Color(red: 0.00, green: 0.78, blue: 0.75)),
        ("#30B0C7", Color(red: 0.19, green: 0.69, blue: 0.78)),
        ("#32ADE6", Color(red: 0.20, green: 0.68, blue: 0.90)),
        ("#5856D6", Color(red: 0.35, green: 0.34, blue: 0.84)),
        ("#AF52DE", Color(red: 0.69, green: 0.32, blue: 0.87)),
        ("#FF2D55", Color(red: 1.00, green: 0.18, blue: 0.33)),
        ("#FF6482", Color(red: 1.00, green: 0.39, blue: 0.51)),
        ("#FFD60A", Color(red: 1.00, green: 0.84, blue: 0.04)),
        ("#64D2FF", Color(red: 0.39, green: 0.82, blue: 1.00)),
        ("#30D158", Color(red: 0.19, green: 0.82, blue: 0.35)),
        ("#0A84FF", Color(red: 0.04, green: 0.52, blue: 1.00)),
    ]
}

private func colorFromHex(_ hex: String) -> Color {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r = Double((int >> 16) & 0xFF) / 255.0
    let g = Double((int >> 8) & 0xFF) / 255.0
    let b = Double(int & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

// MARK: - DraggableAppIcon（改用 Button + PlainPressButtonStyle 防止拖拽误触打开）
// 性能关键点：本视图不再订阅 DragContext，所有拖拽态由父视图在 appIconView 中
// 计算为 isDragged / isDropTarget / isCreatePending 三个纯布尔输入传入。
// 配合 Equatable，拖拽过程中未变化的 cell 会被 SwiftUI 直接跳过 body 重算，
// 从而避免每个 cell 每次都重建 Image(nsImage:) 节点 —— 这是消除掉帧的核心手段。
struct DraggableAppIcon: View, Equatable {
    let item: ApplicationItem
    let size: CGFloat
    let isDragged: Bool
    let isDropTarget: Bool       // 即时高亮：dropTargetIndex 命中即出现（0 延迟反馈）
    let isCreatePending: Bool    // 强提示：计时器到期且中心重叠，即将建文件夹
    @Binding var dropTargetIndex: Int?
    let selfIndex: Int
    let action: () -> Void
    var insertOffsetX: CGFloat = 0

    /// 仅比较会驱动渲染的输入，忽略 closure / binding 身份，
    /// 使拖拽中未变化的 cell 经 .equatable() 跳过 body。
    static func == (lhs: DraggableAppIcon, rhs: DraggableAppIcon) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.size == rhs.size &&
        lhs.isDragged == rhs.isDragged &&
        lhs.isDropTarget == rhs.isDropTarget &&
        lhs.isCreatePending == rhs.isCreatePending &&
        lhs.insertOffsetX == rhs.insertOffsetX &&
        lhs.selfIndex == rhs.selfIndex
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: item.loadIcon(size: size))
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
                Text(item.displayName).font(.caption).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(4)
            .compositingGroup()
            .shadow(color: isDragged ? .clear : .black.opacity(0.12), radius: 3, x: 0, y: 1.5)
        }
        .buttonStyle(PlainPressButtonStyle())
        .modifier(DragGlassModifier(isDragged: isDragged,
                                   isDropTarget: isDropTarget,
                                   isCreatePending: isCreatePending,
                                   offsetX: insertOffsetX))
        .contentShape(Rectangle())
        .allowsHitTesting(!isDragged)
    }
}

/// ButtonStyle that provides click-press visual feedback without the
/// main-queue timer issues that caused the old isPressed approach to fail.
struct PlainPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

struct DragGlassModifier: ViewModifier {
    let isDragged: Bool
    let isDropTarget: Bool
    let isCreatePending: Bool
    let offsetX: CGFloat
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .opacity(isDragged ? 0.85 : 1.0)
            // 三级缩放：建文件夹强提示 > 即时高亮 > 被拖空洞 > 正常
            .scaleEffect(isCreatePending ? 1.12 : (isDropTarget ? 1.06 : (isDragged ? 0.95 : 1.0)))
            .offset(x: offsetX)
            // 位移与缩放在各自变化时使用一致的 spring，避免起停突兀/震颤
            .animation(AnimationTheme.dragShift, value: offsetX)
            .animation(AnimationTheme.dragLift, value: isDropTarget)
            .animation(AnimationTheme.dragLift, value: isCreatePending)
            .animation(AnimationTheme.dragLift, value: isDragged)
            .overlay(
                // 边框视觉提示仅与创建文件夹的判定逻辑绑定：
                // 只有在中心重叠且计时器到期（isCreatePending）时才显示，
                // 避免悬停阶段给出误导性“即将建文件夹”的反馈。
                Group {
                    if isCreatePending {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colorScheme == .dark
                                ? Color.accentColor.opacity(0.22)
                                : Color.accentColor.opacity(0.16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                            }
                    }
                }
            )
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

struct PagingScrollView<Content: View>: NSViewControllerRepresentable {
    let pageCount: Int
    @Binding var currentPage: Int
    let contentVersion: Int
    let content: (Int, CGFloat, CGFloat) -> Content

    func makeNSViewController(context: Context) -> PagingViewController {
        let vc = PagingViewController()
        vc.pageCount = pageCount; vc.contentVersion = contentVersion
        vc.onPageChanged = { newPage in currentPage = newPage }
        DispatchQueue.main.async {
            vc.setupPages { pageIndex, pageWidth, pageHeight in content(pageIndex, pageWidth, pageHeight) }
        }
        return vc
    }

    func updateNSViewController(_ nsViewController: PagingViewController, context: Context) {
        let pageCountChanged = nsViewController.builtPageCount != pageCount
        let versionChanged = nsViewController.contentVersion != contentVersion
        nsViewController.pageCount = pageCount
        if pageCountChanged || versionChanged {
            nsViewController.contentVersion = contentVersion
            nsViewController.setupPages { pageIndex, pageWidth, pageHeight in content(pageIndex, pageWidth, pageHeight) }
        }
        if nsViewController.currentPageIndex != currentPage {
            nsViewController.scrollToPage(currentPage, animated: true)
        }
    }
}

final class PagingViewController: NSViewController {
    var pageCount: Int = 0
    var builtPageCount: Int = 0
    var contentVersion: Int = 0
    var currentPageIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private var pageViews: [NSView] = []

    override func loadView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true; scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none; scrollView.verticalScrollElasticity = .none
        scrollView.allowsMagnification = false; scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.usesPredominantAxisScrolling = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.pageScroll = 100; scrollView.lineScroll = 10
        scrollView.documentView = documentView
        documentView.translatesAutoresizingMaskIntoConstraints = false
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(willStartScroll), name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(didLiveScroll), name: NSScrollView.didLiveScrollNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(didEndLiveScroll), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        self.view = scrollView
    }

    override func viewDidLayout() { super.viewDidLayout(); layoutPages() }

    func setupPages<Content: View>(contentBuilder: (Int, CGFloat, CGFloat) -> Content) {
        pageViews.forEach { $0.removeFromSuperview() }; pageViews.removeAll()
        let containerSize = computePageSize()
        for i in 0..<pageCount {
            let swiftUIView = contentBuilder(i, containerSize.width, containerSize.height)
            let hostingView = NSHostingView(rootView: swiftUIView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.clipsToBounds = true; hostingView.sizingOptions = []
            hostingView.frame = NSRect(x: CGFloat(i) * containerSize.width, y: 0, width: containerSize.width, height: containerSize.height)
            documentView.addSubview(hostingView); pageViews.append(hostingView)
        }
        builtPageCount = pageCount
        documentView.frame = NSRect(x: 0, y: 0, width: containerSize.width * CGFloat(max(1, pageCount)), height: containerSize.height)
        view.layoutSubtreeIfNeeded()
        if currentPageIndex > 0 { scrollToPage(currentPageIndex, animated: false) }
    }

    private func computePageSize() -> NSSize {
        let bw = scrollView.bounds.width; let bh = scrollView.bounds.height
        if bw > 50, bh > 50 { let s = NSSize(width: bw, height: bh); AppDelegate.sharedPagingAreaSize = s; return s }
        let vw = view.bounds.width; let vh = view.bounds.height
        if vw > 50, vh > 50 { let s = NSSize(width: vw, height: vh); AppDelegate.sharedPagingAreaSize = s; return s }
        return NSSize(width: 720, height: 560)
    }

    private func layoutPages() {
        guard !pageViews.isEmpty else { return }
        let containerSize = computePageSize(); let pageWidth = containerSize.width; let pageHeight = containerSize.height
        guard pageWidth > 0, pageHeight > 0 else { return }
        documentView.frame = NSRect(x: 0, y: 0, width: pageWidth * CGFloat(pageCount), height: pageHeight)
        for (index, page) in pageViews.enumerated() {
            page.frame = NSRect(x: CGFloat(index) * pageWidth, y: 0, width: pageWidth, height: pageHeight)
        }
    }

    func scrollToPage(_ index: Int, animated: Bool) {
        guard index >= 0 && index < pageCount else { return }
        let pageWidth = scrollView.bounds.width; let targetPoint = NSPoint(x: CGFloat(index) * pageWidth, y: 0)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.40
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                context.allowsImplicitAnimation = true
                scrollView.contentView.animator().setBoundsOrigin(targetPoint)
            }
        } else { scrollView.contentView.setBoundsOrigin(targetPoint) }
        currentPageIndex = index
    }

    private var isUserScrolling = false
    @objc private func willStartScroll() { isUserScrolling = true }
    @objc private func didLiveScroll() {}
    @objc private func didEndLiveScroll() { isUserScrolling = false; snapToNearestPage() }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard !isUserScrolling else { return }
        let pageWidth = scrollView.bounds.width; guard pageWidth > 0 else { return }
        let currentX = scrollView.contentView.bounds.origin.x
        let newPage = Int((currentX + pageWidth / 2) / pageWidth)
        if newPage != currentPageIndex && newPage >= 0 && newPage < pageCount {
            currentPageIndex = newPage; onPageChanged?(newPage)
        }
    }

    private func snapToNearestPage() {
        let pageWidth = scrollView.bounds.width; guard pageWidth > 0 else { return }
        let currentX = scrollView.contentView.bounds.origin.x
        let newPage = max(0, min(pageCount - 1, Int((currentX + pageWidth / 2) / pageWidth)))
        scrollToPage(newPage, animated: true)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

final class PanelHolder {
    let panel: NSPanel
    var commitHandler: ((String) -> Void)?
    var fieldDelegate: NSObject?
    weak var createButton: NSButton?
    init(panel: NSPanel) { self.panel = panel }
}

final class AddGroupTextFieldDelegate: NSObject, NSTextFieldDelegate {
    private let baseDelegate: TextFieldDelegate
    private let onTextChanged: () -> Void
    init(baseDelegate: TextFieldDelegate, onTextChanged: @escaping () -> Void) {
        self.baseDelegate = baseDelegate; self.onTextChanged = onTextChanged
    }
    func controlTextDidChange(_ obj: Notification) { onTextChanged() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        return baseDelegate.control(control, textView: textView, doCommandBy: commandSelector)
    }
}

final class TextFieldDelegate: NSObject, NSTextFieldDelegate {
    private let onCommit: () -> Void
    private let onCancel: () -> Void
    init(onCommit: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit; self.onCancel = onCancel
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { onCommit(); return true }
        else if commandSelector == #selector(NSResponder.cancelOperation(_:)) { onCancel(); return true }
        return false
    }
    @objc func commitAction(_ sender: Any?) { onCommit() }
    @objc func cancelAction(_ sender: Any?) { onCancel() }
}

struct AppIconDropDelegate: DropDelegate {
    let target: ApplicationItem
    let targetIndex: Int
    let group: GroupContainer
    @Binding var items: [ApplicationItem]
    @Binding var draggedItem: ApplicationItem?
    @Binding var dropTargetIndex: Int?
    let onCreateGroup: (ApplicationItem, ApplicationItem) -> Void
    let onMoveToGroup: (ApplicationItem, UUID) -> Void
    let onReorder: (() -> Void)?
    let onReorderItems: ((Int, Int) -> Void)?
    /// 手动拖拽重排后清除排序，使自定义顺序生效
    let onDidReorder: (() -> Void)?
    /// 图标视图的近似尺寸（用于中心点判定）
    var viewSize: CGFloat = 80

    private var isMouseInsideMainWindow: Bool {
        let launcherWindow = AppDelegate.sharedLauncherWindow
            ?? NSApp.windows.first(where: { $0.isVisible })
        guard let window = launcherWindow else { return true }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    /// 通用的拖拽重排方法：区分方向确保从任何方向插入位置一致
    /// - fromIndex > targetIdx（右到左、下到上）：insert at targetIdx（拖拽项占据目标位置）
    /// - fromIndex < targetIdx（左到右、上到下）：insert at targetIdx+1（拖拽项放到目标后面）
    ///   公式：remove → firstIndex(target) → 按方向决定插入偏移
    private func reorderInArray(_ arr: inout [ApplicationItem], fromIndex: Int, targetItemID: UUID) {
        guard fromIndex < arr.count else { return }
        let moved = arr.remove(at: fromIndex)
        let targetIdx = arr.firstIndex(where: { $0.id == targetItemID }) ?? 0
        if fromIndex > targetIdx {
            // 右到左/下到上：拖拽项占据目标位置（目标右推）
            arr.insert(moved, at: targetIdx)
        } else {
            // 左到右/上到下：拖拽项放到目标后面
            arr.insert(moved, at: min(targetIdx + 1, arr.count))
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let insideWindow = isMouseInsideMainWindow
        if !insideWindow {
            withAnimation(AnimationTheme.spring) { draggedItem = nil; dropTargetIndex = nil }
            DragContext.shared.endDrag(); return false
        }
        let dragged = draggedItem ?? DragContext.shared.draggedItem
        defer {
            withAnimation(AnimationTheme.spring) { draggedItem = nil; dropTargetIndex = nil }
            DragContext.shared.endDrag()
        }
        guard let draggedItem = dragged else { return false }
        guard draggedItem.id != target.id else { return false }

        // Case 1: "全部应用" — 直接通过 binding 重排（绑定 setter 自动更新 ViewModel）
        if group.isDefault {
            let hovered = DragContext.shared.hoveredTargetIndex
            if hovered == targetIndex {
                DragContext.shared.cancelHoverTimer()
                onCreateGroup(draggedItem, target)
            } else {
                guard let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }) else { return false }
                withAnimation(AnimationTheme.spring) {
                    reorderInArray(&items, fromIndex: fromIndex, targetItemID: target.id)
                }
                onReorder?()
                onDidReorder?()
            }
            return true
        }

        let sourceGroupId = DragContext.shared.sourceGroupId

        // Case 2: 系统分组（收藏/最近使用）— 允许同组排序，禁止建组和跨组
        if group.isSystem {
            if sourceGroupId == group.id {
                guard let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }) else { return false }
                withAnimation(AnimationTheme.spring) {
                    reorderInArray(&items, fromIndex: fromIndex, targetItemID: target.id)
                }
                onReorder?()
                onDidReorder?()
                return true
            }
            return false
        }

        // Case 3: 用户文件夹 — 同组排序 或 跨组移入
        if sourceGroupId == group.id {
            guard let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }) else { return false }
            withAnimation(AnimationTheme.spring) {
                reorderInArray(&items, fromIndex: fromIndex, targetItemID: target.id)
            }
            onReorder?()
            onDidReorder?()
            return true
        }

        // Case 4: Cross-group — 系统分组仅允许拖到"收藏"（复制），否则禁止拖出
        guard !DragContext.shared.sourceIsSystem || DragContext.shared.sourceIsDefault || group.title == "收藏" else { return false }
        onMoveToGroup(draggedItem, group.id)
        return true
    }

    func dropEntered(info: DropInfo) {
        DragContext.shared.draggedItem = draggedItem ?? DragContext.shared.draggedItem
        // 计算拖拽方向 → 驱动目标图标的位移动效
        if let dragged = draggedItem ?? DragContext.shared.draggedItem,
           let fromIdx = items.firstIndex(where: { $0.id == dragged.id }),
           fromIdx != targetIndex {
            DragContext.shared.insertDirection = fromIdx < targetIndex ? .shiftLeft : .shiftRight
        }
        // 全部应用/集合：记录目标索引用于偏移动效
        withAnimation(AnimationTheme.pointerMove) { dropTargetIndex = targetIndex }
        // "全部应用"：检查中心覆盖以启动建文件夹计时器
        if group.isDefault && draggedItem != nil && draggedItem?.id != target.id {
            checkCenterOverlap(info)
            DragContext.shared.startHoverTimer(targetIndex: targetIndex, groupId: group.id)
        }
    }

    func dropExited(info: DropInfo) {
        DragContext.shared.isCenterOverlapped = false
        DragContext.shared.cancelHoverTimer()
        DragContext.shared.insertDirection = .none
        withAnimation(AnimationTheme.spring) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if dropTargetIndex == targetIndex { dropTargetIndex = nil }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // "全部应用"：实时检测中心覆盖 + 控制计时器
        if group.isDefault && draggedItem != nil && draggedItem?.id != target.id {
            let wasOverlapped = DragContext.shared.isCenterOverlapped
            checkCenterOverlap(info)
            let nowOverlapped = DragContext.shared.isCenterOverlapped
            // 仅在重叠状态翻转时启停计时器，避免高频移动下反复 invalidate/重建 Timer
            if nowOverlapped && !wasOverlapped {
                DragContext.shared.startHoverTimer(targetIndex: targetIndex, groupId: group.id)
            } else if !nowOverlapped && wasOverlapped {
                DragContext.shared.cancelHoverTimer()
            }
        }
        return DropProposal(operation: .move)
    }

    /// 检测拖拽位置是否覆盖目标图标的中心区域（约 35% 半径）
    private func checkCenterOverlap(_ info: DropInfo) {
        let location = info.location
        let halfSize = viewSize / 2
        let centerX = halfSize
        let centerY = halfSize * 0.7  // 图标在上半部分，文字标签在下半部分
        let dx = location.x - centerX
        let dy = location.y - centerY
        let distance = sqrt(dx * dx + dy * dy)
        let threshold = halfSize * 0.65  // 中心 65% 半径区域（宽松判定）
        DragContext.shared.isCenterOverlapped = distance < threshold
    }
}

enum SFSymbolIcons {
    static let all: [String] = [
        "folder.fill", "star.fill", "heart.fill", "bolt.fill", "flag.fill", "bookmark.fill",
        "tag.fill", "pin.fill", "clock.fill", "calendar", "briefcase.fill", "case.fill",
        "desktopcomputer", "laptopcomputer", "iphone", "appletv.fill", "paintbrush.fill",
        "pencil.and.outline", "camera.fill", "music.note", "film.fill", "gamecontroller.fill",
        "book.fill", "newspaper.fill", "doc.fill", "chart.bar.fill", "currency.dollar",
        "cart.fill", "shippingbox.fill", "gear", "wrench.and.screwdriver.fill", "hammer.fill",
        "leaf.fill", "flame.fill", "drop.fill", "snowflake", "globe", "airplane", "car.fill",
        "bicycle", "house.fill", "building.2.fill", "puzzlepiece.fill", "ladybug.fill",
        "hare.fill", "tortoise.fill", "bird.fill", "fish.fill", "ant.fill", "pawprint.fill",
        "brain.head.profile", "eye.fill", "hand.raised.fill", "person.fill", "person.2.fill",
        "person.3.fill", "bubble.left.fill", "envelope.fill", "phone.fill", "wifi",
        "antenna.radiowaves.left.and.right", "lock.fill", "key.fill", "creditcard.fill",
        "creditcard", "banknote.fill", "dollarsign.circle.fill", "barcode", "qrcode",
        "doc.text.fill", "arrow.up.arrow.down", "arrow.left.arrow.right", "star.circle.fill",
        "sparkles", "sparkle",
    ]
}

final class DragContext: ObservableObject {
    static let shared = DragContext()
    @Published var draggedItem: ApplicationItem?
    @Published var sourceGroupId: UUID?
    @Published var draggedTabGroup: UUID?
    @Published var sourceIsDefault: Bool = false  // 拖拽来源是否为"全部应用"
    @Published var sourceIsSystem: Bool = false   // 拖拽来源是否为系统分组（收藏/最近使用）

    /// 拖拽插入方向 — 用于目标图标的位移动效
    enum DragInsertDirection {
        case none
        case shiftLeft   // 目标向左偏移（拖拽源在左侧→左到右拖拽）
        case shiftRight  // 目标向右偏移（拖拽源在右侧→右到左拖拽）
    }
    @Published var insertDirection: DragInsertDirection = .none

    /// 悬停建文件夹状态机 — 在"全部应用"中，拖拽图标重叠≥50%且持续≥0.3s 才触发建文件夹
    private var hoverTimer: Timer?
    private var hoverTargetId: String?   // 悬停目标的 item.id
    private var hoverGroupId: UUID?      // 悬停目标所属的 group.id
    var hoveredTargetIndex: Int? { willSet { objectWillChange.send() } }
    /// 拖拽图标是否覆盖目标中心区域（由 dropUpdated 实时更新）
    var isCenterOverlapped: Bool = false

    func startHoverTimer(targetIndex: Int, groupId: UUID) {
        // 已有计时器运行 → 不重置
        guard hoverTimer == nil else { return }
        hoveredTargetIndex = nil
        hoverTargetId = nil
        hoverGroupId = groupId
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 只有拖拽图标确实覆盖目标中心时，才触发建文件夹
                if self.isCenterOverlapped {
                    self.hoveredTargetIndex = targetIndex
                }
            }
        }
    }

    func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoveredTargetIndex = nil
        hoverTargetId = nil
        hoverGroupId = nil
        isCenterOverlapped = false
    }

    /// 预渲染拖拽预览图缓存 — 拖拽开始时由 DragInterceptHostingView 写入，
    /// 拖拽结束后清除。一次渲染，整个拖拽会话复用。
    var cachedDragPreview: NSImage?

    private var mouseUpMonitor: Any?
    /// Tracks whether boundary Timer should stay active for non-app-icon drags
    private var boundaryActive = false
    
    /// Timer-based boundary polling (replaces NSEvent local monitor).
    ///
    /// SwiftUI's `.onDrag` uses NSDraggingSession internally. During a drag session,
    /// macOS enters NSEventTrackingRunLoopMode and `.leftMouseDragged` events are
    /// consumed by the drag session — they are NEVER forwarded to local event monitors.
    ///
    /// A Timer scheduled in `.common` modes (which includes `.eventTracking`) bypasses
    /// the event distribution system entirely, polling NSEvent.mouseLocation at ~60fps.
    private var boundaryTimer: Timer?
    
    /// Throttle Escape key sends to avoid flooding the event system.
    /// Escape is sent at most every 100ms while the mouse is outside the window.
    private var lastEscapeTime: Date = .distantPast
    
    /// CGEvent tap that intercepts leftMouseUp at the HID level.
    /// When a drag is active and the mouse-up happens outside the launcher window,
    /// the tap swallows the event (returns nil) — Finder never receives the drop.
    /// This is the primary external prevention; Timer+Escape is the backup.
    private var mouseUpTap: CFMachPort?
    private var mouseUpTapRunLoopSource: CFRunLoopSource?
    
    /// NSDraggingSession captured from DragInterceptHostingView.
    /// When the Timer detects the mouse outside the window, we clear the
    /// dragging pasteboard — Finder has no data to drop.
    private var activeDragSession: NSDraggingSession?

    /// Start boundary monitoring for non-app-icon drags.
    func activateBoundaryMonitor() {
        boundaryActive = true
        guard boundaryTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            guard let self = self, (self.draggedItem != nil || self.boundaryActive) else { return }
            let mouse = NSEvent.mouseLocation
            if let win = AppDelegate.sharedLauncherWindow, !win.frame.contains(mouse) {
                NSPasteboard(name: .drag).clearContents()
                self.sendEscape()
                NotificationCenter.default.post(name: .novaCancelAllDrags, object: nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    func deactivateBoundaryMonitor() {
        boundaryActive = false
    }

    private init() {}

    // MARK: - v111 Session Capture

    func captureSession(_ session: NSDraggingSession) {
        activeDragSession = session
    }

    func releaseSession() {
        activeDragSession = nil
    }
    
    func startDrag(_ item: ApplicationItem, fromGroupId: UUID?, sourceIsDefault: Bool = false, sourceIsSystem: Bool = false) {
        // 修复：清除上一轮拖拽的预览图缓存，避免不同 App 复用同一张预览（缓存未区分来源）
        cachedDragPreview = nil
        draggedItem = item
        sourceGroupId = fromGroupId
        self.sourceIsDefault = sourceIsDefault
        self.sourceIsSystem = sourceIsSystem
        lastEscapeTime = .distantPast
        boundaryActive = true
        
        // Create CGEvent tap to intercept leftMouseUp at HID level.
        // If mouse is outside launcher window during an active drag, swallow the
        // mouse-up event so Finder never receives the drop.
        setupMouseUpTap()
        
        // mouse-up monitor: terminates the drag. On mouse-up, clean up ALL state.
        // Previously, cancelDrag() was called on mouse-up, which sent Escape
        // again unnecessarily. Now we just call endDrag() to clean up.
        if mouseUpMonitor == nil {
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                DispatchQueue.main.async {
                    guard let self = self, self.draggedItem != nil else { return }
                    self.endDrag()
                }
                return event
            }
        }
        
        // Timer polling for boundary detection.
        // Key fix: does NOT call endDrag() when mouse is outside — only sends Escape.
        // draggedItem stays non-nil so the Timer keeps firing, sending Escape
        // repeatedly (throttled) until the system drag session is actually cancelled.
        if boundaryTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                guard let self = self, (self.draggedItem != nil || self.boundaryActive) else { return }
                let mouse = NSEvent.mouseLocation
                if let win = AppDelegate.sharedLauncherWindow, !win.frame.contains(mouse) {
                    NSPasteboard(name: .drag).clearContents()
                    self.sendEscape()
                    NotificationCenter.default.post(name: .novaCancelAllDrags, object: nil)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            boundaryTimer = timer
        }
    }
    
    /// Send hardware-level Escape to cancel the system NSDraggingSession.
    /// Throttled to max 10 sends/second. Called repeatedly by the boundary Timer
    /// while the mouse remains outside the window — not just once.
    private func sendEscape() {
        let now = Date()
        if now.timeIntervalSince(lastEscapeTime) < 0.1 { return }
        lastEscapeTime = now
        
        let keyCode: CGKeyCode = 0x35  // kVK_Escape
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - v110 CGEvent Tap (primary external prevention)
    
    /// Creates a CGEvent tap that intercepts leftMouseUp at the HID level.
    /// When a drag is active and the mouse is outside the launcher window,
    /// the tap swallows the event — Finder never gets the drop.
    private func setupMouseUpTap() {
        guard mouseUpTap == nil else { return }
        
        let mask = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        
        mouseUpTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let selfPtr = Unmanaged<DragContext>.fromOpaque(refcon!).takeUnretainedValue()
                guard selfPtr.draggedItem != nil else { return Unmanaged.passUnretained(event) }
                let mouse = NSEvent.mouseLocation
                if let win = AppDelegate.sharedLauncherWindow, !win.frame.contains(mouse) {
                    // Mouse-up outside the window during an active drag:
                    // swallow the event → Finder never receives the drop.
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        if let tap = mouseUpTap {
            mouseUpTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = mouseUpTapRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
    }
    
    private func teardownMouseUpTap() {
        if let source = mouseUpTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            mouseUpTapRunLoopSource = nil
        }
        if let tap = mouseUpTap {
            CFMachPortInvalidate(tap)
            mouseUpTap = nil
        }
    }
    
    func endDrag() {
        cancelHoverTimer()
        draggedItem = nil
        sourceGroupId = nil
        draggedTabGroup = nil
        activeDragSession = nil
        insertDirection = .none
        boundaryActive = false
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
        if let t = boundaryTimer {
            t.invalidate()
            boundaryTimer = nil
        }
        teardownMouseUpTap()
    }
}

extension Notification.Name {
    static let novaCancelAllDrags = Notification.Name("com.novalaunch.cancelAllDrags")
    static let novaGroupColorChanged = Notification.Name("com.novalaunch.groupColorChanged")
    /// 拖拽开始 — 用于临时关闭 LiquidGlassBackground 毛玻璃效果
    static let novaDragDidBegin = Notification.Name("com.novalaunch.dragDidBegin")
    /// 拖拽结束 — 恢复毛玻璃效果
    static let novaDragDidEnd = Notification.Name("com.novalaunch.dragDidEnd")
}
