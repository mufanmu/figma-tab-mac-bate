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

    private var panel: NSPanel?
    private var pollingTask: Task<Void, Never>?
    private var canvas: CanvasInfo?
    private var screenHeight: Double = 0
    private var cycleCount: Int = 0
    private var emptyCount: Int = 0

    let api = FigmaAPI(client: CDPClient())

    func applicationDidFinishLaunching(_ notification: Notification) {
        screenHeight = Double(NSScreen.main?.frame.height ?? 1055)
        setupPanel()
        Task { await connectAndStartPolling() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTask?.cancel()
        api.disconnect()
    }

    private func setupPanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let hostingView = ToolbarHostingView(
            rootView: ToolbarView(delegate: self).environmentObject(self)
        )
        hostingView.setFrameSize(NSSize(width: 400, height: 56))
        panel.contentView = hostingView
        panel.orderFront(nil)
        self.panel = panel
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
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.figma.Desktop" {
                    panel?.orderOut(nil)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }

                cycleCount += 1

                let (node, vp) = await api.getState()

                // 当前 target 无选中切 Figma 在前台：尝试跳到另一个 target
                if node == nil {
                    emptyCount += 1
                    if emptyCount == 100 {  // ~1.6s 无选中
                        emptyCount = 0
                        let ok = await api.discoverAndSkip(skipURL: api.client.currentURL)
                        if ok { canvas = await api.getCanvasInfo() }
                    }
                } else {
                    emptyCount = 0
                }
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

        let nodeCX = node.x + node.width / 2
        let screenGap = 20.0
        let gapCanvas = screenGap * vb.height / canvas.height

        var domX = canvas.left + (nodeCX - vb.x) / vb.width * canvas.width
        var isBelow = false
        var domY = canvas.top + (node.y - gapCanvas - vb.y) / vb.height * canvas.height
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
        let cocoaX = qx - panel.frame.width / 2
        let cocoaY = isBelow ? screenHeight - qy - panel.frame.height : screenHeight - qy

        let idealSize = panel.contentView?.fittingSize ?? NSSize(width: 300, height: 56)
        let newWidth = min(idealSize.width, 1200)
        if abs(panel.frame.width - newWidth) > 5 {
            let oldWidth = panel.frame.width
            panel.setContentSize(NSSize(width: newWidth, height: 56))
            panel.setFrameOrigin(NSPoint(x: cocoaX + (oldWidth - newWidth) / 2, y: cocoaY))
        } else {
            panel.setFrameOrigin(NSPoint(x: cocoaX, y: cocoaY))
        }

        panel.orderFront(nil)
    }

    /// 前台 Figma 窗口信息（位置 + 标题），用于多窗口切换检测
    /// 前台 Figma 窗口（按 layer 取最上层），用于多窗口切换检测
    private func findFigmaWindow() -> (x: Double, y: Double, w: Double, h: Double, title: String)? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        var best: (x: Double, y: Double, w: Double, h: Double, title: String, layer: Int)? = nil
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "Figma",
                  let b = info[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
            else { continue }
            let title = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if best == nil || layer > best!.layer {
                best = (x, y, w, h, title, layer)
            }
        }
        guard let result = best else { return nil }
        return (result.x, result.y, result.w, result.h, result.title)
    }

    /// 旧版兼容：仅返回位置（被 updatePanelPosition 调用）
    private func findFigmaWindowQuartz() -> (x: Double, y: Double, w: Double, h: Double)? {
        guard let fw = findFigmaWindow() else { return nil }
        return (fw.x, fw.y, fw.w, fw.h)
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
