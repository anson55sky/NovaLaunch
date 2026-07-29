import Foundation
import Combine

// MARK: - GroupViewModel

final class GroupViewModel: ObservableObject {
    @Published var groups: [GroupContainer] = []
    @Published var activeGroupIndex: Int = 0
    @Published var allItems: [ApplicationItem] = []
    
    @Published var dragInsertIndex: Int? = nil

    // 关键修复（v61）：保存持久化时每个 group 的 itemBundleIDs
    private var savedItemBundleIDs: [UUID: [String]] = [:]

    private let persistence = PersistenceService.shared
    private var cancellables = Set<AnyCancellable>()

    var activeGroup: GroupContainer? {
        guard activeGroupIndex < groups.count else { return nil }
        return groups[activeGroupIndex]
    }

    init() {
        
        // 之前 init 时 allItems = []，loadGroups() 恢复的 group.items 全是空的
        // 因为 GroupContainer(from:allItems:) 用空的 allItems 去匹配 → 匹配不到任何 item
        // 虽然 IndexingService.itemsSubject 是 CurrentValueSubject（初始值 []），
        // 但如果上次 scan 已完成并 saveItems，缓存里有数据
        // 先加载缓存 → loadGroups 能正确恢复 → 用户打开 app 立即看到应用
        let cachedItems = persistence.loadItems()
        if !cachedItems.isEmpty {
            allItems = cachedItems
            NovaLog.write("GroupVM", "init: loaded \(cachedItems.count) cached items from persistence")
        }

        loadGroups()

        
        // 之前依赖 MainViewModel.loadGroups 回调（在 .onAppear 中设置），
        // 但时序竞争导致回调经常为 nil → refreshItems 从未被调用 → 应用列表为空
        // 现在让 GroupViewModel 自己监听数据源，不依赖外部回调
        IndexingService.shared.itemsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self = self else { return }
                
                // 如果 items 为空且 self.allItems 已有缓存数据 → 跳过（避免清空）
                // 等 startFullScan 完成后 itemsSubject 会发送真实数据
                if items.isEmpty && !self.allItems.isEmpty {
                    NovaLog.write("GroupVM", "direct subscription: skipping empty items (have \(self.allItems.count) cached)")
                    return
                }
                NovaLog.write("GroupVM", "direct subscription received \(items.count) items")
                self.refreshItems(items)
            }
            .store(in: &cancellables)

        // 关键修复（v4）：订阅 novaAppLaunched 通知，自动刷新"最近使用"分组
        NotificationCenter.default.publisher(for: .novaAppLaunched)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateRecentAppsGroup()
                self.saveGroups()
            }
            .store(in: &cancellables)
    }

    // MARK: - Group CRUD

    func createGroup(title: String, iconName: String = "folder.fill") {
        // 关键修复：禁止创建重复名字的分组
        // 之前用户可以创建多个相同名字的分组，体验很差
        // 现在如果检测到重名直接返回 false
        guard !hasGroup(named: title) else { return }
        let group = GroupContainer(
            title: title,
            iconName: iconName,
            order: groups.count
        )
        groups.append(group)
        saveGroups()
    }

    /// 关键：检查是否已存在同名分组（忽略大小写 + 去除首尾空白）
    func hasGroup(named title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }  // 空名也视为"重复"（不允许）
        return groups.contains { group in
            group.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    func deleteGroup(at index: Int) {
        guard index < groups.count, !groups[index].isSystem else { return }
        groups.remove(at: index)
        rebuildOrders()
        rebuildAllAppsGroup()
        if activeGroupIndex >= groups.count {
            activeGroupIndex = max(0, groups.count - 1)
        }
        saveGroups()
    }

    /// 批量删除文件夹（按 UUID）
    func deleteGroups(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        groups.removeAll { !$0.isSystem && ids.contains($0.id) }
        rebuildOrders()
        rebuildAllAppsGroup()
        if activeGroupIndex >= groups.count {
            activeGroupIndex = max(0, groups.count - 1)
        }
        saveGroups()
    }

    func renameGroup(at index: Int, to title: String) {
        guard index < groups.count else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 关键修复：重命名时也要禁止和其他分组重名
        // 跳过自身索引，检查是否存在同名
        let isDuplicate = groups.enumerated().contains { (i, group) in
            i != index &&
            group.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !isDuplicate else { return }
        groups[index].rename(to: title)
        saveGroups()
    }

    func changeGroupIcon(at index: Int, to icon: String) {
        guard index < groups.count else { return }
        groups[index].changeIcon(to: icon)
        saveGroups()
    }

    func reorderGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        rebuildOrders()
        saveGroups()
    }

    // MARK: - Item Management within Groups

    func addItemToGroup(_ item: ApplicationItem, groupIndex: Int) {
        guard groupIndex < groups.count else { return }
        var g = groups[groupIndex]
        g.add(item)
        groups[groupIndex] = g
        savedItemBundleIDs[g.id] = g.items.map(\.bundleIdentifier)
        NovaLog.write("GroupVM", "addItemToGroup: \(item.displayName) -> \(g.title), savedIDs=\(savedItemBundleIDs[g.id]?.count ?? 0)")
        saveGroups()
    }

    func removeItemFromGroup(_ item: ApplicationItem, groupIndex: Int) {
        guard groupIndex < groups.count else { return }
        var g = groups[groupIndex]
        g.remove(item)
        groups[groupIndex] = g
        savedItemBundleIDs[g.id] = g.items.map(\.bundleIdentifier)
        saveGroups()
    }

    /// 跨分组移动应用（拖拽排序）
    func moveItem(
        _ item: ApplicationItem,
        from sourceGroupIndex: Int,
        to destinationGroupIndex: Int
    ) {
        guard sourceGroupIndex < groups.count,
              destinationGroupIndex < groups.count else { return }

        groups[sourceGroupIndex].remove(item)
        groups[destinationGroupIndex].add(item)
        saveGroups()
    }

    func reorderItems(in groupIndex: Int, from source: IndexSet, to destination: Int) {
        guard groupIndex < groups.count else { return }
        groups[groupIndex].moveItem(from: source, to: destination)
        saveGroups()
    }

    // MARK: - Default "All Apps" Group

    func rebuildAllAppsGroup() {
        // 关键修复（v62）：用 title 查找（不再用 isDefault）
        // 原因：v61 之前持久化的旧数据可能 isDefault = false（字段未持久化）
        // 但 title "全部应用" 是固定的，可以作为唯一标识
        let title = "全部应用"

        // 修复：从"全部应用"中排除已归入用户自建分组的应用
        // 同一个应用不应在"全部应用"和用户文件夹中同时出现
        var groupedBundleIDs = Set<String>()
        for group in groups where !group.isDefault && !group.isSystem {
            for item in group.items {
                groupedBundleIDs.insert(item.bundleIdentifier)
            }
        }
        let ungroupedItems = allItems.filter { !groupedBundleIDs.contains($0.bundleIdentifier) }

        if let idx = groups.firstIndex(where: { $0.title == title }) {
            // Preserve existing custom order for items already in "全部应用"
            let existingItems = groups[idx].items
            
            // Items that were already in "全部应用" — keep their order
            let keptItems = existingItems.filter { item in
                ungroupedItems.contains(where: { $0.bundleIdentifier == item.bundleIdentifier })
            }
            // New items (not previously in "全部应用") — append at end, sorted by name
            let keptIDs = Set(keptItems.map { $0.bundleIdentifier })
            let newItems = ungroupedItems
                .filter { !keptIDs.contains($0.bundleIdentifier) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            
            let mergedItems = keptItems + newItems
            
            groups[idx] = GroupContainer(
                id: groups[idx].id,
                title: title,
                iconName: "square.grid.2x2.fill",
                items: mergedItems,
                order: 0,
                isDefault: true,
                isSystem: true
            )
        } else {
            let allGroup = GroupContainer(
                title: title,
                iconName: "square.grid.2x2.fill",
                items: ungroupedItems.sorted { $0.displayName < $1.displayName },
                order: 0,
                isDefault: true,
                isSystem: true
            )
            groups.insert(allGroup, at: 0)
        }
        // 关键修复（v62）：同时强制 activeGroupIndex 指向"全部应用"（如果当前是无效的）
        if activeGroupIndex >= groups.count || groups[activeGroupIndex].title != title {
            if let allIdx = groups.firstIndex(where: { $0.title == title }) {
                activeGroupIndex = allIdx
            }
        }
        NovaLog.write("GroupVM", "rebuildAllAppsGroup: allItems=\(allItems.count), groups[\(groups.firstIndex(where: { $0.title == title }) ?? -1)].items=\(groups.first(where: { $0.title == title })?.items.count ?? -1), activeGroupIdx=\(activeGroupIndex)")
        saveGroups()
    }

    // MARK: - Persistence

    func saveGroups() {
        let appGroups = groups.map { $0.toAppGroup() }
        persistence.saveGroups(appGroups)
    }

    func loadGroups() {
        let appGroups: [AppGroup] = persistence.loadGroups()
        NovaLog.write("GroupVM", "loadGroups: persisted appGroups count=\(appGroups.count)")
        // 关键修复（v61）：先清空 savedItemBundleIDs（防止重复加载时残留旧数据）
        savedItemBundleIDs.removeAll()
        if appGroups.isEmpty {
            rebuildAllAppsGroup()
            createGroup(title: "收藏", iconName: "star.fill")
            createGroup(title: "最近使用", iconName: "clock.fill")
            // 标记系统内置分组
            for title in ["收藏", "最近使用"] {
                if let idx = groups.firstIndex(where: { $0.title == title }) {
                    groups[idx].isSystem = true
                }
            }
        } else {
            groups = appGroups.map { GroupContainer(from: $0, allItems: allItems) }
                .sorted { $0.order < $1.order }
            NovaLog.write("GroupVM", "loadGroups: after restore groups=\(groups.map { "\($0.title):\($0.items.count):isDefault=\($0.isDefault)" }.joined(separator: ","))")
            // 关键修复（v42）：旧数据从持久化加载时 isSystem 默认为 false
            // 必须按标题重新标记系统内置分组，否则收藏/最近使用的删除按钮仍会显示
            for title in ["收藏", "最近使用"] {
                if let idx = groups.firstIndex(where: { $0.title == title }) {
                    groups[idx].isSystem = true
                }
            }
            // 关键修复（v61）：保存每个 group 的 itemBundleIDs 到 savedItemBundleIDs
            // 这样后续 refreshItems 收到 allItems 时能重新匹配，重建非"全部应用"分组的 items
            for group in appGroups {
                savedItemBundleIDs[group.id] = group.itemBundleIDs
            }
            
            // fix: 不再用 allItems 无条件覆盖"全部应用"，由后续 refreshItems → rebuildAllAppsGroup 统一处理
        }
    }

    func refreshItems(_ items: [ApplicationItem]) {
        NovaLog.write("GroupVM", "refreshItems called with \(items.count) items, current groups=\(groups.count), activeGroupIdx=\(activeGroupIndex)")
        // 关键修复：注入真实分析数据 + 保留已有 createdAt 时间戳
        let analytics = AnalyticsService.shared
        let enriched = items.map { item -> ApplicationItem in
            let existing = allItems.first { $0.bundleIdentifier == item.bundleIdentifier }
            return ApplicationItem(
                id: item.id,
                bundleIdentifier: item.bundleIdentifier,
                displayName: item.displayName,
                name: item.name,
                bundlePath: item.bundlePath,
                executableURL: item.executableURL,
                version: item.version,
                launchCount: analytics.launchCount(for: item.bundleIdentifier),
                lastLaunchedDate: analytics.lastLaunched(for: item.bundleIdentifier),
                createdAt: existing?.createdAt ?? item.createdAt,
                isFavorite: existing?.isFavorite ?? item.isFavorite,
                category: item.category,
                source: item.source
            )
        }
        allItems = enriched
        rebuildAllAppsGroup()
        NovaLog.write("GroupVM", "after rebuildAllAppsGroup: groups[0].items=\(groups.first?.items.count ?? -1), isDefault=\(groups.first?.isDefault ?? false)")
        // 更新最近使用分组
        updateRecentAppsGroup()
        // 重建每个分组中的 items（去掉已卸载的应用 + 用 savedItemBundleIDs 重新匹配）
        // 关键修复（v61）：
        // - 非 isDefault 的 group（如"收藏"）：用持久化的 itemBundleIDs 重新匹配
        //   之前 init 时 allItems 是空，GroupContainer.from 过滤后 items 是空
        //   现在 refreshItems 收到 allItems 后，用 savedItemBundleIDs 重建这些 group 的 items
        for i in groups.indices where !groups[i].isDefault {
            if let savedIDs = savedItemBundleIDs[groups[i].id] {
                // 用持久化的 itemBundleIDs 从当前 allItems 重新匹配
                groups[i].items = allItems.filter { savedIDs.contains($0.bundleIdentifier) }
            } else {
                // 没有 savedIDs（如新建的 group），用原逻辑（去掉已卸载的应用）
                groups[i].items = groups[i].items.filter { item in
                    allItems.contains { $0.bundleIdentifier == item.bundleIdentifier }
                }
            }
        }
        NovaLog.write("GroupVM", "refreshItems done: groups=\(groups.map { "\($0.title):\($0.items.count)" }.joined(separator: ","))")
        saveGroups()
    }
    
    /// 关键修复（v4）：公开方法，可被外部调用刷新"最近使用"分组
    /// （如 app 启动通知触发）
    func updateRecentAppsGroup() {
        let recentItems = AnalyticsService.shared.topRecommendedItems(count: 20, from: allItems)
        if let idx = groups.firstIndex(where: { $0.title == "最近使用" }) {
            groups[idx] = GroupContainer(
                id: groups[idx].id,
                title: "最近使用",
                iconName: groups[idx].iconName,
                items: recentItems,
                order: groups[idx].order,
                isDefault: false,
                isSystem: groups[idx].isSystem
            )
        }
    }

    private func rebuildOrders() {
        for i in groups.indices {
            groups[i] = GroupContainer(
                id: groups[i].id,
                title: groups[i].title,
                iconName: groups[i].iconName,
                colorHex: groups[i].colorHex,
                items: groups[i].items,
                order: i,
                isDefault: groups[i].isDefault,
                isSystem: groups[i].isSystem
            )
        }
    }
}
