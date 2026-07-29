// 整体搬迁自 NovaLaunch/Core/Services/SearchService.swift
// 唯一变化：所有声明加 public，String 扩展已抽出到 String+Pinyin.swift
import Foundation
import Combine

// MARK: - SearchResult

public struct SearchResult: Identifiable, Sendable {
    public let id = UUID()
    public let item: ApplicationItem
    public let priority: MatchPriority

    public enum MatchPriority: Int, Comparable, Sendable {
        case exact = 0
        case prefix = 1
        case pinyinInitial = 2
        case pinyinFull = 3
        case fuzzy = 4

        public static func < (lhs: MatchPriority, rhs: MatchPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

// MARK: - SearchService

/// 智能搜索引擎：精准匹配 → 前缀匹配 → 拼音首字母 → 拼音全拼 → 模糊容错
public final class SearchService: @unchecked Sendable {
    public static let shared = SearchService()
    private init() {}

    private let fuzzyThreshold = 2

    public func search(query: String, in items: [ApplicationItem]) -> [ApplicationItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }

        var results: [SearchResult] = []

        for item in items {
            let name = item.displayName.lowercased()
            let pinyin = item.displayName.toPinyinString().lowercased()
            let initials = item.displayName.toPinyinInitialsString().lowercased()

            // 优先级 0：精准包含
            if name.contains(q) {
                results.append(SearchResult(item: item, priority: .exact))
                continue
            }
            // 优先级 1：前缀匹配
            if name.hasPrefix(q) || initials.hasPrefix(q) {
                results.append(SearchResult(item: item, priority: .prefix))
                continue
            }
            // 优先级 2：拼音首字母缩写匹配
            if initials.contains(q) {
                results.append(SearchResult(item: item, priority: .pinyinInitial))
                continue
            }
            // 优先级 3：全拼匹配
            if pinyin.contains(q) {
                results.append(SearchResult(item: item, priority: .pinyinFull))
                continue
            }
            // 优先级 4：模糊编辑距离容错
            if editDistance(q, to: initials) <= fuzzyThreshold ||
               editDistance(q, to: name) <= fuzzyThreshold {
                results.append(SearchResult(item: item, priority: .fuzzy))
                continue
            }
        }

        return results
            .sorted { $0.priority < $1.priority }
            .map(\.item)
    }

    // MARK: - Levenshtein 编辑距离（纯 Swift 实现，无第三方库）

    private func editDistance(_ s1: String, to s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[m][n]
    }
}
