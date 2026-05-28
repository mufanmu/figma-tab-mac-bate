import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var selectedNode: NodeProperties?
    @Published var viewport: ViewportInfo?
    @Published var isConnected = false
    @Published var statusText = "启动中..."
    @Published var fonts: [FontInfo] = []
    @Published var fontsLoaded = false
    @Published var fontLoadCount = 0
    @Published var isReconnecting = false
    @Published var panelWidth: CGFloat = 498

    private var panel: NSPanel?
    private var pollingTask: Task<Void, Never>?
    private var canvas: CanvasInfo?
    private var screenHeight: Double = 0
    private var clickMonitor: Any?
    /// 点击窗口编号变化时设置此标志，轮询循环内执行重连
    private var pendingReconnect = false

    let api = FigmaAPI(client: CDPClient())

    func applicationDidFinishLaunching(_ notification: Notification) {
        screenHeight = Double(NSScreen.main?.frame.height ?? 1055)
        setupPanel()
        setupClickMonitor()
        Task { await connectAndStartPolling() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        pollingTask?.cancel()
        api.disconnect()
    }

    private func setupPanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let hostingView = ToolbarHostingView(
            rootView: ToolbarView(delegate: self).environmentObject(self)
        )
        hostingView.setFrameSize(NSSize(width: panelWidth, height: 44))
        panel.contentView = hostingView
        self.panel = panel
    }

    /// 安全区域高度：Figma 窗口顶部 64px，点击此处 = 点击空白处
    private let safeAreaHeight: CGFloat = 72

    /// 全局鼠标点击监听：点击 Figma 窗口顶部安全区域时标记 pendingReconnect
    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let pos = NSEvent.mouseLocation
            // 检查点击是否在任一 Figma 窗口的顶部安全区域内
            guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]] else { return }
            for info in list {
                guard let owner = info[kCGWindowOwnerName as String] as? String,
                      owner == "Figma",
                      let b = info[kCGWindowBounds as String] as? [String: Double],
                      let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
                else { continue }
                // CGWindow 左下角原点，顶部 = y + h
                if pos.x >= x && pos.x <= x + w && pos.y >= y + h - safeAreaHeight && pos.y <= y + h {
                    self.pendingReconnect = true
                    return
                }
            }
        }
    }

    private func connectAndStartPolling() async {
        let ok = await api.discoverAndConnect()
        if ok {
            isConnected = true
            statusText = "已连接 - 请在 Figma 选中元素"
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            canvas = await api.getCanvasInfo()
            loadFontsInBackground()
            startPolling()
        } else {
            statusText = "连接失败"
        }
    }

    /// 菜单栏手动重连
    func reconnect() async {
        isReconnecting = true
        statusText = "重新连接中..."
        pollingTask?.cancel()
        api.disconnect()
        selectedNode = nil
        viewport = nil
        panel?.orderOut(nil)
        await connectAndStartPolling()
    }

    func loadFontsIfNeeded() {
        guard !fontsLoaded else { return }
        fontsLoaded = true
        let localAPI = api
        Task { @MainActor in
            let dict = await localAPI.loadFonts()
            var list: [FontInfo] = []
            for (family, styles) in dict.sorted(by: { $0.key < $1.key }) {
                list.append(FontInfo(family: family, styles: styles))
            }
            self.fonts = list
            self.fontLoadCount = min(50, list.count)
        }
    }

    private func loadFontsInBackground() { loadFontsIfNeeded() }

    func expandToInclude(font: String) {
        guard fontLoadCount < fonts.count else { return }
        let idx = fonts.firstIndex(where: { $0.family == font })
        guard let idx = idx, idx >= fontLoadCount else { return }
        fontLoadCount = min(idx + 10, fonts.count)
    }

    func loadMoreFonts() {
        guard fontLoadCount > 0, fontLoadCount < fonts.count else { return }
        let newCount = min(fontLoadCount + 50, fonts.count)
        guard newCount != fontLoadCount else { return }
        fontLoadCount = newCount
    }

    /// 全量加载字体（供搜索使用，不受分页限制）
    func loadAllFontsForSearch() {
        guard !fontsLoaded else {
            fontLoadCount = fonts.count
            return
        }
        fontsLoaded = true
        let localAPI = api
        Task { @MainActor in
            let dict = await localAPI.loadFonts()
            var list: [FontInfo] = []
            for (family, styles) in dict.sorted(by: { $0.key < $1.key }) {
                list.append(FontInfo(family: family, styles: styles))
            }
            self.fonts = list
            self.fontLoadCount = list.count
        }
    }

    private func startPolling() {
        isReconnecting = false
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.figma.Desktop" {
                    panel?.orderOut(nil)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }

                // 点击虚拟空白处 → 取消选中 + 切换到另一个 target
                if pendingReconnect {
                    pendingReconnect = false
                    _ = await api.clearSelection()
                    selectedNode = nil
                    viewport = nil
                    panel?.orderOut(nil)
                    let ok = await api.discoverAndSkip(skipURL: api.client.currentURL)
                    if ok { canvas = await api.getCanvasInfo() }
                }

                let (node, vp) = await api.getState()
                self.selectedNode = node
                self.viewport = vp
                if let n = node {
                    self.statusText = "\(n.type.rawValue): \(n.name)"
                } else {
                    self.statusText = "已连接 - 请在 Figma 中选中元素"
                }
                self.updatePanelPosition()
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
        }
    }

    func updatePanelPosition() {
        guard let panel = panel else { return }
        guard let node = selectedNode,
              (node.type == .text || node.type.isShape),
              let vp = viewport, let vb = vp.bounds,
              let canvas = canvas, let fw = findFigmaWindowQuartz()
        else { panel.orderOut(nil); return }

        let nodeCX = node.absoluteX + node.width / 2
        let screenGap = 20.0
        let gapCanvas = screenGap * vb.height / canvas.height

        var domX = canvas.left + (nodeCX - vb.x) / vb.width * canvas.width
        var isBelow = false
        var domY = canvas.top + (node.absoluteY - gapCanvas - vb.y) / vb.height * canvas.height
        if domY < 0 {
            isBelow = true
            domX = canvas.left + canvas.width / 2
            domY = canvas.top + canvas.height * 2 / 3
            domY = max(0, min(domY, canvas.height - panel.frame.height))
        } else {
            domY = max(0, domY)
        }

        let titleBarH = max(0, fw.h - canvas.height)
        let qx = fw.x + domX
        let qy = fw.y + titleBarH + domY
        let cocoaY = isBelow ? screenHeight - qy - panel.frame.height : screenHeight - qy

        panel.setContentSize(NSSize(width: panelWidth, height: 44))
        panel.setFrameOrigin(NSPoint(x: qx - panelWidth / 2, y: cocoaY))

        panel.orderFront(nil)
    }

    /// 前台 Figma 窗口（按 layer 取最上层）
    private func findFigmaWindow() -> (x: Double, y: Double, w: Double, h: Double)? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        var best: (x: Double, y: Double, w: Double, h: Double, layer: Int)? = nil
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "Figma",
                  let b = info[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
            else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if best == nil || layer > best!.layer {
                best = (x, y, w, h, layer)
            }
        }
        guard let result = best else { return nil }
        return (result.x, result.y, result.w, result.h)
    }

    private func findFigmaWindowQuartz() -> (x: Double, y: Double, w: Double, h: Double)? {
        guard let fw = findFigmaWindow() else { return nil }
        return (fw.x, fw.y, fw.w, fw.h)
    }

    /// 返回指定坐标所在的 Figma 窗口编号
    private func figmaWindowAt(_ point: CGPoint) -> Int? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "Figma",
                  let b = info[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
            else { continue }
            if point.x >= x && point.x <= x + w && point.y >= y && point.y <= y + h {
                return info[kCGWindowNumber as String] as? Int
            }
        }
        return nil
    }
}

/// 浮动面板 — 允许成为 Key Window 以支持 TextField 输入，但不激活 app
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class ToolbarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
