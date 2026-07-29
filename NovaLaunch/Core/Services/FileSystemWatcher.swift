import Foundation
import AppKit
import Combine
import CoreServices

// MARK: - FileSystemWatcher

/// 文件系统监听器：监控 /Applications 目录，自动刷新新安装的应用
/// 使用 FSEventStream（macOS 原生 API，无第三方依赖）
final class FileSystemWatcher {
    static let shared = FileSystemWatcher()

    private var stream: FSEventStreamRef?
    private var lastScanDate: Date = Date()
    private let debounceInterval: TimeInterval = 2.0
    private var pendingCheck: DispatchWorkItem?

    // 监听的应用目录
    private let watchPaths = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications"
    ].filter { FileManager.default.fileExists(atPath: $0) }

    private init() {}

    /// 启动监听
    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (
            streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds
        ) in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleFileSystemEvent()
        }

        let pathsToWatch = watchPaths as CFArray
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            UInt64(kFSEventStreamEventIdSinceNow),
            1.0,  // 延迟 1 秒合并事件
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        guard let stream = stream else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    /// 停止监听
    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    /// 处理文件系统事件（带防抖）
    private func handleFileSystemEvent() {
        // 取消之前的待处理任务
        pendingCheck?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.triggerIncrementalScan()
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// 触发增量扫描：仅扫描可能变化的部分
    private func triggerIncrementalScan() {
        DispatchQueue.main.async {
            // 通知 IndexingService 进行增量刷新
            NotificationCenter.default.post(name: .novaIncrementalScanRequested, object: nil)
        }
    }
}

extension Notification.Name {
    static let novaIncrementalScanRequested = Notification.Name("com.novalaunch.incrementalScanRequested")
    /// 关键修复（v4）：应用启动通知
    /// GroupViewModel 订阅后立即更新"最近使用"分组
    static let novaAppLaunched = Notification.Name("com.novalaunch.appLaunched")
}
