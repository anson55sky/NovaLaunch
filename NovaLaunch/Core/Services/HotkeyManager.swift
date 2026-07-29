import Foundation
import AppKit
import Carbon

// MARK: - HotkeyEventCallback

private func hotkeyCallback(
    nextHandler: EventHandlerCallRef?,
    theEvent: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = theEvent else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event,
                     UInt32(kEventParamDirectObject),
                     UInt32(typeEventHotKeyID),
                     nil,
                     MemoryLayout<EventHotKeyID>.size,
                     nil,
                     &hotKeyID)

    if hotKeyID.id == 1 {
        NotificationCenter.default.post(name: .novaHotkeyPressed, object: nil)
    }
    return noErr
}

// MARK: - Notification Names

extension Notification.Name {
    static let novaHotkeyPressed = Notification.Name("NovaHotkeyPressed")
}

// MARK: - HotkeyConfig（v35：可序列化的热键配置）

/// 热键配置（支持自定义修饰键 + 按键码）
struct HotkeyConfig: Codable, Equatable {
    var modifiers: UInt32   // Carbon 修饰键位掩码
    var keyCode: UInt32     // 虚拟按键码

    // 默认值：Option + Space
    static let `default` = HotkeyConfig(modifiers: UInt32(optionKey), keyCode: 49)

    /// 将配置解析为可读字符串（如 "⌥ Space"、"⌘ ⇧ A"）
    var displayString: String {
        var parts: [String] = []

        // 解析修饰键
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("^") }

        // 解析按键名
        parts.append(keyCodeToName(keyCode))

        return parts.joined(separator: " ")
    }

    /// 虚拟按键码 → 可读名称
    private func keyCodeToName(_ code: UInt32) -> String {
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "5"
        case 23: return "6"
        case 24: return "7"
        case 25: return "8"
        case 26: return "9"
        case 27: return "0"
        case 28: return "Return"
        case 29: return "Escape"
        case 31: return "Tab"
        case 32: return "Space"
        case 36: return "Return (大)"
        case 37: return "←"
        case 38: return "↑"
        case 39: return "→"
        case 40: return "↓"
        case 41: return "-"
        case 42: return "+"
        case 43: return "="
        case 44: return "["
        case 45: return "]"
        case 46: return "\\"
        case 47: return ";"
        case 48: return "'"
        case 49: return "`"
        case 51: return ","
        case 52: return "."
        case 53: return "/"
        case 54: return "Fn"
        case 55: return "F1"
        case 56: return "F2"
        case 57: return "F3"
        case 58: return "F4"
        case 59: return "F5"
        case 60: return "F6"
        case 61: return "F7"
        case 62: return "F8"
        case 63: return "F9"
        case 64: return "F10"
        case 65: return "F11"
        case 66: return "F12"
        case 96: return "F5 (小)"
        case 97: return "F6 (小)"
        case 98: return "F7 (小)"
        case 99: return "F3 (小)"
        case 100: return "F8 (小)"
        case 101: return "F9 (小)"
        case 102: return "F11 (小)"
        case 103: return "F13"
        default: return "Key\(code)"
        }
    }
}

// MARK: - HotkeyManager

/// 全局热键管理器（支持用户自定义热键，支持双热键：启动台 + Launchpad）
/// 使用 Carbon API（kEventHotKeyRef）实现，完全基于 Apple 私有框架，无第三方依赖。
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var launchpadHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// 当前生效的热键配置
    private(set) var currentConfig: HotkeyConfig = .default
    /// Launchpad 热键配置（默认 Ctrl+Cmd+L），keyCode 37 = 'L'
    private(set) var launchpadConfig: HotkeyConfig = HotkeyConfig(
        modifiers: UInt32(controlKey | cmdKey), keyCode: 37
    )

    private init() {}

    /// 注册热键（使用当前配置）
    func register() {
        register(with: currentConfig)
    }

    /// 使用指定配置注册热键（支持动态切换）
    func register(with config: HotkeyConfig) {
        // 先注销旧热键
        unregister()

        currentConfig = config

        // 安装事件处理器（仅一次）
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // 注册主热键 (id=1)
        var hotKeyID = EventHotKeyID(signature: OSType(0x4E4C4348), id: 1) // "NLCH"
        RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        // 注册 Launchpad 热键 (id=2)，默认 Control+Option+Cmd+L
        var launchpadID = EventHotKeyID(signature: OSType(0x4E4C4348), id: 2)
        RegisterEventHotKey(
            launchpadConfig.keyCode,
            launchpadConfig.modifiers,
            launchpadID,
            GetApplicationEventTarget(),
            0,
            &launchpadHotKeyRef
        )
    }

    /// 更新 Launchpad 热键配置
    func updateLaunchpadConfig(_ config: HotkeyConfig) {
        // 先注销旧的 Launchpad 热键
        if let ref = launchpadHotKeyRef {
            UnregisterEventHotKey(ref)
            launchpadHotKeyRef = nil
        }
        launchpadConfig = config
        // 重新注册
        var launchpadID = EventHotKeyID(signature: OSType(0x4E4C4348), id: 2)
        RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            launchpadID,
            GetApplicationEventTarget(),
            0,
            &launchpadHotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = launchpadHotKeyRef {
            UnregisterEventHotKey(ref)
            launchpadHotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
