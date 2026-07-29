import Foundation
import AppKit

// MARK: - 全局剪贴板管理器（v47）

/// 单例全局剪贴板监听器
/// 设计：
/// - 单例模式，AppDelegate 启动时初始化，生命周期与 App 一致
/// - Timer 轮询 NSPasteboard.general.changeCount（0.5s 间隔）
/// - 防抖：只有 changeCount 变化时才读取
/// - 去重：与上一条内容相同则跳过
/// - 线程安全：所有操作在主线程执行
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    /// 剪贴板历史（最新在前，最多 50 条）
    @Published private(set) var entries: [ClipboardEntry] = []

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let maxEntries = 50

    private init() {
        loadHistory()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - 公开接口

    func copyToClipboard(_ entry: ClipboardEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch entry.type {
        case .text:
            pb.setString(entry.content, forType: .string)
        case .image:
            if let data = entry.imageData, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        }
    }

    func deleteEntry(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        saveHistory()
    }

    func clearHistory() {
        entries.removeAll()
        saveHistory()
    }

    // MARK: - 监听

    private func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        NovaLog.write("ClipboardManager", "启动监听, initial changeCount: \(lastChangeCount)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkPasteboard()
            }
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        NovaLog.write("ClipboardManager", "检测到剪贴板变化: changeCount=\(current) types=\(pb.types?.map(\.rawValue).joined(separator: ",") ?? "nil")")

        // 关键修复（v61）：先尝试读取图片（多格式兼容）
        // macOS 截图剪贴板格式优先级：.tiff（系统通用） > .png（macOS 14+ 现代截图）
        // 之前只检测 .tiff，导致 macOS 14+ 用 PNG 写入的截图无法识别
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        var imageData: Data? = nil
        var imageFormat: String = ""
        for type in imageTypes {
            if let data = pb.data(forType: type), !data.isEmpty {
                imageData = data
                imageFormat = type.rawValue
                break
            }
        }
        if let imageData = imageData {
            // 关键修复（v61）：提高图片大小限制从 2MB 到 8MB
            // 之前 2MB 限制会过滤掉大部分全屏截图（2K 显示器全屏截图约 5-8MB）
            // 8MB 限制可覆盖 99% 截图场景，且 50 条记录也不会爆内存
            guard imageData.count < 8_000_000 else {
                NovaLog.write("ClipboardManager", "图片过大(\(imageData.count) bytes)，已跳过")
                return
            }
            // 验证数据可以 decode 为图片（防止损坏数据）
            guard NSImage(data: imageData) != nil else {
                NovaLog.write("ClipboardManager", "图片数据无法 decode，已跳过")
                return
            }
            NovaLog.write("ClipboardManager", "检测到图片：\(imageData.count) bytes, format=\(imageFormat)")
            addEntry(ClipboardEntry(
                id: UUID().uuidString,
                type: .image,
                content: "图片",
                imageData: imageData,
                timestamp: Date()
            ))
            return
        }

        // 读取文本
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addEntry(ClipboardEntry(
                id: UUID().uuidString,
                type: .text,
                content: text,
                imageData: nil,
                timestamp: Date()
            ))
        }
    }

    private func addEntry(_ entry: ClipboardEntry) {
        // 去重：文本按 content 去重，图片按 imageData 去重
        // 之前图片都用 content="图片" 导致连续截图被误判为重复
        if entry.type == .image {
            if entries.contains(where: { $0.imageData == entry.imageData }) {
                return
            }
        } else {
            if entries.contains(where: { $0.content == entry.content && $0.type == entry.type }) {
                return
            }
        }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        saveHistory()
    }

    // MARK: - 持久化

    /// 剪贴板图片缓存目录
    private var imagesCacheDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("NovaLaunch/ClipboardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveHistory() {
        // 删除旧图片缓存文件（每次全量覆盖）
        if let oldFiles = try? FileManager.default.contentsOfDirectory(at: imagesCacheDir, includingPropertiesForKeys: nil) {
            for url in oldFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // 构建持久化条目列表（文本 + 图片元数据，最多 50 条）
        var savedEntries: [[String: Any]] = []
        let maxSave = min(entries.count, 50)
        for i in 0..<maxSave {
            let entry = entries[i]
            var dict: [String: Any] = [
                "id": entry.id,
                "type": entry.type.rawValue,
                "content": entry.content,
                "timestamp": entry.timestamp.timeIntervalSince1970
            ]
            if entry.type == .image, let imageData = entry.imageData {
                let filename = "\(entry.id).png"
                let fileURL = imagesCacheDir.appendingPathComponent(filename)
                try? imageData.write(to: fileURL)
                dict["imageFile"] = filename
            }
            savedEntries.append(dict)
        }

        if let data = try? JSONSerialization.data(withJSONObject: savedEntries) {
            UserDefaults.standard.set(data, forKey: "NovaLaunchClipboardHistory")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "NovaLaunchClipboardHistory"),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            NovaLog.write("ClipboardManager", "loadHistory: 无持久化数据")
            return
        }

        var loadedEntries: [ClipboardEntry] = []
        for dict in saved {
            guard let id = dict["id"] as? String,
                  let typeStr = dict["type"] as? String,
                  let content = dict["content"] as? String,
                  let timestamp = dict["timestamp"] as? TimeInterval else { continue }

            let type: ClipboardEntryType = (typeStr == "image") ? .image : .text
            var imageData: Data? = nil

            if type == .image {
                if let filename = dict["imageFile"] as? String {
                    let fileURL = imagesCacheDir.appendingPathComponent(filename)
                    imageData = try? Data(contentsOf: fileURL)
                }
            }

            loadedEntries.append(ClipboardEntry(
                id: id,
                type: type,
                content: content,
                imageData: imageData,
                timestamp: Date(timeIntervalSince1970: timestamp)
            ))
        }

        entries = loadedEntries
        NovaLog.write("ClipboardManager", "loadHistory: 加载了 \(loadedEntries.count) 条持久化条目 (含 \(loadedEntries.filter { $0.type == .image }.count) 张图片)")
    }
}
