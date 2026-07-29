import Foundation
import Combine

// MARK: - AnalyticsService

/// 使用统计分析服务：记录启动频率 + AI 推荐分数
/// Phase 3 核心：时间衰减算法
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let persistence = PersistenceService.shared
    private var records: [String: LaunchRecord] = [:]
    private let queue = DispatchQueue(label: "com.novalaunch.analytics", qos: .utility)

    private init() {
        records = persistence.loadAnalytics()
    }

    // MARK: - Record Launch

    func recordLaunch(for item: ApplicationItem) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var record = self.records[item.bundleIdentifier] ?? LaunchRecord(
                bundleIdentifier: item.bundleIdentifier,
                launchCount: 0,
                lastLaunchedDate: Date()
            )
            record.record()
            self.records[item.bundleIdentifier] = record
            self.persistence.saveAnalytics(self.records)
        }
    }

    // MARK: - AI Recommendation Score

    /// 时间衰减推荐分数
    /// 公式：Score = Log(点击次数) / (当前时间 - 最后点击时间 + 1)
    func recommendationScore(for item: ApplicationItem) -> Double {
        let record = records[item.bundleIdentifier]
        let hits = Double(max(1, record?.launchCount ?? 0))
        let lastLaunch = record?.lastLaunchedDate ?? item.createdAt
        let intervalSeconds = max(1, Date().timeIntervalSince(lastLaunch))
        let score = log(hits) / log(intervalSeconds / 3600.0 + 2.0)
        return min(max(score, 0), 100)
    }

    /// 带 LaunchRecord 和所有应用的推荐分数计算
    func recommendationScore(for record: LaunchRecord, allItems: [ApplicationItem]) -> Double {
        let hits = Double(max(1, record.launchCount))
        let intervalSeconds = max(1, Date().timeIntervalSince(record.lastLaunchedDate))
        return log(hits) / log(intervalSeconds / 3600.0 + 2.0)
    }

    // MARK: - Ranked Recommendations

    func topRecommendedItems(count: Int = 10, from allItems: [ApplicationItem]) -> [ApplicationItem] {
        var results: [(LaunchRecord, ApplicationItem)] = []
        for (bundleID, record) in records {
            if let item = allItems.first(where: { $0.bundleIdentifier == bundleID }) {
                results.append((record, item))
            }
        }
        results.sort {
            recommendationScore(for: $0.0, allItems: allItems) >
            recommendationScore(for: $1.0, allItems: allItems)
        }
        return results.prefix(count).map { $0.1 }
    }

    // MARK: - Statistics

    var totalLaunches: Int {
        records.values.reduce(0) { $0 + $1.launchCount }
    }

    func launchCount(for bundleID: String) -> Int {
        records[bundleID]?.launchCount ?? 0
    }

    func lastLaunched(for bundleID: String) -> Date? {
        records[bundleID]?.lastLaunchedDate
    }
}
