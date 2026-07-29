// AppList Plugin 的 SwiftUI 视图
// 依赖：AppListViewModelProtocol（Task 4）
//
// 绑定策略说明：
//   - 使用泛型 `VM: AppListViewModelProtocol` + `@ObservedObject`
//   - 不能直接用 `@ObservedObject var viewModel: any AppListViewModelProtocol`，
//     因为 Swift 编译器不允许 protocol existential（any P）满足 ObservableObject。
//   - 改用泛型后，编译器在调用点知道具体类型（这里是 AppListViewModel），
//     因此 @ObservedObject 可以正确订阅 objectWillChange。
//   - 对外仍可接受 AppListViewModelProtocol（任何 conformer），符合 Task 5 的 API 契约。
import SwiftUI
import AppKit

// MARK: - AppListRootView

/// AppList 插件的根视图：搜索框 + 扫描状态 + 结果列表
///
/// 用法：
/// ```swift
/// let plugin = AppListPlugin()
/// let viewModel = plugin.makeViewModel()
/// let view = AppListRootView(viewModel: viewModel)
/// ```
public struct AppListRootView<VM: AppListViewModelProtocol>: View {
    @ObservedObject public var viewModel: VM

    public init(viewModel: VM) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 搜索框：用 Binding(get:set:) 桥接到 viewModel.searchQuery
            // （@Published 监听 String 引用变化，但 SwiftUI 仍需通过 Binding 触发重绘）
            AppListSearchBar(query: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.searchQuery = $0 }
            ))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().opacity(0.15)

            // 内容：搜索时显示结果，否则显示扫描状态
            if viewModel.isSearching {
                searchResultsList
            } else {
                statusView
            }
        }
        // 关键：进入视图时启动扫描（如果 IndexingService 还在 idle）
        .onAppear { viewModel.startScan() }
    }

    // MARK: - 搜索结果列表

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.bundleIdentifier) { _, item in
                    AppListRow(item: item, onLaunch: {
                        viewModel.launch(item)
                    })
                }
                if viewModel.filteredItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("没有匹配结果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                }
            }
            .padding(8)
        }
    }

    // MARK: - 扫描状态视图

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .idle:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("准备扫描...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        case .scanning(let progress, let currentPath):
            VStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(maxWidth: 240)
                Text("扫描中：\(currentPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .completed(let count):
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("已扫描 \(count) 个应用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("在搜索框输入关键字以筛选")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            VStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                Text("扫描失败：\(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Search Bar

/// 搜索框（用 .background(.quaternary, in:) ShapeStyle 形式，macOS 12+）
struct AppListSearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索应用（支持拼音）...", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除")
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Row

/// 单个应用行（点击启动）
struct AppListRow: View {
    let item: ApplicationItem
    let onLaunch: () -> Void

    var body: some View {
        Button(action: onLaunch) {
            HStack(spacing: 10) {
                Image(nsImage: item.loadIcon())
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(item.name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                Spacer()
                if item.isSystemApp {
                    Text("系统")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
