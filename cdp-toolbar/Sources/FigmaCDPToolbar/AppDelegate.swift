import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var selectedNode: NodeProperties?
    @Published var viewport: ViewportInfo?
    @Published var isConnected = false
    @Published var statusText = "启动中..."

    private var panel: NSPanel?
    private var pollingTask: Task<Void, Never>?
    private var canvas: CanvasInfo?
    private var screenHeight: Double = 0

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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: FigmaTokens.toolbarHeight + 12),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 280, height: 40)

        let hostingView = NSHostingView(
            rootView: ToolbarView(delegate: self).environmentObject(self)
                .frame(minWidth: 400, maxWidth: 600)
        )
        hostingView.setFrameSize(NSSize(width: 420, height: FigmaTokens.toolbarHeight + 12))
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
            startPolling()
        } else {
            statusText = "连接失败"
        }
    }

    private func startPolling() {
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
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
        guard let panel = panel, let node = selectedNode, let vp = viewport,
              let vb = vp.bounds, let canvas = canvas, let fw = findFigmaWindowQuartz() else {
            return
        }

        let nodeCX = node.x + node.width / 2
        let screenGap = 20.0
        let gapCanvas = screenGap * vb.height / canvas.height

        var domX = canvas.left + (nodeCX - vb.x) / vb.width * canvas.width

        var isBelow = false
        var domY = canvas.top + (node.y - gapCanvas - vb.y) / vb.height * canvas.height
        if domY < 0 {
            isBelow = true
            let belowOffset = 20.0
            domX = canvas.left + canvas.width / 2
            domY = canvas.top + canvas.height * 2 / 3
            domY = max(0, min(domY, canvas.height - panel.frame.height))
        } else {
            domY = max(0, domY)
        }

        let titleBarH = max(0, fw.height - canvas.height)
        let qx = fw.x + domX
        let qy = fw.y + titleBarH + domY

        let cocoaX = qx - panel.frame.width / 2
        let cocoaY = isBelow
            ? screenHeight - qy - panel.frame.height
            : screenHeight - qy

        panel.setFrameOrigin(NSPoint(x: cocoaX, y: cocoaY))
        panel.orderFront(nil)
    }

    private func findFigmaWindowQuartz() -> (x: Double, y: Double, width: Double, height: Double)? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "Figma",
                  let bounds = info[kCGWindowBounds as String] as? [String: Double],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"]
            else { continue }
            return (x, y, w, h)
        }
        return nil
    }
}
