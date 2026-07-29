import Foundation

// MARK: - AppGroup Entity (Core Data 兼容)

/// 分组数据模型，同时支持 Codable（JSON/UserDefaults）和 Core Data
struct AppGroup: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var iconName: String
    var colorHex: String  // 文件夹自定义颜色
    var itemBundleIDs: [String]
    var order: Int
    var createdAt: Date
    var isDefault: Bool
    var isSystem: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, iconName, colorHex
        case itemBundleIDs
        case itemIDs
        case order, createdAt, isDefault, isSystem
    }

    init(id: UUID = UUID(),
         title: String,
         iconName: String = "folder.fill",
         colorHex: String = "#007AFF",
         itemBundleIDs: [String] = [],
         order: Int = 0,
         createdAt: Date = Date(),
         isDefault: Bool = false,
         isSystem: Bool = false) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        self.itemBundleIDs = itemBundleIDs
        self.order = order
        self.createdAt = createdAt
        self.isDefault = isDefault
        self.isSystem = isSystem
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "folder.fill"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#007AFF"
        if let bundleIDs = try c.decodeIfPresent([String].self, forKey: .itemBundleIDs) {
            itemBundleIDs = bundleIDs
        } else {
            let oldUUIDs = try c.decodeIfPresent([UUID].self, forKey: .itemIDs) ?? []
            itemBundleIDs = oldUUIDs.map { $0.uuidString }
        }
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isSystem = try c.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(iconName, forKey: .iconName)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(itemBundleIDs, forKey: .itemBundleIDs)
        try c.encode(order, forKey: .order)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isDefault, forKey: .isDefault)
        try c.encode(isSystem, forKey: .isSystem)
    }
}

// MARK: - GroupContainer (UI 层)

struct GroupContainer: Identifiable {
    let id: UUID
    var title: String
    var iconName: String
    var colorHex: String  // 文件夹自定义颜色
    var items: [ApplicationItem]
    var order: Int
    var isDefault: Bool
    var isSystem: Bool

    init(id: UUID = UUID(),
         title: String,
         iconName: String = "folder.fill",
         colorHex: String = "#007AFF",
         items: [ApplicationItem] = [],
         order: Int = 0,
         isDefault: Bool = false,
         isSystem: Bool = false) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        self.items = items
        self.order = order
        self.isDefault = isDefault
        self.isSystem = isSystem
    }

    // 从 AppGroup + 所有应用列表构建 UI 容器
    init(from group: AppGroup, allItems: [ApplicationItem]) {
        self.id = group.id
        self.title = group.title
        self.iconName = group.iconName
        self.colorHex = group.colorHex
        self.order = group.order
        self.isDefault = group.isDefault
        self.isSystem = group.isSystem
        self.items = allItems.filter { group.itemBundleIDs.contains($0.bundleIdentifier) }
    }

    // 导出为 AppGroup（持久化用）
    func toAppGroup() -> AppGroup {
        AppGroup(
            id: id,
            title: title,
            iconName: iconName,
            colorHex: colorHex,
            itemBundleIDs: items.map(\.bundleIdentifier),
            order: order,
            createdAt: Date(),
            isDefault: isDefault,
            isSystem: isSystem
        )
    }
}

// MARK: - Mutations

extension GroupContainer {
    mutating func add(_ item: ApplicationItem) {
        if !items.contains(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
            items.append(item)
        }
    }

    mutating func remove(_ item: ApplicationItem) {
        items.removeAll { $0.id == item.id }
    }

    mutating func moveItem(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    mutating func rename(to newTitle: String) {
        title = newTitle
    }

    mutating func changeIcon(to newIcon: String) {
        iconName = newIcon
    }
}
