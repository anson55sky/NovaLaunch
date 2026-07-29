// 整体搬迁自 NovaLaunch/Core/Models/ApplicationItem.swift
// 唯一变化：所有声明加 public，加 Sendable
import Foundation
import SwiftUI
import AppKit

// MARK: - ApplicationItem

/// 应用程序数据模型：描述一个可被 NovaLaunch 索引与展示的 .app 条目
public struct ApplicationItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let bundleIdentifier: String
    public let displayName: String
    public let name: String
    public let bundlePath: String
    public let executableURL: URL?
    public let version: String
    public let launchCount: Int
    public let lastLaunchedDate: Date?
    public let createdAt: Date
    public var isFavorite: Bool
    public var category: AppCategory
    public var source: AppSource

    public enum AppCategory: String, Codable, CaseIterable, Sendable {
        case productivity
        case creativity
        case developer
        case utilities
        case games
        case system
        case other
    }

    /// 应用来源：系统自带 vs 用户安装
    public enum AppSource: String, Codable, CaseIterable, Sendable {
        case system   // 系统自带
        case user     // 用户安装
    }

    public init(id: UUID = UUID(),
                bundleIdentifier: String,
                displayName: String,
                name: String,
                bundlePath: String,
                executableURL: URL? = nil,
                version: String = "1.0.0",
                launchCount: Int = 0,
                lastLaunchedDate: Date? = nil,
                createdAt: Date = Date(),
                isFavorite: Bool = false,
                category: AppCategory = .other,
                source: AppSource = .user) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.name = name
        self.bundlePath = bundlePath
        self.executableURL = executableURL
        self.version = version
        self.launchCount = launchCount
        self.lastLaunchedDate = lastLaunchedDate
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.category = category
        self.source = source
    }

    /// 是否是系统自带应用
    public var isSystemApp: Bool { source == .system }
}

// MARK: - Hashable

extension ApplicationItem {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }

    public static func == (lhs: ApplicationItem, rhs: ApplicationItem) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

// MARK: - Display Helpers

extension ApplicationItem {
    /// 通过 NSWorkspace 动态获取应用原生图标（非主线程友好）
    public func loadIcon() -> NSImage {
        let workspace = NSWorkspace.shared
        return workspace.icon(forFile: bundlePath)
    }

    /// 启动该应用
    @discardableResult
    public func launch() -> Bool {
        let url = URL(fileURLWithPath: bundlePath)
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return true
    }

    /// AI 推荐分数计算
    public var recommendationScore: Double {
        let hits = max(1, launchCount)
        let interval = max(1, Date().timeIntervalSince(lastLaunchedDate ?? createdAt))
        return log(Double(hits)) / interval
    }
}
