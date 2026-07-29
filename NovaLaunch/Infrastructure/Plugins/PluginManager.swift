import Foundation

// MARK: - PluginManager

/// 插件加载与管理器（Phase 4 预留框架）
/// 支持从 .bundle 加载插件
final class PluginManager {
    static let shared = PluginManager()

    private let pluginDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        pluginDirectory = appSupport
            .appendingPathComponent("NovaLaunch", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)

        try? FileManager.default.createDirectory(at: pluginDirectory,
                                                  withIntermediateDirectories: true)
    }

    func loadPlugins() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: pluginDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            guard url.pathExtension == "bundle" else { continue }
            loadPlugin(at: url)
        }
    }

    private func loadPlugin(at url: URL) {
        guard let bundle = Bundle(url: url), bundle.load() else {
            NovaLog.write("PluginManager", "Failed to load: \(url.lastPathComponent)")
            return
        }

        if let info = bundle.infoDictionary,
           let id = info["CFBundleIdentifier"] as? String,
           let name = info["CFBundleName"] as? String {
            NovaLog.write("PluginManager", "Loaded: \(name) (\(id))")
        }
    }
}
