import Foundation
import Combine

final class MainViewModel: ObservableObject {
    @Published private(set) var items: [ApplicationItem] = []
    @Published private(set) var filteredItems: [ApplicationItem] = []
    @Published private(set) var status: IndexingStatus = .idle
    @Published var searchQuery: String = ""
    @Published var pluginResults: [PluginResultItem] = []  

    var loadGroups: (([ApplicationItem]) -> Void)?

    private let indexing = IndexingService.shared
    private let search = SearchService.shared
    private let persistence = PersistenceService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Bug Fix: Pre-load cached items so search works immediately on launch
        // (before IndexingService scan completes).
        let cached = persistence.loadItems()
        if !cached.isEmpty {
            // 关键修复：预加载的缓存 items 也需注入真实分析数据
            let analytics = AnalyticsService.shared
            let enriched = cached.map { item in
                ApplicationItem(
                    id: item.id,
                    bundleIdentifier: item.bundleIdentifier,
                    displayName: item.displayName,
                    name: item.name,
                    bundlePath: item.bundlePath,
                    executableURL: item.executableURL,
                    version: item.version,
                    launchCount: analytics.launchCount(for: item.bundleIdentifier),
                    lastLaunchedDate: analytics.lastLaunched(for: item.bundleIdentifier),
                    createdAt: item.createdAt,
                    isFavorite: item.isFavorite,
                    category: item.category,
                    source: item.source
                )
            }
            items = enriched
            filteredItems = enriched
            NovaLog.write("MainVM", "init: pre-loaded \(enriched.count) cached items for search")
        }

        indexing.itemsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self = self else { return }
                NovaLog.write("MainVM", "itemsSubject sink received \(items.count) items, loadGroups is\(self.loadGroups == nil ? " nil" : " set")")
                
                // 关键修复：将 AnalyticsService 中的真实启动统计数据注入 ApplicationItem
                // IndexingService 创建的 item 不含 launchCount/lastLaunchedDate（默认 0/nil）
                // 同时也保留已持久化过的 createdAt 时间戳（避免每次扫描重置）
                let analytics = AnalyticsService.shared
                let existingItems = self.items  // 当前已有 items（可能是缓存的）
                let enriched = items.map { item -> ApplicationItem in
                    let existing = existingItems.first { $0.bundleIdentifier == item.bundleIdentifier }
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
                self.items = enriched
                self.recomputeSearch()
                self.loadGroups?(enriched)
                ApplicationItem.preloadIcons(for: enriched)
            }
            .store(in: &cancellables)

        indexing.statusSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)

        $searchQuery
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.recomputeSearch()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        NovaLog.write("MainVM", "refresh() called, starting full scan")
        indexing.startFullScan()
    }

    func launch(_ item: ApplicationItem) {
        item.launch()
        AnalyticsService.shared.recordLaunch(for: item)
        // 修复：启动应用后立即隐藏启动器主界面，并切换到对应应用
        // （NSWorkspace.openApplication 会激活目标 App，从而完成"切换至对应视图"）
        // 覆盖全部应用 / 收藏 / 最近使用 / 搜索结果 / 全部应用网格 等所有经由此方法的入口
        NotificationCenter.default.post(name: .novaHideLauncher, object: nil)
        // 启动应用后立刻发送通知，GroupViewModel 收到后刷新"最近使用"分组
        // （刷新在后台进行，不受启动器隐藏影响）
        NotificationCenter.default.post(name: .novaAppLaunched, object: item.bundleIdentifier)
    }

    /// 重命名应用（保存自定义名称到 UserDefaults）
    func renameItem(_ item: ApplicationItem, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserPreferences.shared.setCustomName(for: item.bundleIdentifier, name: trimmed)

        // 重新计算 displayName
        var updated = item
        updated = ApplicationItem(
            id: item.id,
            bundleIdentifier: item.bundleIdentifier,
            displayName: trimmed,
            name: item.name,
            bundlePath: item.bundlePath,
            executableURL: item.executableURL,
            version: item.version,
            launchCount: item.launchCount,
            lastLaunchedDate: item.lastLaunchedDate,
            createdAt: item.createdAt,
            isFavorite: item.isFavorite,
            category: item.category,
            source: item.source
        )
        // 替换 items 中的旧项
        if let idx = items.firstIndex(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
            items[idx] = updated
        }
        // 通知 GroupViewModel 刷新
        loadGroups?(items)
    }

    func recomputeSearch() {
        if searchQuery.isEmpty {
            filteredItems = items
        } else {
            filteredItems = search.search(query: searchQuery, in: items)
        }
        Task {
            pluginResults = await SearchPluginManager.shared.search(query: searchQuery)
        }
    }
}
