import Foundation
import CoreData
import CloudKit

// MARK: - CloudSyncManager

/// iCloud + CloudKit 同步管理器
/// 使用 NSPersistentCloudKitContainer 实现无缝 iCloud 同步
/// 严格遵守合规要求：仅使用 Apple CloudKit 框架，无第三方依赖。
final class CloudSyncManager {
    static let shared = CloudSyncManager()

    private init() {}

    // MARK: - iCloud Availability

    var isCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Sync Configuration

    /// 配置 CloudKit 同步（由 CoreDataStack 调用）
    func configureSync(for container: NSPersistentCloudKitContainer) {
        guard isCloudAvailable else {
            NovaLog.write("CloudSync", "iCloud 不可用，跳过 CloudKit 配置")
            return
        }

        // 启用 CloudKit 自动同步
        guard let description = container.persistentStoreDescriptions.first else { return }

        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.novalaunch.app"
        )

        // 启用历史追踪（支持增量同步）
        description.setOption(true as NSNumber,
                              forKey: NSPersistentHistoryTrackingKey)

        // 启用远程变更通知
        description.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        NovaLog.write("CloudSync", "CloudKit 同步已配置")
    }

    // MARK: - Account Status

    func checkAccountStatus(completion: @escaping (Bool, String) -> Void) {
        CKContainer(identifier: "iCloud.com.novalaunch.app")
            .accountStatus { status, error in
                DispatchQueue.main.async {
                    switch status {
                    case .available:
                        completion(true, "iCloud 账户已登录")
                    case .noAccount:
                        completion(false, "未登录 iCloud 账户")
                    case .restricted:
                        completion(false, "iCloud 受限")
                    case .couldNotDetermine:
                        completion(false, "无法确定 iCloud 状态")
                    case .temporarilyUnavailable:
                        completion(false, "iCloud 暂时不可用")
                    @unknown default:
                        completion(false, "未知错误")
                    }
                }
            }
    }

    // MARK: - Manual Sync Trigger

    func triggerSync() {
        NotificationCenter.default.post(name: .novaCloudSyncRequested, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let novaCloudSyncRequested = Notification.Name("NovaCloudSyncRequested")
}
