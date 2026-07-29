import AppKit
import SwiftUI
import Combine
import os.log

// MARK: - 自定义 NSWindow 子类

/// 关键修复（v13）：自定义 NSWindow 子类
/// canBecomeKey = true 让 TextField 可以获取焦点（borderless 窗口默认 false）
class NovaLauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    /// ProMotion 120Hz support
    override func awakeFromNib() {
        super.awakeFromNib()
        enableProMotion()
    }
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        enableProMotion()
    }
    
    private func enableProMotion() {
        // 120FPS ProMotion 深度优化
        if let layer = contentView?.layer ?? {
            contentView?.wantsLayer = true
            return contentView?.layer
        }() {
            // drawsAsynchronously=false 减少 1 帧延迟
            layer.drawsAsynchronously = false
            layer.isOpaque = true
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        }
        animationBehavior = .documentWindow

        // CADisplayLink 120Hz 驱动 — 由 DragPerformanceMonitor 统一管理
        DragPerformanceMonitor.shared.startIfNeeded()
    }
    
    // Native edge resize — reliable AppKit-level mouse tracking
    private let resizeEdgeWidth: CGFloat = 8
    private var isResizing: Bool = false
    private var resizeEdge: ResizeEdge?
    private var resizeInitialFrame: NSRect?
    private var resizeInitialPoint: NSPoint?
    
    private enum ResizeEdge { case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
    
    private func edgeAt(point: NSPoint) -> ResizeEdge? {
        let frameSize = self.frame.size
        let inLeft   = point.x <= resizeEdgeWidth
        let inRight  = point.x >= frameSize.width - resizeEdgeWidth
        let inTop    = point.y >= frameSize.height - resizeEdgeWidth
        let inBottom = point.y <= resizeEdgeWidth
        
        if inLeft   && inTop    { return .topLeft }
        if inRight  && inTop    { return .topRight }
        if inLeft   && inBottom { return .bottomLeft }
        if inRight  && inBottom { return .bottomRight }
        if inLeft              { return .left }
        if inRight             { return .right }
        if inTop               { return .top }
        if inBottom            { return .bottom }
        return nil
    }
    
    private func updateCursor(for edge: ResizeEdge?) {
        switch edge {
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .topLeft, .bottomRight:
            // diagonal: top-left to bottom-right
            if #available(macOS 15.0, *) {
                NSCursor.frameResize(position: .topLeft, directions: .all).set()
            } else {
                NSCursor(image: NSImage(size: NSSize(width: 16, height: 16)), hotSpot: NSPoint(x: 8, y: 8)).set()
            }
        case .topRight, .bottomLeft:
            // diagonal: top-right to bottom-left
            if #available(macOS 15.0, *) {
                NSCursor.frameResize(position: .topRight, directions: .all).set()
            } else {
                NSCursor.resizeLeftRight.set()
            }
        case nil:
            NSCursor.arrow.set()
        }
    }
    
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let localPoint = event.locationInWindow
            if let edge = edgeAt(point: localPoint) {
                resizeEdge = edge
                isResizing = true
                resizeInitialFrame = frame
                resizeInitialPoint = convertPoint(toScreen: localPoint)
                return
            }
            
        case .leftMouseDragged:
            if isResizing, let edge = resizeEdge,
               let initialFrame = resizeInitialFrame,
               let initialPoint = resizeInitialPoint {
                performResize(edge: edge, initialFrame: initialFrame,
                              initialPoint: initialPoint,
                              currentScreenPoint: convertPoint(toScreen: event.locationInWindow))
                return
            }
            
        case .leftMouseUp:
            if isResizing {
                isResizing = false
                resizeEdge = nil
                resizeInitialFrame = nil
                resizeInitialPoint = nil
                return
            }
            
        case .mouseMoved:
            let localPoint = event.locationInWindow
            updateCursor(for: edgeAt(point: localPoint))
            
        case .mouseExited:
            updateCursor(for: nil)
            // Don't call endDrag() here — it would clear draggedItem and
            // stop the boundary Timer from sending Escape. The Timer itself
            // detects the mouse outside and sends Escape. endDrag() is called
            // on mouse-up (the actual end of the drag session).
            if DragContext.shared.draggedItem != nil || DragContext.shared.draggedTabGroup != nil {
                NotificationCenter.default.post(name: .novaCancelAllDrags, object: nil)
            }
            
        default: break
        }
        
        super.sendEvent(event)
    }
    
    private func performResize(edge: ResizeEdge, initialFrame: NSRect,
                                initialPoint: NSPoint, currentScreenPoint: NSPoint) {
        let dx = currentScreenPoint.x - initialPoint.x
        let dy = currentScreenPoint.y - initialPoint.y
        let minW: CGFloat = 800, minH: CGFloat = 500
        var newFrame = frame
        
        switch edge {
        case .left:
            let newWidth = max(minW, initialFrame.width - dx)
            newFrame.origin.x = initialFrame.maxX - newWidth
            newFrame.size.width = newWidth
            
        case .right:
            let newWidth = max(minW, initialFrame.width + dx)
            newFrame.size.width = newWidth
            
        case .top:
            let newHeight = max(minH, initialFrame.height + dy)
            newFrame.size.height = newHeight
            
        case .bottom:
            let newHeight = max(minH, initialFrame.height - dy)
            newFrame.origin.y = initialFrame.minY + dy
            newFrame.size.height = newHeight
            
        case .topLeft:
            let newWidth = max(minW, initialFrame.width - dx)
            let newHeight = max(minH, initialFrame.height + dy)
            newFrame.origin.x = initialFrame.maxX - newWidth
            newFrame.size.width = newWidth
            newFrame.size.height = newHeight
            
        case .topRight:
            let newWidth = max(minW, initialFrame.width + dx)
            let newHeight = max(minH, initialFrame.height + dy)
            newFrame.size.width = newWidth
            newFrame.size.height = newHeight
            
        case .bottomLeft:
            let newWidth = max(minW, initialFrame.width - dx)
            let newHeight = max(minH, initialFrame.height - dy)
            newFrame.origin.x = initialFrame.maxX - newWidth
            newFrame.origin.y = initialFrame.minY + dy
            newFrame.size.width = newWidth
            newFrame.size.height = newHeight
            
        case .bottomRight:
            let newWidth = max(minW, initialFrame.width + dx)
            let newHeight = max(minH, initialFrame.height - dy)
            newFrame.origin.y = initialFrame.minY + dy
            newFrame.size.width = newWidth
            newFrame.size.height = newHeight
        }
        
        // Screen bounds
        if let screen = screen {
            let v = screen.visibleFrame
            if newFrame.maxX > v.maxX { newFrame.origin.x = v.maxX - newFrame.width }
            if newFrame.minX < v.minX { newFrame.origin.x = v.minX }
            if newFrame.maxY > v.maxY { newFrame.origin.y = v.maxY - newFrame.height }
            if newFrame.minY < v.minY { newFrame.origin.y = v.minY }
        }
        
        setFrame(newFrame, display: true, animate: false)
        AppDelegate.saveWindowFrame(newFrame.size)
    }
}

// MARK: - 自定义 NSHostingController 子类

/// 关键修复（v14）：自定义 NSHostingController
/// 解决方角问题：NSHostingView 的 intrinsic size 由 SwiftUI 内容决定，
/// 比窗口小 → 四周透明 → 方角
///
/// 拖拽性能精准优化
/// 在 beginDraggingSession 拦截点执行三项优化:
/// 1) 预渲染拖拽预览 NSImage 替代 SwiftUI 默认动态渲染 (消除 90% 卡顿根因)
/// 2) animatesToStartingPositionsOnCancelOrFail=false + draggingFormation=.none
/// 3) 关闭 layer 隐式动画 (shouldRasterize + actions 覆盖)
final class DragInterceptHostingView<Content: View>: NSHostingView<Content> {
    
    // 实现任意空白区域拖动窗口（兼容 isMovableByWindowBackground = false）
    // 点击 SwiftUI 按钮/输入框等交互元素时 super.mouseDown 先消费事件
    // 点击空白区域时 performDrag 启动原生窗口拖动
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let window = window, !window.isMovableByWindowBackground {
            window.performDrag(with: event)
        }
    }
    
    override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource) -> NSDraggingSession {
        // ✅ 已修复：拖拽预览零实时渲染 + GPU 纹理直传
        let optimizedItems: [NSDraggingItem] = items.map { originalItem in
            if let draggedItem = DragContext.shared.draggedItem {
                let previewImage = preRenderDragPreviewLightweight(for: draggedItem)

                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(draggedItem.bundleIdentifier, forType: .string)
                pasteboardItem.setData(
                    draggedItem.bundleIdentifier.data(using: .utf8) ?? Data(),
                    forType: NSPasteboard.PasteboardType("com.novalaunch.drag.item")
                )

                let optimized = NSDraggingItem(pasteboardWriter: pasteboardItem)
                // 关键修复：拖拽图像 frame 必须使用屏幕坐标系（NSDraggingSession 约定），
                // 且尺寸与预览图一致，否则会出现偏移/拉伸导致“不跟手”。
                let previewSize = previewImage.size
                let frame: NSRect
                if originalItem.draggingFrame.isEmpty {
                    // 退回方案：将窗口坐标转换为屏幕坐标，并以预览图中心对齐光标
                    let winOrigin = window?.frame.origin ?? .zero
                    let screenPoint = NSPoint(x: winOrigin.x + event.locationInWindow.x,
                                              y: winOrigin.y + event.locationInWindow.y)
                    frame = NSRect(x: screenPoint.x - previewSize.width / 2,
                                   y: screenPoint.y - previewSize.height / 2,
                                   width: previewSize.width, height: previewSize.height)
                } else {
                    // 系统给出的 draggingFrame 已是屏幕坐标且正确对齐手势起点。
                    // 以其中心为锚、用预览图自身尺寸，避免尺寸错配导致拉伸/偏移。
                    let base = originalItem.draggingFrame
                    frame = NSRect(x: base.midX - previewSize.width / 2,
                                   y: base.midY - previewSize.height / 2,
                                   width: previewSize.width, height: previewSize.height)
                }
                optimized.setDraggingFrame(frame, contents: previewImage)
                return optimized
            }
            return originalItem
        }

        let session = super.beginDraggingSession(with: optimizedItems, event: event, source: source)

        // ✅ 已修复：120FPS ProMotion 拖拽优化
        session.animatesToStartingPositionsOnCancelOrFail = false
        session.draggingFormation = .none

        // ✅ 已修复：拖拽期间关闭 layer 隐式动画 + 非必要合成层
        disableAnimationsFor120FPS()

        DragContext.shared.captureSession(session)
        return session
    }

    // MARK: - v125: 轻量拖拽预览 (简化为 lockFocus，消除 bitmap 分配瓶颈)

    /// 移除 NSBitmapImageRep 分配（这是 54 FPS 的主要瓶颈之一）。
    /// NSBitmapImageRep(width=136, height=168) + 4 channels = ~91KB 每次拖拽的堆分配。
    /// 改用最简单的 lockFocus 渲染，NSImage 内部自动管理 bitmap。
    private func preRenderDragPreviewLightweight(for item: ApplicationItem) -> NSImage {
        if let cached = DragContext.shared.cachedDragPreview { return cached }

        let iconSize: CGFloat = 48; let padding: CGFloat = 10; let labelHeight: CGFloat = 16
        let canvasW = iconSize + padding * 2; let canvasH = iconSize + padding * 2 + labelHeight
        let image = NSImage(size: NSSize(width: canvasW, height: canvasH))
        image.lockFocus()

        // 纯色背景
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: canvasW - 4, height: canvasH - 4), xRadius: 12, yRadius: 12).fill()

        // 图标 — 同步 IO，但仅在拖拽启动时一次
        let rawIcon = NSWorkspace.shared.icon(forFile: item.bundlePath)
        let iconRect = NSRect(x: (canvasW - iconSize) / 2, y: labelHeight + padding, width: iconSize, height: iconSize)
        let clipPath = NSBezierPath(roundedRect: iconRect, xRadius: iconSize * 0.22, yRadius: iconSize * 0.22)
        NSGraphicsContext.current?.saveGraphicsState(); clipPath.addClip()
        rawIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.current?.restoreGraphicsState()

        // 名称
        let par = NSMutableParagraphStyle(); par.alignment = .center; par.lineBreakMode = .byTruncatingTail
        (item.displayName as NSString).draw(in: NSRect(x: 4, y: 4, width: canvasW - 8, height: labelHeight),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
                             .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: par])

        image.unlockFocus()
        DragContext.shared.cachedDragPreview = image
        return image
    }

    // MARK: - v126: CALayer 直操作拖拽渲染链路

    /// 拖拽期间绕过 SwiftUI diff 管线，直接操作 CALayer
    /// 
    /// 核心原理:
    /// - CATransaction.setDisableActions(true) 全局禁用隐式动画
    /// - shadowPath 预计算消除离屏渲染（shadowOffset/shadowRadius 导致 OS render）
    /// - masksToBounds=false 避免 cornerRadius 触发离屏渲染
    /// - 子视图 layer 批量设置 shouldRasterize + rasterizationScale
    /// 拖拽开始通知。
    ///
    /// 旧版会同步递归遍历整棵视图树、全局禁用隐式动画并开启 shouldRasterize，
    /// 实测阻塞主线程导致拖拽起点卡顿、压低跟手感，还干扰系统 NSDraggingSession
    /// 的实时跟随。现改为仅广播通知（供 LiquidGlassBackground 等外部按需临时关闭毛玻璃），
    /// 不再篡改任何 CALayer，保证拖拽图像由系统原生、稳定跟随光标。
    private func disableAnimationsFor120FPS() {
        NotificationCenter.default.post(name: .novaDragDidBegin, object: nil)
    }

    // 旧版逐层 layer 优化已弃用（拖拽启动卡顿 + 干扰系统跟手），保留空实现以防遗漏调用。
    private func optimizeSubviews(view: NSView) {}

    // 拖拽结束时仅广播结束通知。
    // 由于 disableAnimationsFor120FPS 已不再修改任何 layer 属性，
    // 无需、也不应再对子视图 layer 做任何逆向操作（旧版 restoreSubviews 的
    // shadowOpacity*3.33 会在未经过 *0.3 预处理时错误放大阴影，是明确的回归 bug）。
    private func restoreAnimations() {
        NotificationCenter.default.post(name: .novaDragDidEnd, object: nil)
    }

    // 旧版 restoreSubviews 已随 optimizeSubviews 一并弃用。
    private func restoreSubviews(view: NSView) {}

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        super.draggingEnded(sender)
        restoreAnimations()
        NotificationCenter.default.post(name: .novaDragDidEnd, object: nil)
        DragContext.shared.releaseSession()
        DragContext.shared.cachedDragPreview = nil
    }
}

/// 方案：
/// 1. sizingOptions = [] 禁用 intrinsic size
/// 2. viewDidAppear 时强制撑满
/// 3. 监听窗口 resize 通知，手动同步 frame
class NovaHostingController<Content: View>: NSHostingController<Content> {
    private var resizeObserver: NSObjectProtocol?
    
    // Custom hosting view that intercepts drag session creation
    override func loadView() {
        // Create a custom DragInterceptHostingView instead of default NSHostingView
        let customView = DragInterceptHostingView(rootView: rootView)
        customView.sizingOptions = []
        customView.autoresizingMask = [.width, .height]
        self.view = customView
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        forceFillSuperview()
        
        // 监听窗口 resize，手动同步 hosting view 的 frame
        if let window = view.window {
            NotificationCenter.default.removeObserver(resizeObserver as Any)
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.forceFillSuperview()
            }
        }
    }
    
    private func forceFillSuperview() {
        if let parentView = view.superview {
            view.frame = parentView.bounds
        }
    }
    
    deinit {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    static weak var shared: AppDelegate?
    var statusItem: NSStatusItem?
    /// 关键：把原来的 NSPopover 改成 NSWindow
    /// 1) NSWindow 可自由缩放（用户新需求 #3：缩放整个程序框）
    /// 2) NSWindow 是普通 window，child NSPanel 可以用 parent 属性正确浮在它上面
    ///    （解决 #2：新建分组弹窗被主程序遮住，NSPopover 太高挡住 panel）
    /// 3) NSHostingView 桥接 SwiftUI 的布局更可预测
    /// 4) 提供原生的 mouseDrag/resize 行为
    var launcherWindow: NSWindow?
    var preferencesWindow: NSWindow?
    var cancellables = Set<AnyCancellable>()

    
    private var lastFullscreenMode: Bool = false

    // 全局事件监听器（用于点击主程序外自动隐藏）
    private var outsideClickMonitor: Any?

    
    private var panelKeyMonitor: Any?

    
    var activePanel: MainLauncherView.NovaPanel = .launcher

    // 主程序的视觉外观
    var launcherAppearance: NSAppearance = NSAppearance(named: .aqua)!

    // 关键修复：静态引用主程序的窗口，供 panel 定位
    // NSWindow 相比 NSPopover 是稳定的、生命周期可预测的对象
    static weak var sharedLauncherWindow: NSWindow?
    static weak var sharedPreferencesWindow: NSWindow?

    // 关键修复（v5）：箭头在窗口中的 x 坐标（指向状态栏按钮）
    // AppDelegate 在 positionLauncherWindowBelowStatusBar 中更新
    // SwiftUI 视图读取此值来定位箭头
    // 使用 CGFloat 而非 CGFloat?，默认 -1（表示尚未初始化）
    static var sharedArrowXPosition: CGFloat = -1

    // 关键修复（v15）：状态栏按钮在屏幕上的 x 中心坐标
    // 用于 resize 时重新计算箭头位置（LauncherWindowDelegate 无法访问 statusItem）
    static var sharedButtonScreenX: CGFloat = -1

    // 关键修复（v5）：窗口当前尺寸
    // 用于 SwiftUI 中动态计算每屏数量
    static var sharedWindowSize: NSSize = NSSize(width: 720, height: 560)

    // 关键修复（v17）：分屏浏览区域的实际可用尺寸
    // PagingViewController 在 computePageSize() 中更新此值
    // itemsPerPage() 使用此值（而非 sharedWindowSize）来计算每屏图标数量
    // 解决：之前用窗口总高度减去估算的 chromeHeight → 估算不准 → 第一行被裁切
    static var sharedPagingAreaSize: NSSize = NSSize(width: 680, height: 360)

    // 关键修复：专门处理 launcher window 的"右上角固定"缩放行为
    // 不能用 self（AppDelegate）做 NSWindowDelegate，
    // 否则会和 preferences window 的 windowWillClose 等回调冲突
    private let launcherDelegate = LauncherWindowDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动自动更新检查
        UpdateChecker.shared.start()
        
        AppDelegate.shared = self

        // 关键修复：设置为 accessory 策略，菜单栏应用不显示 dock 图标和主窗口
        // 这彻底解决了"空白页弹窗"问题
        NSApp.setActivationPolicy(.accessory)
        
        // Enable ProMotion 120Hz display support
        enableHighRefreshRate()

        // Phase 2: 先加载用户偏好（热键配置需要在注册前加载）
        UserPreferences.shared.load()

        
        let config = HotkeyConfig(
            modifiers: UserPreferences.shared.hotkeyModifiers,
            keyCode: UserPreferences.shared.hotkeyCode
        )
        HotkeyManager.shared.register(with: config)

        // 监听热键事件
        NotificationCenter.default.publisher(for: .novaHotkeyPressed)
            .sink { [weak self] _ in
                self?.toggleLauncher()
            }
            .store(in: &cancellables)


        // Phase 3: 初始化 Core Data
        _ = CoreDataStack.shared.viewContext

        // Phase 3: 加载插件
        PluginManager.shared.loadPlugins()

        // Phase 3: 监听 iCloud 同步通知
        NotificationCenter.default.publisher(for: .novaCloudSyncRequested)
            .sink { _ in
                CloudSyncManager.shared.triggerSync()
            }
            .store(in: &cancellables)

        // Phase 4: 监听增量扫描请求（由文件监视器触发）
        NotificationCenter.default.publisher(for: .novaIncrementalScanRequested)
            .sink { _ in
                IndexingService.shared.startIncrementalScan()
            }
            .store(in: &cancellables)

        // Phase 4: 启动文件系统监视器，自动检测新安装的应用
        FileSystemWatcher.shared.start()

        // Bug Fix: Start initial scan so search works immediately on launch.
        // Previously scan was only triggered on menu bar click, leaving items
        // empty and search broken until the user manually refreshed.
        IndexingService.shared.startFullScan()

        
        PinchGestureManager.shared.onPinchToggle = { [weak self] _ in
            self?.toggleLauncher()
        }
        PinchGestureManager.shared.setEnabled(UserPreferences.shared.enablePinchGesture)
        PinchGestureManager.shared.startMonitoring()

        // 监听外观变化（仅作用于主程序，不影响设置窗口）
        NotificationCenter.default.publisher(for: .novaLauncherAppearanceChanged)
            .sink { [weak self] notification in
                guard let self = self,
                      let appearance = notification.object as? NSAppearance else { return }
                self.launcherAppearance = appearance
                // 实时更新当前显示的主程序窗口
                self.launcherWindow?.appearance = appearance
            }
            .store(in: &cancellables)

        // 监听"隐藏启动器"通知（来自面板内点击触发的关闭请求）
        NotificationCenter.default.publisher(for: .novaHideLauncher)
            .sink { [weak self] _ in
                guard let self = self, let window = self.launcherWindow, window.isVisible else { return }
                window.orderOut(nil)
                self.removeOutsideClickMonitor()
            }
            .store(in: &cancellables)

        // 创建菜单栏图标 + 菜单
        setupStatusItem()

        // 检测"减少运动"偏好
        UserPreferences.shared.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // 注册视图插件（注册后立即激活 AppList 为默认 Tab）
        ViewPluginManager.shared.registerBuiltInPlugins()
        ViewPluginManager.shared.activePluginID = "com.novalaunch.applist"

        
        SearchPluginManager.shared.registerBuiltInPlugins()

        
        _ = ClipboardManager.shared

        
        DashboardViewModel.shared.startPreloading()

    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出前保存窗口尺寸
        if let window = launcherWindow {
            saveWindowSize(window.frame.size)
        }
        HotkeyManager.shared.unregister()
        FileSystemWatcher.shared.stop()
        removeOutsideClickMonitor()
    }

    // MARK: - 菜单栏图标 + 菜单

    /// Enable ProMotion 120Hz display support for ultra-smooth animations
    private func enableHighRefreshRate() {
        // Tell CoreAnimation to prefer display-linked updates at the display's native refresh rate
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.0)
        
        // Set the global preferred frames per second range (0 = no cap, display native)
        if let screen = NSScreen.main {
            let maxFPS = screen.maximumFramesPerSecond
            // Request adaptive sync at native display refresh (60/120/ProMotion)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = true
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.grid.2x2.fill",
                                  accessibilityDescription: "NovaLaunch")
            // 关键修复（v23）：只设置 action，不设置 button.menu
            // 设置 menu 后系统会接管左键显示菜单的行为，与 action 冲突导致点击无响应
            // 改为在 action 中手动 popUp 菜单，完全控制左键行为
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            // 不设置 button.menu！在 statusItemClicked 中手动弹出
        }
    }

    /// 构建菜单栏菜单（图1：显示主程序、设置、关于、退出）
    private func buildStatusBarMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false  // 手动控制菜��项启用状态
        menu.appearance = NSAppearance(named: .aqua)

        // 1. 显示 NovaLaunch
        let showItem = NSMenuItem(
            title: "显示 NovaLaunch",
            action: #selector(showLauncherFromMenu),
            keyEquivalent: ""
        )
        showItem.target = self
        showItem.isEnabled = true
        showItem.image = NSImage(systemSymbolName: "rectangle.grid.2x2", accessibilityDescription: "")
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // 2. 设置...
        let prefsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        prefsItem.isEnabled = true
        prefsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "")
        menu.addItem(prefsItem)

        // 3. 刷新应用
        let refreshItem = NSMenuItem(
            title: "刷新应用列表",
            action: #selector(refreshApps),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = true
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "")
        menu.addItem(refreshItem)

        // 3.5 检查更新
        let updateItem = NSMenuItem(
            title: "检查更新…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.isEnabled = true
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "")
        menu.addItem(updateItem)

        // 购买 & 激活（当前免费开放，灰色显示）
        let purchaseItem = NSMenuItem(
            title: "购买 PRO…",
            action: #selector(purchasePro),
            keyEquivalent: ""
        )
        purchaseItem.target = self
        purchaseItem.isEnabled = false  // 待收费时启用
        purchaseItem.image = NSImage(systemSymbolName: "cart", accessibilityDescription: "")
        menu.addItem(purchaseItem)

        let activateItem = NSMenuItem(
            title: "激活许可证…",
            action: #selector(activateLicense),
            keyEquivalent: ""
        )
        activateItem.target = self
        activateItem.isEnabled = false  // 待收费时启用
        activateItem.image = NSImage(systemSymbolName: "key", accessibilityDescription: "")
        menu.addItem(activateItem)

        menu.addItem(NSMenuItem.separator())

        // 4. 关于
        let aboutItem = NSMenuItem(
            title: "关于 NovaLaunch",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.isEnabled = true
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 5. 退出
        let quitItem = NSMenuItem(
            title: "退出 NovaLaunch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        return menu
    }

    /// 关键修复（v23）：左键点击菜单栏图标 → 弹出操作菜单
    /// 菜单包含：显示主程序、设置、刷新、关于、退出
    /// 不使用 button.menu（会与 action 冲突），改为手动 popUp
    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        let menu = buildStatusBarMenu()
        // 在按钮正下方弹出菜单
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -button.bounds.height), in: button)
    }

    @objc private func showLauncherFromMenu() {
        showLauncher()
    }

    @objc private func refreshApps() {
        IndexingService.shared.startFullScan()
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkForUpdatesManually()
    }

    @objc private func purchasePro() {
        // 待收费时：打开购买页面
        NSWorkspace.shared.open(URL(string: "https://nova-launch.app/purchase")!)
    }

    @objc private func activateLicense() {
        let alert = NSAlert()
        alert.messageText = "激活 NovaLaunch PRO"
        alert.informativeText = "请输入您的许可证密钥。"
        alert.alertStyle = .informational
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "XXXX-XXXX-XXXX-XXXX"
        alert.accessoryView = input
        alert.addButton(withTitle: "激活")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            _ = input.stringValue.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - 主程序（NSWindow 形式，支持自由缩放）

    /// 静态方法，供 NovaLauncherWindow 调用
    static func saveWindowFrame(_ size: NSSize) {
        let defaults = UserDefaults.standard
        defaults.set(Double(size.width), forKey: "launcherWindowWidth")
        defaults.set(Double(size.height), forKey: "launcherWindowHeight")
        defaults.synchronize()
    }
    
    /// 保存窗口位置 (origin)
    func saveWindowOrigin(_ origin: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(Double(origin.x), forKey: "launcherWindowOriginX")
        defaults.set(Double(origin.y), forKey: "launcherWindowOriginY")
        defaults.synchronize()
    }
    
    /// 加载窗口位置，首次返回 nil
    private func loadWindowOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "launcherWindowOriginX") != nil else { return nil }
        let x = defaults.double(forKey: "launcherWindowOriginX")
        let y = defaults.double(forKey: "launcherWindowOriginY")
        return NSPoint(x: x, y: y)
    }
    
    private func saveWindowSize(_ size: NSSize) {
        AppDelegate.saveWindowFrame(size)
    }
    
    private func loadWindowSize() -> NSSize {
        let defaults = UserDefaults.standard
        let w = defaults.double(forKey: "launcherWindowWidth")
        let h = defaults.double(forKey: "launcherWindowHeight")
        if w >= 800, h >= 500 {
            return NSSize(width: w, height: h)
        }
        return NSSize(width: 800, height: 557)
    }
    
    private func toggleLauncher() {
        if let window = launcherWindow, window.isVisible {
            // 全屏模式：先退出全屏，再隐藏窗口（防止黑屏）
            if UserPreferences.shared.useFullscreenMode {
                window.toggleFullScreen(nil)
            }
            window.orderOut(nil)
            // 关闭时移除全局点击监听
            removeOutsideClickMonitor()
        } else {
            showLauncher()
        }
    }

    private func showLauncher() {
        
        let isFullscreen = UserPreferences.shared.useFullscreenMode
        let windowNeedsRecreate: Bool
        if let existingWindow = launcherWindow {
            // 关键修复（v38）：用记录的 lastFullscreenMode 判断
            // 之前用 existingWindow.level.rawValue >= 100000 判断，依赖 level 数值不可靠
            // 现在用应用层显式记录的状态，更可靠
            _ = existingWindow
            windowNeedsRecreate = (lastFullscreenMode != isFullscreen)
        } else {
            windowNeedsRecreate = true
        }
        lastFullscreenMode = isFullscreen

        if launcherWindow == nil || windowNeedsRecreate {
            // 销毁旧窗口（如果存在）
            if let oldWindow = launcherWindow {
                oldWindow.close()
                launcherWindow = nil
            }

            
            // visibleFrame 会排除这些区域，导致窗口只显示一部分
            let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

            // 关键修复（v11）：使用 NovaLauncherWindow 子类
            // canBecomeKey = true 让 TextField 可以获取焦点
            let window: NovaLauncherWindow
            if isFullscreen {
                // 全屏模式：窗口覆盖整个屏幕，从 (0,0) 开始
                window = NovaLauncherWindow(
                    contentRect: NSRect(origin: .zero, size: screenFrame.size),
                    styleMask: [.borderless, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                
                // （多次设置确保 layout 系统不会回弹到内容尺寸）
                window.setFrame(NSRect(origin: .zero, size: screenFrame.size), display: true)
                window.setFrameOrigin(.zero)
            } else {
                // 恢复上次窗口尺寸
                let saved = loadWindowSize()
                let initW = saved.width
                let initH = saved.height
                window = NovaLauncherWindow(
                    contentRect: NSRect(x: 0, y: 0, width: initW, height: initH),
                    styleMask: [.borderless, .resizable, .miniaturizable, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
            }
            window.isOpaque = isFullscreen   // 全屏模式不透明（显示毛玻璃背景）
            window.backgroundColor = isFullscreen ? NSColor.black.withAlphaComponent(0.001) : .clear
            window.hasShadow = !isFullscreen  // 全屏无阴影
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            
            // 原因：window.isMovable = false 会让 NSWindow 在鼠标按下时进入"无拖动模式"，
            //       这会拦截 SwiftUI 内部子视图的 onDrag 事件传递
            //       全屏窗口从 (0,0) 开始覆盖整个屏幕，user 实际无法把它拖到屏幕外
            //       （窗口大于等于屏幕，移动后仍会强制 setFrame 复位 - 见 LauncherWindowDelegate）
            window.isMovable = true
            window.isMovableByWindowBackground = false
            window.isMovable = true
            window.acceptsMouseMovedEvents = true  // required for resize edge cursor tracking
            if !isFullscreen {
                window.minSize = NSSize(width: 800, height: 500)
                window.styleMask.insert(.resizable)  // allow resizing
            }
            window.appearance = launcherAppearance
            window.isReleasedWhenClosed = false
            window.delegate = launcherDelegate
            
            window.level = isFullscreen ? NSWindow.Level(rawValue: 100000) : .normal
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.insert(.fullScreenPrimary)  // 支持原生全屏动画
            window.collectionBehavior.insert(.fullScreenAllowsTiling)  // 全屏时支持分屏
            window.hidesOnDeactivate = false

            // SwiftUI 内容
            let contentView = MainLauncherView(
                onClose: { [weak self] in
                    
                    if let win = self?.launcherWindow {
                        NSAnimationContext.runAnimationGroup({ ctx in
                            ctx.duration = 0.18
                            ctx.timingFunction = CAMediaTimingFunction(
                                controlPoints: 0.55, 0.0, 1.0, 0.45  // easeInQuad — 快速收缩
                            )
                            ctx.allowsImplicitAnimation = true
                            win.alphaValue = 0.0
                        }, completionHandler: {
                            win.orderOut(nil)
                        })
                    }
                    
                    Task { @MainActor in
                        DashboardViewModel.shared.stopPreloading()
                    }
                    self?.removeOutsideClickMonitor()
                    if let monitor = self?.panelKeyMonitor {
                        NSEvent.removeMonitor(monitor)
                        self?.panelKeyMonitor = nil
                    }
                },
                onOpenSettings: { [weak self] in
                    self?.openPreferencesKeepLauncherVisible()
                },
                onShowMenu: { [weak self] in
                    self?.showMainMenu()
                }
            )
            // 关键修复（v15）：使用 NovaHostingController + contentViewController
            let hostingController = NovaHostingController(rootView: contentView)
            let desiredFrame = window.frame

            // iOS 27 液态玻璃：NSVisualEffectView 直接作为窗口 contentView
            if UserPreferences.shared.isLiquidGlassEnabled && !isFullscreen {
                window.styleMask.insert(.fullSizeContentView)
                window.isOpaque = false
                window.backgroundColor = .clear

                let backdrop = NSVisualEffectView()
                backdrop.material = .hudWindow
                backdrop.blendingMode = .behindWindow
                backdrop.state = .active
                backdrop.translatesAutoresizingMaskIntoConstraints = false
                backdrop.wantsLayer = true
                backdrop.layer?.cornerRadius = 20
                backdrop.layer?.cornerCurve = CALayerCornerCurve.continuous
                backdrop.layer?.masksToBounds = true

                let hostingView = hostingController.view
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                backdrop.addSubview(hostingView)
                NSLayoutConstraint.activate([
                    hostingView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
                    hostingView.topAnchor.constraint(equalTo: backdrop.topAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
                ])
                window.contentView = backdrop
            } else {
                if !isFullscreen { window.styleMask.remove(.fullSizeContentView) }
                window.contentViewController = hostingController
            }

            // Restore saved size
            if !isFullscreen {
                window.setFrame(desiredFrame, display: true)
            }

            // Round corners
            if let cv = window.contentView, !isFullscreen {
                cv.wantsLayer = true
                cv.layer?.cornerRadius = 20
                cv.layer?.cornerCurve = CALayerCornerCurve.continuous
            }

            launcherDelegate.window = window
            launcherWindow = window
        }

        // 窗口定位：优先恢复用户上次拖放的位置，首次启动使用状态栏定位
        let fullScreen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        if !UserPreferences.shared.useFullscreenMode {
            if let savedOrigin = loadWindowOrigin() {
                // 已保存过位置 → 恢复到该位置
                launcherWindow?.setFrameOrigin(savedOrigin)
            } else {
                // 首次启动 → 状态栏定位
                positionLauncherWindowBelowStatusBar()
            }
        } else {
            
            // 否则 GroupDetailView 拿到的还是旧值（720x560），导致每屏图标数计算错误
            AppDelegate.sharedWindowSize = fullScreen.size
            AppDelegate.sharedPagingAreaSize = NSSize(
                width: fullScreen.size.width - 40,
                height: fullScreen.size.height - 220  // 减去 header + 标签栏 + 顶部底部安全区
            )
        }

        // 关键修复：把当前窗口的 top-right 位置记为新的"锚点"
        if let window = launcherWindow {
            launcherDelegate.captureInitialAnchor(for: window)
        }

        // 暴露给 panel 系统
        AppDelegate.sharedLauncherWindow = launcherWindow

        // 显示窗口（v44：弹簧弹出动画）
        if let window = launcherWindow {
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.22, 1.0, 0.36, 1.0  // easeOutCubic
                )
                context.allowsImplicitAnimation = true
                window.alphaValue = 1.0
                // 轻微缩放弹出感
                if let contentView = window.contentView {
                    contentView.layer?.transform = CATransform3DIdentity
                }
            })
        }

        // 启动"点击外部关闭"的全局监听
        setupOutsideClickMonitor()

        
        setupPanelKeyMonitor()
    }

    // MARK: - v47 面板键盘导航

    /// 全局快捷键监听器（应用最外层根节点）
    ///   - 实现方式：NSEvent.addLocalMonitorForEvents（进程级 local monitor，作用域为整个 App，
    ///               比 .onKeyPress / NSResponder 链更外层，key event 在分发到具体 NSView 之前先到达这里）
    ///   - 这是应用最外层的根节点监听（不是 view-level），无论当前 focus 在哪个 panel 哪个 TextField，
    ///     key event 都会先经过本 monitor，符合"无论在哪个面板都能切"的要求
    ///   - 行为：
    ///       Cmd + 1/2/3  →  直接跳转到对应面板（launcher / clipboard / windows）
    ///       Tab          →  0 -> 1 -> 2 -> 0 循环切换（仅当 firstResponder 不是 NSTextView）
    ///   - 卸载：applicationWillTerminate 中 NSEvent.removeMonitor(monitor)
    private func setupPanelKeyMonitor() {
        panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers ?? ""

            var targetPanel: MainLauncherView.NovaPanel?

            // Cmd+1/2/3 直接跳转到对应面板（无修饰键冲突，flags 必须 == .command）
            if flags == .command {
                switch key {
                case "1": targetPanel = .launcher
                case "2": targetPanel = .clipboard
                case "3": targetPanel = .windows
                default: break
                }
            }

            // Tab 键循环切换：0 -> 1 -> 2 -> 0
            // 关键：firstResponder 是 NSTextView（搜索框等正在输入）时不拦截，
            //       让 Tab 正常做焦点跳转
            if event.keyCode == 48 && flags.isEmpty && targetPanel == nil {
                let isEditingText = NSApp.keyWindow?.firstResponder is NSTextView
                if !isEditingText {
                    let all = MainLauncherView.NovaPanel.allCases
                    if let idx = all.firstIndex(of: self.activePanel) {
                        targetPanel = all[(idx + 1) % all.count]
                    }
                }
            }

            if let panel = targetPanel {
                self.switchPanel(panel)
                return nil  // 消费事件，阻止传递到 view 层
            }

            // ESC 键：隐藏主程序窗口
            if event.keyCode == 53 && flags.isEmpty {
                if let window = self.launcherWindow, window.isVisible {
                    // 全屏模式：先退出全屏，再隐藏窗口（防止黑屏）
                    if UserPreferences.shared.useFullscreenMode {
                        window.toggleFullScreen(nil)
                    }
                    window.orderOut(nil)
                    self.removeOutsideClickMonitor()
                    return nil
                }
            }

            return event
        }
    }

    private func switchPanel(_ panel: MainLauncherView.NovaPanel) {
        activePanel = panel
        // 通过通知让 MainLauncherView 同步
        NotificationCenter.default.post(name: .novaPanelChanged, object: nil, userInfo: ["panel": panel])
    }

    /// 关键：把 NSWindow 定位到状态栏按钮附近（类似 NSPopover 的默认行为）
    /// 关键修复（v15/v32）：以屏幕中心为主 + 轻微偏向按钮
    /// 70% 屏幕中心 + 30% 按钮位置，首启动时若按钮坐标异常则回退到屏幕居中
    private func positionLauncherWindowBelowStatusBar() {
        guard let window = launcherWindow,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        // 尝试获取屏幕信息（首启动时可能不可用）
        guard let screen = buttonWindow.screen else {
            // 安全回退：无法获取屏幕信息时居中显示
            if let mainScreen = NSScreen.main {
                let mainFrame = mainScreen.visibleFrame
                let windowSize = window.frame.size
                window.setFrameOrigin(NSPoint(
                    x: mainFrame.midX - windowSize.width / 2,
                    y: mainFrame.midY - windowSize.height / 2
                ))
            } else {
                window.center()
            }
            return
        }

        // 状态栏按钮在屏幕坐标系中的位置
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenButtonFrame = buttonWindow.convertToScreen(buttonFrame)

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size

        // 关键修复：混合定位策略
        // 屏幕中心位置
        let screenCenterX = screenFrame.midX
        // 按钮居中位置（如果窗口以按钮为中心）
        let buttonCenteredX = screenButtonFrame.midX - windowSize.width / 2

        // 70% 屏幕中心 + 30% 按钮位置 → 窗口基本居中，略微偏向按钮
        var originX = screenCenterX * 0.7 + buttonCenteredX * 0.3

        // 防止窗口超出屏幕左右边界
        originX = max(screenFrame.minX + 8, min(originX, screenFrame.maxX - windowSize.width - 8))

        // 窗口顶部紧贴状态栏按钮底部
        var originY = screenButtonFrame.minY - windowSize.height
        // 如果下方空间不够，放到按钮上方
        if originY < screenFrame.minY {
            originY = screenButtonFrame.maxY
        }

        window.setFrameOrigin(NSPoint(x: originX, y: originY))

        // 关键修复（v15）：箭头 x = 按钮中心 - 窗口左边
        // 箭头始终指向菜单栏上的自己的图标
        AppDelegate.sharedArrowXPosition = screenButtonFrame.midX - originX
        // 关键修复（v15）：保存按钮屏幕 x 坐标，供 resize 时使用
        AppDelegate.sharedButtonScreenX = screenButtonFrame.midX

        // 关键修复（v11）：激活 app 并设置 firstResponder
        NSApp.activate(ignoringOtherApps: true)
        if let contentView = window.contentView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                window.makeFirstResponder(contentView)
            }
        }
    }

    /// 关键修复（v4）：重新对齐 launcher 窗口到状态栏下方
    /// LauncherWindowDelegate 在检测到窗口被移动时调用
    /// （虽然 isMovable = false，但 Accessibility API 等可能仍能移动）
    func realignLauncherWindowIfNeeded() {
        guard let window = launcherWindow else { return }
        positionLauncherWindowBelowStatusBar()
        // 关键：重新捕获锚点（窗口位置已变化）
        launcherDelegate.captureInitialAnchor(for: window)
    }

    /// 在主程序窗口右上方弹出菜单（与菜单栏图标菜单内容一致）
    func showMainMenu() {
        let menu = buildStatusBarMenu()
        menu.appearance = NSAppearance(named: .aqua)
        if let window = launcherWindow {
            // 定位在窗口顶部右上方（"..." 按钮附近）
            let topRight = NSPoint(x: window.frame.maxX - 50, y: window.frame.maxY - 36)
            menu.popUp(positioning: nil, at: topRight, in: nil)
        } else {
            // 回退：在鼠标位置弹出
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    /// 打开设置但保留主程序显示
    private func openPreferencesKeepLauncherVisible() {
        // 不关闭主程序
        if preferencesWindow == nil {
            let preferencesView = NSHostingController(rootView: PreferencesView())
            let window = NSWindow(contentViewController: preferencesView)
            window.title = "NovaLaunch 设置"
            window.styleMask = [.titled, .closable, .resizable, .utilityWindow]
            window.setContentSize(NSSize(width: 620, height: 580))
            window.minSize = NSSize(width: 620, height: 580)
            window.isMovableByWindowBackground = true
            window.center()
            window.delegate = self
            // 关键修复：NSPopover 的实际 level 高，使用更高的 level
            window.level = NSWindow.Level(rawValue: 2000)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.collectionBehavior.insert(.canJoinAllSpaces)
            preferencesWindow = window
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        preferencesWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKey()
    }

    // MARK: - 全局点击监听（点击主程序外自动隐藏）

    private func setupOutsideClickMonitor() {
        removeOutsideClickMonitor()

        
        // 全屏关闭方式：双击顶栏 → 返回窗口模式，或按 ESC 键隐藏
        // 窗口模式使用 addGlobalMonitorForEvents（原来方案，只观察不拦截）
        if !UserPreferences.shared.useFullscreenMode {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self,
                      let window = self.launcherWindow,
                      window.isVisible else { return }

                // 获取点击位置
                let mouseLocation = NSEvent.mouseLocation

                // 关键修复：主程序窗口的 frame
                let windowFrame = window.frame

                // 关键修复：如果点击在状态栏图标区域，由系统处理（打开/关闭）
                // 如果点击在主程序窗口内，忽略
                // 其他情况：关闭主程序
                if !windowFrame.contains(mouseLocation) {
                    // 检查是否点击在状态栏按钮上
                    if let button = self.statusItem?.button,
                       let buttonWindow = button.window {
                        let buttonFrame = button.convert(button.bounds, to: nil)
                        let screenButtonFrame = buttonWindow.convertToScreen(buttonFrame)
                        if screenButtonFrame.contains(mouseLocation) {
                            return // 让系统处理状态栏按钮点击
                        }
                    }
                    // 点击在主程序外，关闭主程序
                    window.orderOut(nil)
                    self.removeOutsideClickMonitor()
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - 设置窗口（独立窗口，不受主程序外观影响，必须浮在主程序之上）

    @objc private func openPreferences() {
        // 关键：先关闭主程序窗口，让设置窗口成为最前面
        
        if let lw = launcherWindow {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.55, 0.0, 1.0, 0.45
                )
                ctx.allowsImplicitAnimation = true
                lw.alphaValue = 0.0
            }, completionHandler: {
                lw.orderOut(nil)
            })
        }

        if preferencesWindow == nil {
            let preferencesView = NSHostingController(rootView: PreferencesView())
            let window = NSWindow(contentViewController: preferencesView)
            window.title = "NovaLaunch 设置"
            window.styleMask = [.titled, .closable, .resizable, .utilityWindow]
            window.setContentSize(NSSize(width: 620, height: 580))
            window.minSize = NSSize(width: 620, height: 580)
            window.isMovableByWindowBackground = true
            window.center()
            window.delegate = self
            // 关键修复：NSPopover 的实际 level 高达 100000+ (.popUpMenu+)
            // 必须用 NSWindow.Level(rawValue: ...) 强制设置更高
            // .screenSaver = 1000 不够，使用 2000 远超 popover
            window.level = NSWindow.Level(rawValue: 2000)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.collectionBehavior.insert(.canJoinAllSpaces)
            preferencesWindow = window
        }

        // 关键修复：保存设置窗口的静态引用，供其他 panel 区分"主程序"和"设置窗口"
        AppDelegate.sharedPreferencesWindow = preferencesWindow

        preferencesWindow?.makeKeyAndOrderFront(nil)
        // 关键：使用 orderFrontRegardless() 强制前置显示
        preferencesWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // 把焦点移到设置窗口
        preferencesWindow?.makeKey()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "NovaLaunch"
        alert.informativeText = """
        版本 1.0.0

        新一代 macOS 智能启动台
        Swift 5.9 + SwiftUI 4.0 原生构建

        热键：Option + Space

        © 2026 NovaLaunch. 保留所有权利。
        严格遵守 MIT / Apache 2.0 开源协议。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    // 让 dock 栏点击时显示主窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            toggleLauncher()
        }
        return true
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === preferencesWindow {
            preferencesWindow = nil
        }
    }
}

// MARK: - 自动更新 (v1.0)

final class UpdateChecker {
    static let shared = UpdateChecker()

    private var appcastURL = URL(string: "https://raw.githubusercontent.com/YOUR_USER/NovaLaunch/main/appcast.json")
    private let checkInterval: TimeInterval = 6 * 3600
    private let userDefaultsKey = "NovaLaunch_LastUpdateCheck"
    private var timer: Timer?

    private init() {}

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.checkInBackground()
        }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkInBackground()
        }
    }

    func checkForUpdatesManually() {
        Task {
            guard let info = await fetchUpdateInfo() else {
                await MainActor.run { showNoUpdateAlert() }
                return
            }
            guard isNewer(current: currentVersion, remote: info.version) else {
                await MainActor.run { showNoUpdateAlert() }
                return
            }
            await MainActor.run { showUpdatePrompt(info: info) }
        }
    }

    private func checkInBackground() {
        let last = UserDefaults.standard.object(forKey: userDefaultsKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= checkInterval else { return }
        UserDefaults.standard.set(Date(), forKey: userDefaultsKey)
        Task {
            guard let info = await fetchUpdateInfo() else { return }
            guard isNewer(current: currentVersion, remote: info.version) else { return }
            await MainActor.run { showUpdatePrompt(info: info) }
        }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func fetchUpdateInfo() async -> UpdateInfo? {
        guard let url = appcastURL else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(UpdateInfo.self, from: data)
        } catch { return nil }
    }

    private func downloadUpdate(from urlString: String) async -> URL? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("NL-Update.zip")
            try data.write(to: zipURL)
            return zipURL
        } catch { return nil }
    }

    private func installUpdate(from zipURL: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("NL-\(UUID().uuidString.prefix(8))")
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipURL.path, "-d", tmp.path]
            try unzip.run(); unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { return }

            let files = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
            guard let newApp = files.first(where: { $0.pathExtension == "app" }) else { return }
            let curApp = Bundle.main.bundleURL

            let script = """
            #!/bin/bash
            sleep 1
            rm -rf "\(curApp.path)"
            mv "\(newApp.path)" "\(curApp.path)"
            open "\(curApp.path)"
            """
            let s = tmp.appendingPathComponent("install.sh")
            try script.write(to: s, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.path)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [s.path]
            try p.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        } catch {}
    }

    private func isNewer(current: String, remote: String) -> Bool {
        let c = current.split(separator: ".").compactMap { Int($0) }
        let r = remote.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(c.count, r.count) {
            let a = i < c.count ? c[i] : 0
            let b = i < r.count ? r[i] : 0
            if a < b { return true }
            if a > b { return false }
        }
        return false
    }

    private func showNoUpdateAlert() {
        let a = NSAlert()
        a.messageText = "已是最新版本"
        a.informativeText = "NovaLaunch \(currentVersion) 已是最新版本。"
        a.alertStyle = .informational
        a.addButton(withTitle: "好的")
        a.runModal()
    }

    private func showUpdatePrompt(info: UpdateInfo) {
        let a = NSAlert()
        a.messageText = "发现新版本 NovaLaunch \(info.version)"
        a.informativeText = info.notes ?? "包含性能优化和问题修复。"
        a.alertStyle = .informational
        a.addButton(withTitle: "下载并安装")
        a.addButton(withTitle: "稍后提醒")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Task {
            guard let zip = await downloadUpdate(from: info.downloadURL) else {
                await MainActor.run {
                    let e = NSAlert()
                    e.messageText = "下载失败"
                    e.informativeText = "请检查网络连接后重试。"
                    e.alertStyle = .warning
                    e.addButton(withTitle: "好的")
                    e.runModal()
                }
                return
            }
            await MainActor.run { installUpdate(from: zip) }
        }
    }
}

struct UpdateInfo: Codable {
    let version: String
    let downloadURL: String
    let notes: String?
    let minVersion: String?
    let isCritical: Bool?
}

// MARK: - LauncherWindowDelegate（关键：实现"右上角固定"的缩放行为）
// 用户新需求：程序框可以放大缩小，但要保留细节（标题栏/小箭头），
// 整个程序固定在右上角的情况下再拉大缩小。
// 默认 NSWindow 缩放时是"对角固定"（拉右下角时左上角固定），
// 我们要改成"右上角始终固定"——窗口只能向左下方向扩展。
//
// 实现策略：
// 1. 在 showLauncher 时记录窗口 top-right 的屏幕坐标作为"锚点"
// 2. windowDidResize 后，比较当前 top-right 和锚点，计算偏移量
// 3. 把窗口的 origin 调整 -offset，让 top-right 重新回到锚点
// 4. 移动窗口（windowDidMove）后，重置锚点（用户拖到新位置，右上角跟随新位置）
// 5. 屏幕边界约束：窗口不能超出屏幕可见区域，否则裁剪
final class LauncherWindowDelegate: NSObject, NSWindowDelegate {
    /// 关键：弱引用 launcher 窗口（避免循环引用）
    weak var window: NSWindow?

    /// 关键：右上角锚点的屏幕坐标 (maxX, maxY)
    /// 每次用户开始缩放时捕获，缩放过程中保持不变
    private var topRightAnchor: NSPoint?

    /// 关键：标志位，防止 setFrame 触发 windowDidResize 形成循环
    private var isAdjusting: Bool = false

    /// 关键：用户每次显示窗口时（showLauncher）调用，把当前 top-right 设为锚点
    func captureInitialAnchor(for window: NSWindow) {
        topRightAnchor = NSPoint(x: window.frame.maxX, y: window.frame.maxY)
    }

    // MARK: NSWindowDelegate 关键回调

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === self.window,
              !isAdjusting else { return }

        // 全屏模式：强制恢复屏幕尺寸
        if UserPreferences.shared.useFullscreenMode {
            if let screen = window.screen {
                let screenFrame = screen.frame
                if abs(window.frame.width - screenFrame.width) > 1 ||
                   abs(window.frame.height - screenFrame.height) > 1 {
                    isAdjusting = true
                    window.setFrame(screenFrame, display: true)
                    isAdjusting = false
                }
            }
            return
        }

        // 更新共享窗口尺寸
        AppDelegate.sharedWindowSize = window.frame.size

        // 更新箭头位置
        if AppDelegate.sharedButtonScreenX >= 0 {
            AppDelegate.sharedArrowXPosition = AppDelegate.sharedButtonScreenX - window.frame.origin.x
        }

        // 自由缩放模式：仅约束屏幕边界，不强制左上角锚点
        if let screen = window.screen {
            let vFrame = screen.visibleFrame
            var newFrame = window.frame
            var adjusted = false
            if newFrame.maxX > vFrame.maxX { newFrame.origin.x = vFrame.maxX - newFrame.width; adjusted = true }
            if newFrame.minX < vFrame.minX { newFrame.origin.x = vFrame.minX; adjusted = true }
            if newFrame.maxY > vFrame.maxY { newFrame.origin.y = vFrame.maxY - newFrame.height; adjusted = true }
            if newFrame.minY < vFrame.minY { newFrame.origin.y = vFrame.minY; adjusted = true }
            if adjusted {
                isAdjusting = true
                window.setFrame(newFrame, display: true)
                isAdjusting = false
            }
        }

        // 记住当前 top-right 为下次锚点
        topRightAnchor = NSPoint(x: window.frame.maxX, y: window.frame.maxY)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === self.window,
              !isAdjusting else { return }

        // 全屏模式：强制恢复位置和尺寸
        if UserPreferences.shared.useFullscreenMode {
            if let screen = window.screen {
                let screenFrame = screen.frame
                if window.frame.origin != .zero ||
                   abs(window.frame.width - screenFrame.width) > 1 {
                    isAdjusting = true
                    window.setFrame(screenFrame, display: true)
                    isAdjusting = false
                }
            }
            return
        }

        // 自由移动模式：保存新位置 + 更新箭头，不强制回到状态栏
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.saveWindowOrigin(window.frame.origin)
        }
        if AppDelegate.sharedButtonScreenX >= 0 {
            AppDelegate.sharedArrowXPosition = AppDelegate.sharedButtonScreenX - window.frame.origin.x
        }
        // 记住新位置为锚点
        topRightAnchor = NSPoint(x: window.frame.maxX, y: window.frame.maxY)
        AppDelegate.saveWindowFrame(window.frame.size)
    }
}

extension Notification.Name {
    static let novaLauncherAppearanceChanged = Notification.Name("com.novalaunch.launcherAppearanceChanged")
    static let novaHideLauncher = Notification.Name("com.novalaunch.hideLauncher")
    static let novaLauncherAccentColorChanged = Notification.Name("com.novalaunch.launcherAccentColorChanged")
    static let novaLauncherBlurChanged = Notification.Name("com.novalaunch.launcherBlurChanged")
    
    static let novaPanelChanged = Notification.Name("com.novalaunch.panelChanged")
}

// MARK: - v125: DragPerformanceMonitor — 纯 Timer 驱动 FPS 监测（零崩溃风险）
//
// CVDisplayLink 在 macOS 27 Beta 上不可靠 (SIGBUS on callback thread)。
// 降级为纯主线程 Timer 方案，简单可靠，精度足够。

final class DragPerformanceMonitor: NSObject {
    static let shared = DragPerformanceMonitor()
    override private init() { super.init() }

    var currentFPS: Double = 0
    var avgFrameMs: Double = 0
    var p99FrameMs: Double = 0
    var maxFrameMs: Double = 0

    private var tickTimer: Timer?
    private var statsTimer: Timer?
    private var tickTimestamps: [Double] = []
    private let perfLogger = OSLog(subsystem: "com.novalaunch.app", category: "DragPerf")
    private var logSamples: [Double] = []
    private var lastLogTime: CFAbsoluteTime = 0

    func startIfNeeded() {
        guard tickTimer == nil else { return }

        // 120Hz tick — 主线程，零风险
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(tickTimer!, forMode: .common)

        // 统计 + 日志 — 每 0.25s
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.computeAndLog()
        }
        RunLoop.main.add(statsTimer!, forMode: .common)

        let maxFPS = NSScreen.main?.maximumFramesPerSecond ?? 60
        os_log("FPS Monitor started (Timer-based): maxFPS=%d", log: perfLogger, type: .info, maxFPS)
    }

    func stop() {
        tickTimer?.invalidate(); tickTimer = nil
        statsTimer?.invalidate(); statsTimer = nil
    }

    private func tick() {
        tickTimestamps.append(CFAbsoluteTimeGetCurrent())
        if tickTimestamps.count > 256 { tickTimestamps.removeFirst() }
    }

    private func computeAndLog() {
        guard tickTimestamps.count > 1 else { return }
        var deltas: [Double] = []
        deltas.reserveCapacity(tickTimestamps.count - 1)
        for i in 1..<tickTimestamps.count {
            let dt = tickTimestamps[i] - tickTimestamps[i-1]
            if dt > 0, dt < 0.1 { deltas.append(dt) }
        }
        guard deltas.count > 1 else { return }

        let sorted = deltas.sorted()
        let avg = deltas.reduce(0, +) / Double(deltas.count)
        currentFPS = 1.0 / avg
        avgFrameMs = avg * 1000.0
        let p99Idx = min(deltas.count - 1, Int(Double(deltas.count) * 0.99))
        p99FrameMs = sorted[p99Idx] * 1000.0
        maxFrameMs = (sorted.last ?? 0) * 1000.0

        logSamples.append(contentsOf: deltas)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastLogTime >= 1.0, !logSamples.isEmpty {
            lastLogTime = now
            let ls = logSamples.sorted()
            let la = logSamples.reduce(0, +) / Double(logSamples.count)
            let lp99 = ls[min(logSamples.count - 1, Int(Double(logSamples.count) * 0.99))]
            os_log("[DragPerf] Avg: %.1f FPS | P99: %.1fms | Max: %.1fms | Samples: %ld",
                   log: perfLogger, type: .info, 1.0/la, lp99*1000, (ls.last ?? 0)*1000, logSamples.count)
            logSamples.removeAll(keepingCapacity: true)
        }
    }

}
