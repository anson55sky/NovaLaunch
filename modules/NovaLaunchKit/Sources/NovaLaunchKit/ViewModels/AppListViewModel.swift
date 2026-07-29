// AppList Plugin 的 ViewModel
// 策略：保持 v40 ObservableObject + @Published 风格，订阅 IndexingService.shared
//       调用 SearchService.shared.search(query:in:)，不重写业务逻辑
import Foundation
import Combine
import AppKit

/// AppList Plugin 的 ViewModel 协议（让 PluginManager 能以 AnyObject 形式持有）
@MainActor
public protocol AppListViewModelProtocol: AnyObject, ObservableObject {
    var items: [ApplicationItem] { get }
    var status: IndexingStatus { get }
    var searchQuery: String { get set }
    var filteredItems: [ApplicationItem] { get }
    var isSearching: Bool { get }

    func startScan()
    func application(at index: Int) -> ApplicationItem?
    func launch(_ item: ApplicationItem)
    func toggleFavorite(_ item: ApplicationItem)
}

/// AppList Plugin 的 ViewModel
/// - 订阅 IndexingService.shared.itemsSubject / statusSubject
/// - 用 SearchService.shared.search(query:in:) 实现搜索
/// - 不重写扫描/搜索业务逻辑（业务逻辑在 IndexingService/SearchService 中）
@MainActor
public final class AppListViewModel: ObservableObject, AppListViewModelProtocol {

    // MARK: - Published State

    @Published public private(set) var items: [ApplicationItem] = []
    @Published public private(set) var status: IndexingStatus = .idle
    @Published public var searchQuery: String = "" {
        didSet { recomputeFilteredItems() }
    }
    @Published public private(set) var filteredItems: [ApplicationItem] = []

    public var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Dependencies

    private let indexing: IndexingService
    private let search: SearchService
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    public init(
        indexing: IndexingService = .shared,
        search: SearchService = .shared
    ) {
        self.indexing = indexing
        self.search = search

        // 1. 订阅 items（写入后立即重新计算 filteredItems）
        indexing.itemsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newItems in
                guard let self = self else { return }
                self.items = newItems
                self.recomputeFilteredItems()
            }
            .store(in: &cancellables)

        // 2. 订阅 status（直接 assign）
        indexing.statusSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)
    }

    // MARK: - Public API

    public func startScan() {
        indexing.startFullScan()
    }

    public func application(at index: Int) -> ApplicationItem? {
        guard index >= 0, index < filteredItems.count else { return nil }
        return filteredItems[index]
    }

    public func launch(_ item: ApplicationItem) {
        item.launch()
    }

    public func toggleFavorite(_ item: ApplicationItem) {
        // v41 阶段：仅占位实现。真实 toggle 需要 favoriteStore 注入。
    }

    // MARK: - Private

    private func recomputeFilteredItems() {
        if isSearching {
            filteredItems = search.search(query: searchQuery, in: items)
        } else {
            filteredItems = items
        }
    }
}
