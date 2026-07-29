import SwiftUI

struct SearchResultView: View {
    let results: [ApplicationItem]
    let onSelect: (ApplicationItem) -> Void

    @State private var hoveredID: UUID?

    var body: some View {
        if results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("无搜索结果")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { item in
                        SearchResultRow(
                            item: item,
                            isHovered: hoveredID == item.id,
                            onSelect: { onSelect(item) }
                        )
                        .onHover { hovering in
                            hoveredID = hovering ? item.id : nil
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    let item: ApplicationItem
    let isHovered: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                AppIcon(item: item, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(item.bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                // 推荐分数
                let score = AnalyticsService.shared.recommendationScore(for: item)
                if score > 0 {
                    Text("\(Int(score))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(score > 50 ? .green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(score > 50 ? Color.green.opacity(0.15) : Color.clear)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
struct SearchResultView_Preview: PreviewProvider {
    static var previews: some View {
        SearchResultView(
            results: [
                ApplicationItem(bundleIdentifier: "com.apple.Safari",
                               displayName: "Safari",
                               name: "Safari",
                               bundlePath: "/Applications/Safari.app")
            ],
            onSelect: { _ in }
        )
    }
}
#endif
