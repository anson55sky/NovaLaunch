import Foundation
import AppKit
import SwiftUI

// MARK: - 超级剪贴板插件（v45）

/// 剪贴板历史插件
/// 功能：
/// - 后台监听 NSPasteboard 变化
/// - 存储文本/图片历史（限制 50 条）
/// - 搜索集成：输入 .clip 或直接输入文本时展示历史
/// - 选中条目按回车 → 重新写入剪贴板 + 提示"已复制"
final class ClipboardPlugin: SearchPluginProtocol {
    let id = "com.novalaunch.clipboard"
    let name = "剪贴板"
    let icon = "doc.on.clipboard"
    let keywords = ["clip", "剪贴板", "clipboard", "粘贴"]

    ///
    private var clipboardManager: ClipboardManager { ClipboardManager.shared }

    // MARK: - SearchPluginProtocol

    func search(query: String) async -> [PluginResultItem] {
        let lowerQuery = query.lowercased()
        let trimmedQuery = lowerQuery.hasPrefix(".") ? String(lowerQuery.dropFirst()) : lowerQuery

        // 如果 query 匹配关键词（如 ".clip"），返回全部历史
        let isKeywordMatch = keywords.contains(where: { trimmedQuery.hasPrefix($0.lowercased()) })

        let entries = clipboardManager.entries

        if isKeywordMatch {
            return entries.map { $0.toPluginResultItem() }
        }

        return entries.filter { entry in
            entry.searchText.lowercased().contains(lowerQuery)
        }.map { $0.toPluginResultItem() }
    }

    func handle(action: String, item: PluginResultItem) async {
        guard action == "copy" || action == "default" else { return }
        guard let entry = clipboardManager.entries.first(where: { $0.id == item.id }) else { return }
        clipboardManager.copyToClipboard(entry)
        NotificationCenter.default.post(name: .novaClipboardCopied, object: nil)
    }

    func panelView() -> AnyView? {
        AnyView(ClipboardHistoryPanel(plugin: self))
    }

    // MARK: - v47 仪表盘支持

    func getRecentEntries(limit: Int = 8) -> [ClipboardEntry] {
        Array(clipboardManager.entries.prefix(limit))
    }

    func removeEntry(byID entryID: String) {
        if let entry = clipboardManager.entries.first(where: { $0.id == entryID }) {
            clipboardManager.deleteEntry(entry)
        }
    }

    
}

// MARK: - 剪贴板条目模型

enum ClipboardEntryType: String, Codable {
    case text
    case image
}

struct ClipboardEntry: Codable, Identifiable {
    let id: String
    let type: ClipboardEntryType
    let content: String
    let imageData: Data?
    let timestamp: Date

    /// 搜索用文本
    var searchText: String {
        content
    }

    func toPluginResultItem() -> PluginResultItem {
        let icon: PluginResultItem.PluginResultIcon = type == .image
            ? .systemName("photo")
            : .systemName("doc.text")

        let timeStr = Self.relativeTimeString(from: timestamp)

        return PluginResultItem(
            id: id,
            title: type == .image ? "图片" : String(content.prefix(80)),
            subtitle: timeStr,
            icon: icon,
            pluginID: "com.novalaunch.clipboard",
            action: "copy",
            data: nil
        )
    }

    static func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}

// MARK: - 剪贴板历史面板

struct ClipboardHistoryPanel: View {
    let plugin: ClipboardPlugin
    @State private var copiedID: String?

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
                Text("剪贴板历史")
                    .font(.headline)
                Spacer()
                Text("\(plugin.getRecentEntries().count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // 列表
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(plugin.getRecentEntries().map { $0.toPluginResultItem() }) { item in
                        ClipboardRow(item: item, isCopied: copiedID == item.id) {
                            Task { @MainActor in
                                await SearchPluginManager.shared.handle(action: "copy", item: item)
                                copiedID = item.id
                                // 2 秒后清除提示
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    if copiedID == item.id { copiedID = nil }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ClipboardRow: View {
    let item: PluginResultItem
    let isCopied: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: iconSystemName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isCopied {
                    Text("已复制")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var iconSystemName: String {
        switch item.icon {
        case .systemName(let name): return name
        default: return "doc"
        }
    }
}

// MARK: - 通知

extension Notification.Name {
    static let novaClipboardCopied = Notification.Name("novaClipboardCopied")
}
