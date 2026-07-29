// PluginTabView — 动态 Tab 视图（v41 Task 8）
//
// 职责：
// 1. PluginTabView: 根据 ViewPluginManager.activePlugin 渲染当前激活 Plugin 的内容
// 2. PluginTabBar: 顶部 Tab 切换条，点击切换 manager.activePluginID
// 3. PluginContentHost: 单个 Plugin 的内容宿主，懒创建并持有 viewModel 生命周期
// 4. TabFramePreferenceKey: 上报每个 Tab 按钮的 frame 给父级（v41 Task 10 动态小箭头用）
//
// 关键设计：
// - viewModel 用 @State 持有（结构体值类型），@State 在 View 生命周期内稳定
//   → 切换 Tab 时 PluginContentHost 会被销毁/重建，但只要 plugin.id 稳定，
//     新建的 PluginContentHost 会重新懒创建 viewModel（这是预期行为）
// - .onAppear 触发 makeViewModel()，保证 Plugin 真正显示时才创建 viewModel
// - @ObservedObject manager 让 Tab 切换时自动触发 View 重建
// - v41 Task 10: PluginTabBar 用 GeometryReader + PreferenceKey 上报每个 tab 的 frame
//   到名为 "panelSpace" 的坐标系（父级 MainLauncherView 定义），让 DynamicPointer
//   知道每个 tab 的 midX 位置，从而把箭头指向当前激活的 tab
import SwiftUI
import NovaLaunchKit

// MARK: - Tab Frame PreferenceKey（v41 Task 10：上报 tab 位置给父级）

/// 上报每个 Tab 按钮在 panelSpace 坐标系中的 frame
/// - key: plugin.id
/// - value: CGRect（在父级 .coordinateSpace(name: "panelSpace") 中的位置）
public struct TabFramePreferenceKey: PreferenceKey {
    public static var defaultValue: [String: CGRect] = [:]
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        // 同 id 后值覆盖前值（最新一次 GeometryReader 测量生效）
        value.merge(nextValue()) { _, new in new }
    }
}

/// 动态 Tab 视图：根据 ViewPluginManager.plugins 渲染当前激活 Plugin 的内容
/// 设计：每个 Tab 独立持有 viewModel（避免重建），选中时创建
@MainActor
public struct PluginTabView: View {
    @ObservedObject public var manager: ViewPluginManager

    public init(manager: ViewPluginManager) {
        self.manager = manager
    }

    public var body: some View {
        if let active = manager.activePlugin {
            PluginContentHost(plugin: active)
        } else {
            VStack {
                Image(systemName: "square.dashed")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("暂无可用插件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 单个 Plugin 内容宿主：持有 viewModel 生命周期
@MainActor
private struct PluginContentHost: View {
    let plugin: any ViewPlugin
    @State private var viewModel: (any AppListViewModelProtocol)?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                plugin.makeView(viewModel: viewModel)
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = plugin.makeViewModel()
            }
        }
    }
}

/// Tab 切换条（顶部或侧边）
@MainActor
public struct PluginTabBar: View {
    @ObservedObject public var manager: ViewPluginManager

    public init(manager: ViewPluginManager) {
        self.manager = manager
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(manager.plugins, id: \.id) { plugin in
                Button(action: {
                    manager.activePluginID = plugin.id
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: plugin.iconName)
                        Text(plugin.displayName)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        manager.activePluginID == plugin.id
                            ? plugin.accentColor.opacity(0.2)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .foregroundStyle(
                        manager.activePluginID == plugin.id
                            ? plugin.accentColor
                            : .secondary
                    )
                }
                .buttonStyle(.plain)
                // 上报 tab frame 到父级（用于 DynamicPointer 跟随）
                // 用 panelSpace 坐标系（父级 MainLauncherView 定义），
                // 父级根据 frames[activePluginID].midX 算出箭头 x 坐标
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TabFramePreferenceKey.self,
                            value: [plugin.id: geo.frame(in: .named("panelSpace"))]
                        )
                    }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
