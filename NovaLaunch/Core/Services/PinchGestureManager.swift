import AppKit
import CoreGraphics

// MARK: - 捏合手势管理器（v36）
/// 监听触控板四指/五指捏合手势，用于唤醒/隐藏启动台
/// 使用 CGEventTap 实现真正的事件拦截（而非仅观察）
/// 关键优势：可以消费事件，阻止系统 Launchpad 同时响应
final class PinchGestureManager {
    static let shared = PinchGestureManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentMagnification: CGFloat = 0
    private var isInPinch = false
    private var isEnabled: Bool = true

    // 阈值：向内捏合的幅度超过此值才触发（避免误触）
    private let pinchThreshold: CGFloat = -0.5

    /// 手势动作回调
    var onPinchToggle: ((Bool) -> Void)?

    private init() {}

    /// 开始监听捏合手势（使用 CGEventTap 拦截）
    func startMonitoring() {
        stopMonitoring()
        guard isEnabled else { return }

        // CGEventTap 可以真正拦截并消费事件（return nil = 消费，return event = 放行）
        // 这样系统 Launchpad 就不会同时响应
        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                return PinchGestureManager.shared.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: nil
        ) else {
            NovaLog.write("PinchGesture", "CGEventTap 创建失败，回退到 NSEvent 观察模式")
            // 回退到观察模式（无法拦截，但不会崩溃）
            startFallbackMonitoring()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// 回退方案：NSEvent 观察模式（无法拦截系统事件）
    private var fallbackMonitor: Any?
    private func startFallbackMonitoring() {
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.handleNSEvent(event)
        }
    }

    /// 停止监听
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        if let monitor = fallbackMonitor {
            NSEvent.removeMonitor(monitor)
            fallbackMonitor = nil
        }
        resetState()
    }

    /// 启用/禁用
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    // MARK: - CGEventTap 回调

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 只处理滚轮事件（捏合手势在 macOS 上表现为 scrollWheel 事件）
        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        // 检测是否为捏合手势（scrollWheel 的 phase 包含 magnification 信息）
        let scrollDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let scrollDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1

        // 捏合手势的特征：continuous + 双轴都有值
        if isContinuous && abs(scrollDeltaX) > 0.001 {
            let delta = scrollDeltaX

            if !isInPinch {
                isInPinch = true
                currentMagnification = 0
            }
            currentMagnification += delta

            // 检测手势结束
            if abs(delta) < 0.0001 {
                if currentMagnification < pinchThreshold {
                    // 向内捏合 → 触发唤醒
                    DispatchQueue.main.async { [weak self] in
                        self?.onPinchToggle?(true)
                    }
                } else if currentMagnification > 0.3 {
                    // 向外张开 → 触发隐藏
                    DispatchQueue.main.async { [weak self] in
                        self?.onPinchToggle?(false)
                    }
                }
                resetState()
            }

            // 关键：消费事件（返回 nil），阻止系统 Launchpad 响应
            return nil
        }

        // 非捏合手势 → 放行
        return Unmanaged.passUnretained(event)
    }

    // MARK: - NSEvent 回退处理

    private func handleNSEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel else { return }
        let deltaX = event.scrollingDeltaX
        let isContinuous = event.hasPreciseScrollingDeltas

        if isContinuous && abs(deltaX) > 0.001 {
            if !isInPinch {
                isInPinch = true
                currentMagnification = 0
            }
            currentMagnification += deltaX

            if abs(deltaX) < 0.0001 {
                if currentMagnification < pinchThreshold {
                    onPinchToggle?(true)
                } else if currentMagnification > 0.3 {
                    onPinchToggle?(false)
                }
                resetState()
            }
        }
    }

    private func resetState() {
        isInPinch = false
        currentMagnification = 0
    }

    deinit {
        stopMonitoring()
    }
}
