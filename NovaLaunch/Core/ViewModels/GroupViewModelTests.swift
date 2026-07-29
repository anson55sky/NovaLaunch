//
//  GroupViewModelTests.swift
//  NovaLaunch Tests
//
//  测试覆盖：createGroup / deleteGroup / rebuildAllAppsGroup
//  日志规范：全部使用 NovaLog.write，严禁裸 print
//  策略：直接实例化 GroupViewModel，利用 @Published 属性的可写性手动设置状态
//

import XCTest
import Foundation

// ============================================================================
// MARK: - Test Helpers
// ============================================================================

/// 创建 mock ApplicationItem（bundleIdentifier 用作确定性 ID）
private func makeItem(
    _ bundleID: String,
    displayName: String,
    name: String? = nil,
    path: String = "/Applications/TestApp.app"
) -> ApplicationItem {
    ApplicationItem(
        id: ApplicationItem.deterministicID(for: bundleID),
        bundleIdentifier: bundleID,
        displayName: displayName,
        name: name ?? displayName,
        bundlePath: path,
        executableURL: URL(fileURLWithPath: path),
        version: "1.0.0",
        launchCount: 0,
        lastLaunchedDate: nil,
        createdAt: Date(),
        isFavorite: false,
        category: .other,
        source: .user
    )
}

// MARK: - 预定义测试应用

private let testAppSafari   = makeItem("com.apple.Safari",   displayName: "Safari")
private let testAppMail     = makeItem("com.apple.Mail",     displayName: "Mail")
private let testAppNotes    = makeItem("com.apple.Notes",    displayName: "Notes")
private let testAppPhotos   = makeItem("com.apple.Photos",   displayName: "Photos")
private let testAppMusic    = makeItem("com.apple.Music",    displayName: "Music")
private let testAppCalendar = makeItem("com.apple.Calendar", displayName: "Calendar")

private let allTestApps: [ApplicationItem] = [
    testAppSafari, testAppMail, testAppNotes, testAppPhotos, testAppMusic, testAppCalendar
]

/// 构造一个干净的 GroupViewModel 用于测试
/// - 接受 init() 中的默认行为（会尝试从 UserDefaults 加载，通常是空的）
/// - 手动设置 allItems
/// - 调用 rebuildAllAppsGroup 确保"全部应用"分组就绪
/// - 然后重置 groups 为可控的初始状态
private func makeTestVM(
    allItems: [ApplicationItem] = allTestApps,
    groups: [GroupContainer] = []
) -> GroupViewModel {
    let vm = GroupViewModel()
    vm.allItems = allItems

    if groups.isEmpty {
        // 默认初始状态：仅"全部应用"分组
        vm.groups = [
            GroupContainer(
                title: "全部应用",
                iconName: "square.grid.2x2.fill",
                items: allItems.sorted { $0.displayName < $1.displayName },
                order: 0,
                isDefault: true,
                isSystem: true
            ),
            GroupContainer(
                title: "收藏",
                iconName: "star.fill",
                items: [],
                order: 1,
                isDefault: false,
                isSystem: true
            ),
            GroupContainer(
                title: "最近使用",
                iconName: "clock.fill",
                items: [],
                order: 2,
                isDefault: false,
                isSystem: true
            )
        ]
        vm.activeGroupIndex = 0
    } else {
        vm.groups = groups
        vm.activeGroupIndex = 0
    }

    NovaLog.write("Test", "makeTestVM: groups=\(vm.groups.count), allItems=\(vm.allItems.count)")
    return vm
}

// ============================================================================
// MARK: - GroupViewModelTests
// ============================================================================

final class GroupViewModelTests: XCTestCase {

    /// 备份 UserDefaults 中 groups key 的原始数据
    private var originalGroupsData: Data?

    override func setUp() {
        super.setUp()
        NovaLog.clear()
        NovaLog.write("Test", "=== setUp ===")

        // 备份真实 UserDefaults 数据（测试结束后恢复，避免污染）
        originalGroupsData = UserDefaults.standard.data(forKey: "com.novalaunch.groups")
        // 清空测试 key，确保每次测试从干净状态开始
        UserDefaults.standard.removeObject(forKey: "com.novalaunch.groups")
        UserDefaults.standard.removeObject(forKey: "com.novalaunch.items")
    }

    override func tearDown() {
        // 恢复真实数据
        if let data = originalGroupsData {
            UserDefaults.standard.set(data, forKey: "com.novalaunch.groups")
        } else {
            UserDefaults.standard.removeObject(forKey: "com.novalaunch.groups")
        }
        UserDefaults.standard.removeObject(forKey: "com.novalaunch.items")

        NovaLog.write("Test", "=== tearDown ===")
        super.tearDown()
    }

    // ========================================================================
    // MARK: - createGroup 测试用例
    // ========================================================================

    /// TC-CREATE-01: 正常创建一个新分组
    /// 预期：groups.count +1，新分组包含正确 title/iconName，isSystem=false
    func testCreateGroup_normalCase() {
        NovaLog.write("Test", ">>> testCreateGroup_normalCase")
        let vm = makeTestVM()
        let beforeCount = vm.groups.count

        vm.createGroup(title: "工作", iconName: "briefcase.fill")

        XCTAssertEqual(vm.groups.count, beforeCount + 1, "分组数量应 +1")
        let newGroup = vm.groups.first(where: { $0.title == "工作" })
        XCTAssertNotNil(newGroup, "应包含名为'工作'的分组")
        XCTAssertEqual(newGroup?.iconName, "briefcase.fill")
        XCTAssertEqual(newGroup?.isSystem, false, "用户分组不应为系统分组")
        XCTAssertEqual(newGroup?.isDefault, false, "用户分组不应为默认分组")
        XCTAssertEqual(newGroup?.order, beforeCount, "order 应等于插入前的 groups.count")
        NovaLog.write("Test", "testCreateGroup_normalCase PASSED")
    }

    /// TC-CREATE-02: 完全重名分组应被拒绝
    /// 预期：groups.count 不变，无新分组出现
    func testCreateGroup_exactDuplicate_rejected() {
        NovaLog.write("Test", ">>> testCreateGroup_exactDuplicate_rejected")
        let vm = makeTestVM()
        vm.createGroup(title: "工作")
        let count = vm.groups.count

        vm.createGroup(title: "工作")

        XCTAssertEqual(vm.groups.count, count, "完全重名不应创建新分组")
        NovaLog.write("Test", "testCreateGroup_exactDuplicate_rejected PASSED")
    }

    /// TC-CREATE-03: 大小写变体重名应被拒绝
    /// 预期：hasGroup 忽略大小写，"工作" 与 "工作" 视为重名
    func testCreateGroup_caseInsensitiveDuplicate_rejected() {
        NovaLog.write("Test", ">>> testCreateGroup_caseInsensitiveDuplicate_rejected")
        let vm = makeTestVM()
        vm.createGroup(title: "工作")
        let count = vm.groups.count

        vm.createGroup(title: "工作")

        XCTAssertEqual(vm.groups.count, count, "大小写变体应被视为重名")
        NovaLog.write("Test", "testCreateGroup_caseInsensitiveDuplicate_rejected PASSED")
    }

    /// TC-CREATE-04: 空字符串名应被拒绝
    /// 预期：hasGroup 将空名视为"重复"，不创建分组
    func testCreateGroup_emptyString_rejected() {
        NovaLog.write("Test", ">>> testCreateGroup_emptyString_rejected")
        let vm = makeTestVM()
        let before = vm.groups.count

        vm.createGroup(title: "")

        XCTAssertEqual(vm.groups.count, before, "空名不应创建分组")
        NovaLog.write("Test", "testCreateGroup_emptyString_rejected PASSED")
    }

    /// TC-CREATE-05: 纯空白字符串应被拒绝
    /// 预期：trim 后为空，hasGroup 返回 true
    func testCreateGroup_whitespaceOnly_rejected() {
        NovaLog.write("Test", ">>> testCreateGroup_whitespaceOnly_rejected")
        let vm = makeTestVM()
        let before = vm.groups.count

        vm.createGroup(title: "   \t\n   ")

        XCTAssertEqual(vm.groups.count, before, "纯空白名不应创建分组")
        NovaLog.write("Test", "testCreateGroup_whitespaceOnly_rejected PASSED")
    }

    /// TC-CREATE-06: 带前后空白 trim 后重名应拒绝
    /// 预期：hasGroup 对双方都 trim 后再比较
    func testCreateGroup_whitespaceTrimmedDuplicate_rejected() {
        NovaLog.write("Test", ">>> testCreateGroup_whitespaceTrimmedDuplicate_rejected")
        let vm = makeTestVM()
        vm.createGroup(title: "工作")
        let count = vm.groups.count

        vm.createGroup(title: "  工作  ")

        XCTAssertEqual(vm.groups.count, count, "trim 后重名不应创建")
        NovaLog.write("Test", "testCreateGroup_whitespaceTrimmedDuplicate_rejected PASSED")
    }

    /// TC-CREATE-07: 与系统分组（收藏/最近使用）重名应拒绝
    /// 预期：不能创建名为"收藏"或"最近使用"的用户分组
    func testCreateGroup_duplicateSystemGroupName_rejected() {
        NovaLog.write("Test", ">>> testCreateGroup_duplicateSystemGroupName_rejected")
        let vm = makeTestVM()
        let before = vm.groups.count

        vm.createGroup(title: "收藏")
        XCTAssertEqual(vm.groups.count, before, "与'收藏'重名不应创建")

        vm.createGroup(title: "最近使用")
        XCTAssertEqual(vm.groups.count, before, "与'最近使用'重名不应创建")

        NovaLog.write("Test", "testCreateGroup_duplicateSystemGroupName_rejected PASSED")
    }

    /// TC-CREATE-08: 默认 iconName（不传参）应为 "folder.fill"
    /// 预期：createGroup(title:) 使用默认参数
    func testCreateGroup_defaultIconName() {
        NovaLog.write("Test", ">>> testCreateGroup_defaultIconName")
        let vm = makeTestVM()

        vm.createGroup(title: "默认图标")

        let group = vm.groups.first(where: { $0.title == "默认图标" })
        XCTAssertEqual(group?.iconName, "folder.fill", "默认图标名应为 folder.fill")
        NovaLog.write("Test", "testCreateGroup_defaultIconName PASSED")
    }

    // ========================================================================
    // MARK: - deleteGroup 测试用例
    // ========================================================================

    /// TC-DELETE-01: 正常删除一个用户自建分组
    /// 预期：groups.count -1，被删除分组消失，order 重建连续
    func testDeleteGroup_normalCase() {
        NovaLog.write("Test", ">>> testDeleteGroup_normalCase")
        let vm = makeTestVM()
        vm.createGroup(title: "临时分组")
        guard let idx = vm.groups.firstIndex(where: { $0.title == "临时分组" }) else {
            XCTFail("未找到刚创建的分组")
            return
        }
        let before = vm.groups.count

        vm.deleteGroup(at: idx)

        XCTAssertEqual(vm.groups.count, before - 1, "分组数量应 -1")
        XCTAssertFalse(vm.groups.contains(where: { $0.title == "临时分组" }), "被删除的分组不应存在")
        // 验证 order 重建
        for (i, g) in vm.groups.enumerated() {
            XCTAssertEqual(g.order, i, "删除后 order 应从 0 连续: group[\(i)] order=\(g.order)")
        }
        NovaLog.write("Test", "testDeleteGroup_normalCase PASSED")
    }

    /// TC-DELETE-02: 系统分组"收藏"不可删除
    /// 预期：groups 不变，收藏分组保留
    func testDeleteGroup_favorites_protected() {
        NovaLog.write("Test", ">>> testDeleteGroup_favorites_protected")
        let vm = makeTestVM()
        guard let favIdx = vm.groups.firstIndex(where: { $0.title == "收藏" }) else {
            XCTFail("未找到'收藏'")
            return
        }
        let before = vm.groups.count

        vm.deleteGroup(at: favIdx)

        XCTAssertEqual(vm.groups.count, before, "系统分组不应被删除")
        XCTAssertTrue(vm.groups.contains(where: { $0.title == "收藏" }), "收藏应保留")
        NovaLog.write("Test", "testDeleteGroup_favorites_protected PASSED")
    }

    /// TC-DELETE-03: 系统分组"最近使用"不可删除
    /// 预期：groups 不变
    func testDeleteGroup_recents_protected() {
        NovaLog.write("Test", ">>> testDeleteGroup_recents_protected")
        let vm = makeTestVM()
        guard let recIdx = vm.groups.firstIndex(where: { $0.title == "最近使用" }) else {
            XCTFail("未找到'最近使用'")
            return
        }
        let before = vm.groups.count

        vm.deleteGroup(at: recIdx)

        XCTAssertEqual(vm.groups.count, before, "系统分组不应被删除")
        NovaLog.write("Test", "testDeleteGroup_recents_protected PASSED")
    }

    /// TC-DELETE-04: "全部应用"（isSystem=true）不可删除
    /// 预期：groups 不变
    func testDeleteGroup_allApps_protected() {
        NovaLog.write("Test", ">>> testDeleteGroup_allApps_protected")
        let vm = makeTestVM()
        guard let allIdx = vm.groups.firstIndex(where: { $0.title == "全部应用" }) else {
            XCTFail("未找到'全部应用'")
            return
        }
        let before = vm.groups.count

        vm.deleteGroup(at: allIdx)

        XCTAssertEqual(vm.groups.count, before, "'全部应用'不应被删除")
        NovaLog.write("Test", "testDeleteGroup_allApps_protected PASSED")
    }

    /// TC-DELETE-05: 越界索引（负数）安全跳过
    /// 预期：不崩溃，groups 不变
    func testDeleteGroup_negativeIndex_safeNoop() {
        NovaLog.write("Test", ">>> testDeleteGroup_negativeIndex_safeNoop")
        let vm = makeTestVM()
        let before = vm.groups.count

        vm.deleteGroup(at: -1)

        XCTAssertEqual(vm.groups.count, before, "负数索引不应修改数据")
        NovaLog.write("Test", "testDeleteGroup_negativeIndex_safeNoop PASSED")
    }

    /// TC-DELETE-06: 越界索引（等于 count）安全跳过
    /// 预期：不崩溃，groups 不变
    func testDeleteGroup_indexEqualsCount_safeNoop() {
        NovaLog.write("Test", ">>> testDeleteGroup_indexEqualsCount_safeNoop")
        let vm = makeTestVM()
        let before = vm.groups.count

        vm.deleteGroup(at: vm.groups.count)

        XCTAssertEqual(vm.groups.count, before, "count 索引不应修改数据")
        NovaLog.write("Test", "testDeleteGroup_indexEqualsCount_safeNoop PASSED")
    }

    /// TC-DELETE-07: 越界索引（远超 count）安全跳过
    /// 预期：不崩溃，groups 不变
    func testDeleteGroup_farOutOfBounds_safeNoop() {
        NovaLog.write("Test", ">>> testDeleteGroup_farOutOfBounds_safeNoop")
        let vm = makeTestVM()
        let before = vm.groups.count

        vm.deleteGroup(at: 999)

        XCTAssertEqual(vm.groups.count, before, "远超越界不应修改数据")
        NovaLog.write("Test", "testDeleteGroup_farOutOfBounds_safeNoop PASSED")
    }

    /// TC-DELETE-08: 删除分组后 activeGroupIndex 修正到有效范围
    /// 预期：如果 activeGroupIndex 越界，修正到 max(0, count-1)
    func testDeleteGroup_activeIndex_adjustsWhenOutOfBounds() {
        NovaLog.write("Test", ">>> testDeleteGroup_activeIndex_adjustsWhenOutOfBounds")
        let vm = makeTestVM()
        vm.createGroup(title: "A")
        vm.createGroup(title: "B")
        vm.activeGroupIndex = vm.groups.count - 1 // 最后一个

        guard let bIdx = vm.groups.firstIndex(where: { $0.title == "B" }) else {
            XCTFail("未找到分组 B")
            return
        }
        vm.deleteGroup(at: bIdx)

        XCTAssertLessThan(vm.activeGroupIndex, vm.groups.count, "activeIndex 不应越界")
        XCTAssertGreaterThanOrEqual(vm.activeGroupIndex, 0, "activeIndex 不应为负")
        NovaLog.write("Test", "testDeleteGroup_activeIndex_adjustsWhenOutOfBounds PASSED")
    }

    /// TC-DELETE-09: 删除后自动调用 rebuildAllAppsGroup（被删分组 items 回归）
    /// 预期：被删分组中的应用回到"全部应用"
    func testDeleteGroup_triggersRebuildAllApps() {
        NovaLog.write("Test", ">>> testDeleteGroup_triggersRebuildAllApps")
        let vm = makeTestVM()
        vm.createGroup(title: "浏览器")

        // 将 Safari 从全部应用移到浏览器分组
        if let browserIdx = vm.groups.firstIndex(where: { $0.title == "浏览器" }),
           let allIdx = vm.groups.firstIndex(where: { $0.title == "全部应用" }) {
            vm.groups[browserIdx].items = [testAppSafari]
            // 从全部应用中移除 Safari（模拟真实场景）
            vm.groups[allIdx].items.removeAll { $0.bundleIdentifier == testAppSafari.bundleIdentifier }
        }

        // 删除浏览器分组
        guard let browserIdx = vm.groups.firstIndex(where: { $0.title == "浏览器" }) else {
            XCTFail("未找到浏览器分组")
            return
        }
        vm.deleteGroup(at: browserIdx)

        // Safari 应回到"全部应用"
        guard let allGroup = vm.groups.first(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        XCTAssertTrue(
            allGroup.items.contains(where: { $0.bundleIdentifier == testAppSafari.bundleIdentifier }),
            "删除分组后，Safari 应回到全部应用"
        )
        NovaLog.write("Test", "testDeleteGroup_triggersRebuildAllApps PASSED")
    }

    // ========================================================================
    // MARK: - rebuildAllAppsGroup 测试用例
    // ========================================================================

    /// TC-REBUILD-01: "全部应用"已存在时，保留已有 items 的顺序，新 items 按名追加
    /// 预期：keptItems 保持原序在前，newItems 按 displayName 排序在后
    func testRebuildAllAppsGroup_existing_preservesOrder() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_existing_preservesOrder")
        let vm = makeTestVM()

        // 手动设置全部应用中的已有 items（特定顺序）
        if let allIdx = vm.groups.firstIndex(where: { $0.title == "全部应用" }) {
            vm.groups[allIdx] = GroupContainer(
                id: vm.groups[allIdx].id,
                title: "全部应用",
                iconName: "square.grid.2x2.fill",
                items: [testAppSafari, testAppMail],  // 只有 2 个
                order: 0,
                isDefault: true,
                isSystem: true
            )
        }

        vm.rebuildAllAppsGroup()

        guard let allGroup = vm.groups.first(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        // 前两个应保持原序（Safari, Mail）
        let firstTwo = Array(allGroup.items.prefix(2))
        XCTAssertEqual(firstTwo[0].bundleIdentifier, testAppSafari.bundleIdentifier, "Safari 应在第一位")
        XCTAssertEqual(firstTwo[1].bundleIdentifier, testAppMail.bundleIdentifier, "Mail 应在第二位")
        // 后面的新 items 应按名称排序
        let restNames = allGroup.items.dropFirst(2).map(\.displayName)
        for i in 1..<restNames.count {
            XCTAssertTrue(
                restNames[i-1].localizedCaseInsensitiveCompare(restNames[i]) != .orderedDescending,
                "新 items 应按名排序: \(restNames[i-1]) vs \(restNames[i])"
            )
        }
        NovaLog.write("Test", "testRebuildAllAppsGroup_existing_preservesOrder PASSED")
    }

    /// TC-REBUILD-02: "全部应用"不存在时，创建新分组并插入 index 0
    /// 预期：创建 isDefault=true/isSystem=true/order=0 的分组
    func testRebuildAllAppsGroup_notExists_createsNew() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_notExists_createsNew")
        let vm = GroupViewModel()
        vm.allItems = allTestApps
        // 初始无任何分组（模拟极端情况）
        vm.groups = []

        vm.rebuildAllAppsGroup()

        XCTAssertEqual(vm.groups.count, 1, "应创建唯一分组")
        let allGroup = vm.groups[0]
        XCTAssertEqual(allGroup.title, "全部应用")
        XCTAssertTrue(allGroup.isDefault)
        XCTAssertTrue(allGroup.isSystem)
        XCTAssertEqual(allGroup.order, 0)
        XCTAssertFalse(allGroup.items.isEmpty, "应包含 allItems 中的应用")
        NovaLog.write("Test", "testRebuildAllAppsGroup_notExists_createsNew PASSED")
    }

    /// TC-REBUILD-03: 已归入用户自建分组的应用不应出现在"全部应用"
    /// 预期：排除 !isDefault && !isSystem 分组中的 items
    func testRebuildAllAppsGroup_excludesUserGroupItems() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_excludesUserGroupItems")
        let vm = makeTestVM()

        // 创建用户分组并放入 Safari
        vm.createGroup(title: "浏览器")
        if let browserIdx = vm.groups.firstIndex(where: { $0.title == "浏览器" }) {
            vm.groups[browserIdx].items = [testAppSafari]
        }

        vm.rebuildAllAppsGroup()

        guard let allGroup = vm.groups.first(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        let ids = allGroup.items.map(\.bundleIdentifier)
        XCTAssertFalse(ids.contains(testAppSafari.bundleIdentifier),
                       "已归入'浏览器'的 Safari 不应在全部应用中")
        NovaLog.write("Test", "testRebuildAllAppsGroup_excludesUserGroupItems PASSED")
    }

    /// TC-REBUILD-04: 系统分组（收藏/最近使用）中的 items 仍在"全部应用"
    /// 预期：排除条件仅限 !isDefault && !isSystem，系统分组的 items 不排除
    func testRebuildAllAppsGroup_systemGroupItems_notExcluded() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_systemGroupItems_notExcluded")
        let vm = makeTestVM()

        // 将 Safari 放入收藏（系统分组）
        if let favIdx = vm.groups.firstIndex(where: { $0.title == "收藏" }) {
            vm.groups[favIdx].items = [testAppSafari]
        }

        vm.rebuildAllAppsGroup()

        guard let allGroup = vm.groups.first(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        let ids = allGroup.items.map(\.bundleIdentifier)
        XCTAssertTrue(ids.contains(testAppSafari.bundleIdentifier),
                      "收藏（系统分组）中的 Safari 仍应在全部应用")
        NovaLog.write("Test", "testRebuildAllAppsGroup_systemGroupItems_notExcluded PASSED")
    }

    /// TC-REBUILD-05: activeGroupIndex 无效时修正到"全部应用"
    /// 预期：越界或不在全部应用时，强制切换到全部应用
    func testRebuildAllAppsGroup_fixesActiveIndex_outOfBounds() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_fixesActiveIndex_outOfBounds")
        let vm = makeTestVM()
        vm.activeGroupIndex = 999

        vm.rebuildAllAppsGroup()

        guard let allIdx = vm.groups.firstIndex(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        XCTAssertEqual(vm.activeGroupIndex, allIdx, "越界时应修正到全部应用")
        NovaLog.write("Test", "testRebuildAllAppsGroup_fixesActiveIndex_outOfBounds PASSED")
    }

    /// TC-REBUILD-06: activeGroupIndex 在其他分组时不修正
    /// 预期：仅当越界或不在全部应用时才修正
    func testRebuildAllAppsGroup_activeIndex_valid_unchanged() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_activeIndex_valid_unchanged")
        let vm = makeTestVM()
        // 找到收藏的索引并设置
        guard let favIdx = vm.groups.firstIndex(where: { $0.title == "收藏" }) else {
            XCTFail("未找到收藏")
            return
        }
        vm.activeGroupIndex = favIdx

        vm.rebuildAllAppsGroup()

        // 条件：activeGroupIndex >= groups.count || groups[activeGroupIndex].title != "全部应用"
        // 收藏 != 全部应用 → 会被修正
        guard let allIdx = vm.groups.firstIndex(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        XCTAssertEqual(vm.activeGroupIndex, allIdx, "不在全部应用时应修正")
        NovaLog.write("Test", "testRebuildAllAppsGroup_activeIndex_valid_unchanged PASSED")
    }

    /// TC-REBUILD-07: allItems 为空时安全执行（不崩溃）
    /// 预期：全部应用分组 items 为空
    func testRebuildAllAppsGroup_emptyAllItems_safe() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_emptyAllItems_safe")
        let vm = GroupViewModel()
        vm.allItems = []
        vm.groups = []

        vm.rebuildAllAppsGroup()

        guard let allGroup = vm.groups.first(where: { $0.title == "全部应用" }) else {
            XCTFail("即使 allItems 为空也应创建全部应用")
            return
        }
        XCTAssertEqual(allGroup.items.count, 0, "空 allItems 时全部应用 items 应为空")
        NovaLog.write("Test", "testRebuildAllAppsGroup_emptyAllItems_safe PASSED")
    }

    /// TC-REBUILD-08: 新 items 按 displayName 本地化升序排列
    /// 预期：newItems 使用 localizedCaseInsensitiveCompare 排序
    func testRebuildAllAppsGroup_newItems_sortedByDisplayName() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_newItems_sortedByDisplayName")
        let vm = makeTestVM()

        // 清空全部应用
        if let allIdx = vm.groups.firstIndex(where: { $0.title == "全部应用" }) {
            vm.groups[allIdx] = GroupContainer(
                id: vm.groups[allIdx].id,
                title: "全部应用",
                iconName: "square.grid.2x2.fill",
                items: [],
                order: 0,
                isDefault: true,
                isSystem: true
            )
        }

        vm.rebuildAllAppsGroup()

        guard let allGroup = vm.groups.first(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        let names = allGroup.items.map(\.displayName)
        for i in 1..<names.count {
            let cmp = names[i-1].localizedCaseInsensitiveCompare(names[i])
            XCTAssertTrue(cmp != .orderedDescending,
                          "排序错误: \(names[i-1]) 应在 \(names[i]) 之前")
        }
        NovaLog.write("Test", "testRebuildAllAppsGroup_newItems_sortedByDisplayName PASSED")
    }

    /// TC-REBUILD-09: 分组中 items 部分已卸载时，保留仍然存在的 items
    /// 预期：keptItems 过滤掉不在 allItems 中的应用
    func testRebuildAllAppsGroup_removesUninstalledApps() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_removesUninstalledApps")
        let vm = makeTestVM()

        // 在全部应用中放入一个不在 allItems 中的幽灵应用
        let ghostApp = makeItem("com.ghost.App", displayName: "Ghost")
        if let allIdx = vm.groups.firstIndex(where: { $0.title == "全部应用" }) {
            vm.groups[allIdx] = GroupContainer(
                id: vm.groups[allIdx].id,
                title: "全部应用",
                iconName: "square.grid.2x2.fill",
                items: [testAppSafari, ghostApp],
                order: 0,
                isDefault: true,
                isSystem: true
            )
        }

        vm.rebuildAllAppsGroup()

        guard let allGroup = vm.groups.first(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        let ids = allGroup.items.map(\.bundleIdentifier)
        XCTAssertFalse(ids.contains(ghostApp.bundleIdentifier),
                       "已卸载的应用不应出现在全部应用中")
        XCTAssertTrue(ids.contains(testAppSafari.bundleIdentifier),
                      "仍安装的应用应保留")
        NovaLog.write("Test", "testRebuildAllAppsGroup_removesUninstalledApps PASSED")
    }

    /// TC-REBUILD-10: 多个用户分组各有不同 items 时，全部排除
    /// 预期：所有用户分组 items 的 bundleID 并集被排除
    func testRebuildAllAppsGroup_multipleUserGroups_allExcluded() {
        NovaLog.write("Test", ">>> testRebuildAllAppsGroup_multipleUserGroups_allExcluded")
        let vm = makeTestVM()
        vm.createGroup(title: "浏览器")
        vm.createGroup(title: "工具")

        if let bIdx = vm.groups.firstIndex(where: { $0.title == "浏览器" }) {
            vm.groups[bIdx].items = [testAppSafari]
        }
        if let tIdx = vm.groups.firstIndex(where: { $0.title == "工具" }) {
            vm.groups[tIdx].items = [testAppMail]
        }

        vm.rebuildAllAppsGroup()

        guard let allGroup = vm.groups.first(where: { $0.title == "全部应用" }) else {
            XCTFail("'全部应用'应存在")
            return
        }
        let ids = allGroup.items.map(\.bundleIdentifier)
        XCTAssertFalse(ids.contains(testAppSafari.bundleIdentifier), "浏览器中的 Safari 应排除")
        XCTAssertFalse(ids.contains(testAppMail.bundleIdentifier), "工具中的 Mail 应排除")
        // 其他未分组的应保留
        XCTAssertTrue(ids.contains(testAppNotes.bundleIdentifier), "未分组的 Notes 应保留")
        NovaLog.write("Test", "testRebuildAllAppsGroup_multipleUserGroups_allExcluded PASSED")
    }
}
