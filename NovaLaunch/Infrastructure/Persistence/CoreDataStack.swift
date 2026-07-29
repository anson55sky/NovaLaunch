import Foundation
import CoreData

// MARK: - CoreDataStack

/// Core Data 持久化栈
/// 支持本地存储 + CloudKit iCloud 同步（Phase 3）
/// 严格遵守合规要求：仅使用 Apple CoreData / CloudKit 框架，无第三方依赖。
final class CoreDataStack: @unchecked Sendable {
    static let shared = CoreDataStack()

    private init() {}

    // MARK: - Persistent Container

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        // 防止在模型不存在时 CoreData 报错
        let modelURL = Bundle.main.url(forResource: "NovaLaunch", withExtension: "momd")
        let container: NSPersistentCloudKitContainer
        if let modelURL = modelURL, let model = NSManagedObjectModel(contentsOf: modelURL) {
            container = NSPersistentCloudKitContainer(name: "NovaLaunch", managedObjectModel: model)
        } else {
            // 没有 .xcdatamodeld 时用空模型跳过 CoreData
            container = NSPersistentCloudKitContainer(name: "NovaLaunch", managedObjectModel: NSManagedObjectModel())
        }

        // 配置本地存储
        let storeURL = applicationSupportDirectory
            .appendingPathComponent("NovaLaunch.sqlite")

        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        // Phase 3: CloudKit 同步配置
        CloudSyncManager.shared.configureSync(for: container)

        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                // CoreData 模型不存在时静默失败（Phase 1/2 不依赖 CoreData，使用 UserDefaults）
                NovaLog.write("CoreData", "跳过: \(error.localizedDescription)")
            }
        }

        // 自动合并远程变更
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

        return container
    }()

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    // MARK: - Background Context

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = persistentContainer.newBackgroundContext()
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return ctx
    }

    // MARK: - Save

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            NovaLog.write("CoreData", "保存失败: \(error)")
            context.rollback()
        }
    }

    func saveBackground(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            NovaLog.write("CoreData", "后台保存失败: \(error)")
        }
    }

    // MARK: - Store URL

    private var applicationSupportDirectory: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls[0].appendingPathComponent("NovaLaunch", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport,
                                                  withIntermediateDirectories: true)
        return appSupport
    }
}
