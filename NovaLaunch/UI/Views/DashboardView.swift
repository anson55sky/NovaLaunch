import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 统一管理工作台（v47）

/// 空状态仪表盘：搜索框为空时自动展示
/// 布局：
/// - 顶部：最近剪贴板（横向滚动）
/// - 主体：左侧 60% 活跃窗口 + 右侧 40% 浏览器标签页
struct DashboardView: View {
    @ObservedObject var dashboard: DashboardViewModel
    let onCloseLauncher: () -> Void

    // Drag reorder state
    @State private var dragSourceIndex: Int?
    @State private var dragTargetIndex: Int?
    /// "windows" or "tabs" — which list the drag belongs to
    @State private var dragList: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 顶部区域：最近剪贴板
            if !dashboard.clipboardEntries.isEmpty {
                clipboardSection
                Divider().opacity(0.15)
            }

            // 主体区域：分栏网格
            HStack(alignment: .top, spacing: 16) {
                // 左侧 60%：活跃窗口
                windowsSection
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().opacity(0.15)

                // 右侧 40%：浏览器标签页
                tabsSection
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .opacity(dashboard.isReady ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.25), value: dashboard.isReady)
    }

    // MARK: - 剪贴板区域

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("最近剪贴板")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(dashboard.clipboardEntries.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dashboard.clipboardEntries) { entry in
                        ClipboardCard(
                            entry: entry,
                            onTap: {
                                dashboard.copyToClipboard(entry)
                                onCloseLauncher()
                            },
                            onDelete: {
                                dashboard.deleteClipboardEntry(entry)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 活跃窗口区域

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("活跃窗口")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(dashboard.activeWindows.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if dashboard.activeWindows.isEmpty {
                emptyState(icon: "macwindow.badge.xmark", text: "无活跃窗口")
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(dashboard.activeWindows.enumerated()), id: \.element.id) { index, item in
                        WindowRow(
                            item: item,
                            index: index,
                            isDropTarget: dragList == "windows" && dragTargetIndex == index,
                            onActivate: {
                                dashboard.activateWindow(item)
                                onCloseLauncher()
                            },
                            onClose: {
                                dashboard.closeWindow(item)
                            },
                            onDragStart: { i in
                                dragSourceIndex = i
                                dragList = "windows"
                            },
                            onReorder: { from, to in
                                dashboard.moveWindow(from: from, to: to)
                            },
                            dragList: $dragList,
                            dragTargetIndex: $dragTargetIndex
                        )
                    }
                }
            }
        }
    }

    // MARK: - 浏览器标签区域

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("浏览器标签")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(dashboard.browserTabs.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if dashboard.browserTabs.isEmpty {
                emptyState(icon: "globe.badge.xmark", text: "无浏览器标签")
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(dashboard.browserTabs.enumerated()), id: \.element.id) { index, item in
                        TabRow(
                            item: item,
                            index: index,
                            isDropTarget: dragList == "tabs" && dragTargetIndex == index,
                            onOpen: {
                                dashboard.openTab(item)
                                onCloseLauncher()
                            },
                            onClose: {
                                dashboard.closeTab(item)
                            },
                            onDragStart: { i in
                                dragSourceIndex = i
                                dragList = "tabs"
                            },
                            onReorder: { from, to in
                                dashboard.moveTab(from: from, to: to)
                            },
                            dragList: $dragList,
                            dragTargetIndex: $dragTargetIndex
                        )
                    }
                }
            }
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.quaternary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - 剪贴板卡片

struct ClipboardCard: View {
    let entry: ClipboardEntry
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // 图片缩略图或文本图标
                if entry.type == .image, let data = entry.imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.truncatedText)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.relativeTime)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.gray.opacity(0.06))
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .padding(3)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .frame(maxWidth: 180)
    }
}

// MARK: - 窗口行

struct WindowRow: View {
    let item: PluginResultItem
    let index: Int
    var isDropTarget: Bool = false
    let onActivate: () -> Void
    let onClose: () -> Void
    var onDragStart: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    @Binding var dragList: String?
    @Binding var dragTargetIndex: Int?
    @State private var isHovered = false

    var body: some View {
        Button {
            onActivate()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? .secondary : .quaternary)
                    .frame(width: 12)
                
                iconView
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isHovered ? Color.red.opacity(0.8) : Color.clear)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered || isDropTarget ? Color.accentColor.opacity(isDropTarget ? 0.12 : 0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isDropTarget ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDropTarget)
        .onDrag {
            onDragStart?(index)
            let provider = NSItemProvider()
            provider.registerObject("\(index)" as NSString, visibility: .all)
            return provider
        }
        .onDrop(of: [.text],
                delegate: InlineReorderDelegate(
                    list: "windows",
                    targetIndex: index,
                    dragList: $dragList,
                    dragTargetIndex: $dragTargetIndex,
                    onReorder: { from, to in onReorder?(from, to) }
                ))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.icon {
        case .systemName(let name):
            Image(systemName: name)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .appBundleID(let bundleID):
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let icon = NSWorkspace.shared.icon(forFile: url?.path ?? "")
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        case .image(let nsImage):
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        }
    }
}

// MARK: - 标签页行

struct TabRow: View {
    let item: PluginResultItem
    let index: Int
    var isDropTarget: Bool = false
    let onOpen: () -> Void
    let onClose: () -> Void
    var onDragStart: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    @Binding var dragList: String?
    @Binding var dragTargetIndex: Int?
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? .secondary : .quaternary)
                    .frame(width: 12)
                
                browserIcon
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isHovered ? Color.red.opacity(0.8) : Color.clear)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered || isDropTarget ? Color.accentColor.opacity(isDropTarget ? 0.12 : 0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isDropTarget ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDropTarget)
        .onDrag {
            onDragStart?(index)
            let provider = NSItemProvider()
            provider.registerObject("\(index)" as NSString, visibility: .all)
            return provider
        }
        .onDrop(of: [.text],
                delegate: InlineReorderDelegate(
                    list: "tabs",
                    targetIndex: index,
                    dragList: $dragList,
                    dragTargetIndex: $dragTargetIndex,
                    onReorder: { from, to in onReorder?(from, to) }
                ))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private var browserIcon: some View {
        let name: String
        if item.subtitle.lowercased().contains("safari") {
            name = "safari"
        } else if item.subtitle.lowercased().contains("chrome") {
            name = "globe"
        } else if item.subtitle.lowercased().contains("arc") {
            name = "globe"
        } else {
            name = "globe"
        }
        return Image(systemName: name)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }
}

// MARK: - v121 Inline Reorder Drop Delegate

struct InlineReorderDelegate: DropDelegate {
    let list: String
    let targetIndex: Int
    @Binding var dragList: String?
    @Binding var dragTargetIndex: Int?
    let onReorder: (Int, Int) -> Void
    
    /// Track the source index from the drag item's string payload
    static private var dragSourceMap: [String: Int] = [:]

    func validateDrop(info: DropInfo) -> Bool {
        guard dragList == list else { return false }
        // Extract source index from the drag string payload
        if let str = info.itemProviders(for: [.text]).first {
            let semaphore = DispatchSemaphore(value: 0)
            var source: Int?
            str.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { (data, _) in
                if let d = data as? Data, let s = String(data: d, encoding: .utf8), let idx = Int(s) {
                    source = idx
                } else if let s = data as? String, let idx = Int(s) {
                    source = idx
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 0.1)
            if let src = source, src != targetIndex {
                Self.dragSourceMap["\(list)-\(src)"] = src
                return true
            }
        }
        return false
    }

    func dropEntered(info: DropInfo) {
        guard dragList == list else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragTargetIndex = targetIndex
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if dragTargetIndex == targetIndex { dragTargetIndex = nil }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragTargetIndex = nil
            dragList = nil
        }
        // Try to get source from the drag payload
        if let str = info.itemProviders(for: [.text]).first {
            let semaphore = DispatchSemaphore(value: 0)
            var source: Int?
            str.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { (data, _) in
                if let d = data as? Data, let s = String(data: d, encoding: .utf8), let idx = Int(s) {
                    source = idx
                } else if let s = data as? String, let idx = Int(s) {
                    source = idx
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 0.5)
            if let src = source, src != targetIndex {
                onReorder(src, targetIndex)
                return true
            }
        }
        return false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
