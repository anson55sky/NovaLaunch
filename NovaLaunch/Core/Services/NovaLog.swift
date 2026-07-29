import Foundation

/// 统一日志系统：写入 ~/Library/Application Support/NovaLaunch/debug.log
enum NovaLog {
    static let logURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = dir.appendingPathComponent("NovaLaunch")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("debug.log")
    }()

    static func write(_ tag: String, _ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [\(tag)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: logURL)
    }

    static func readAll() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? "(空)"
    }
}
