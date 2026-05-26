import Foundation

final class FigmaAPI: @unchecked Sendable {
    private let client: CDPClient

    init(client: CDPClient) {
        self.client = client
    }

    nonisolated func discoverAndConnect(port: Int = 9222) async -> Bool {
        guard let url = URL(string: "http://localhost:\(port)/json") else { return false }

        let targets: [[String: Any]]
        do {
            let data = try Data(contentsOf: url)
            targets = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        } catch { return false }

        for t in targets {
            let targetURL = t["url"] as? String ?? ""
            let wsURL = t["webSocketDebuggerUrl"] as? String ?? ""
            if wsURL.isEmpty || targetURL.contains("shell.html") { continue }

            if targetURL.contains("figma.com/design/")
                || targetURL.contains("figma.com/file/")
                || targetURL.contains("figma.com/board/") {
                return await client.connect(to: wsURL)
            }
        }
        return false
    }

    private nonisolated func execJS(_ js: String, awaitPromise: Bool = false) async -> String? {
        var params: [String: Any] = ["expression": js, "returnByValue": true, "timeout": 8000]
        if awaitPromise { params["awaitPromise"] = true }
        return await client.send("Runtime.evaluate", params: params)
    }

    nonisolated func getState() async -> (node: NodeProperties?, viewport: ViewportInfo?) {
        let js = """
        (() => {
            var s = figma.currentPage.selection;
            var n = (s && s.length > 0) ? s[0] : null;
            var vb = figma.viewport.bounds;
            var vp = {
                zoom: figma.viewport.zoom,
                centerX: figma.viewport.center.x,
                centerY: figma.viewport.center.y,
                bounds: vb ? { x: vb.x, y: vb.y, width: vb.width, height: vb.height } : null
            };
            if (!n) return JSON.stringify({ vp: vp, node: null });
            var info = {
                id: n.id, name: n.name, type: n.type,
                width: n.width, height: n.height, x: n.x, y: n.y,
                opacity: n.opacity, visible: n.visible, locked: n.locked,
                cornerRadius: n.cornerRadius,
                selectionCount: s.length,
                allTypes: s.map(function(x) { return x.type; })
            };
            if (n.type === 'TEXT') {
                info.characters = n.characters ? n.characters.slice(0, 100) : '';
                info.fontSize = n.fontSize;
                if (n.fontName) { info.fontName = n.fontName.family; info.fontWeight = n.fontName.style; }
                info.textAlign = n.textAlignHorizontal;
                if (n.lineHeight && n.lineHeight.value !== undefined) info.lineHeight = n.lineHeight.value;
                if (n.letterSpacing && n.letterSpacing.value !== undefined) info.letterSpacing = n.letterSpacing.value;
            }
            if (n.fills && n.fills.length > 0 && n.fills[0].type === 'SOLID') {
                info.fillColor = n.fills[0].color;
                info.fillOpacity = n.fills[0].opacity;
            }
            if (n.strokes && n.strokes.length > 0 && n.strokes[0].type === 'SOLID') {
                info.strokeColor = n.strokes[0].color;
                info.strokeWeight = n.strokeWeight;
            }
            return JSON.stringify({ vp: vp, node: info });
        })()
        """
        guard let json = await execJS(js),
              let data = json.data(using: .utf8) else { return (nil, nil) }
        struct State: Codable {
            let node: NodeProperties?
            let vp: ViewportInfo
        }
        guard let state = try? JSONDecoder().decode(State.self, from: data) else { return (nil, nil) }
        return (state.node, state.vp)
    }

    nonisolated func getViewport() async -> ViewportInfo? {
        let js = """
        JSON.stringify({
            zoom: figma.viewport.zoom,
            centerX: figma.viewport.center.x,
            centerY: figma.viewport.center.y
        })
        """
        guard let json = await execJS(js),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ViewportInfo.self, from: data)
    }

    nonisolated func setFillColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) async -> Bool {
        let r = await execJS("""
        (() => { var s = figma.currentPage.selection; if (!s || s.length === 0) return 'no sel';
        s[0].fills = [{type:'SOLID',color:{r:\(r),g:\(g),b:\(b)},opacity:\(a)}]; return 'ok'; })()
        """)
        return r?.contains("ok") ?? false
    }

    nonisolated func setOpacity(_ opacity: Double) async -> Bool {
        let r = await execJS("""
        (() => { var s = figma.currentPage.selection; if (!s || s.length === 0) return 'no sel';
        s[0].opacity = \(opacity); return 'ok'; })()
        """)
        return r?.contains("ok") ?? false
    }

    nonisolated func setCornerRadius(_ radius: Double) async -> Bool {
        let r = await execJS("""
        (() => { var s = figma.currentPage.selection; if (!s || s.length === 0) return 'no sel';
        s[0].cornerRadius = \(radius); return 'ok'; })()
        """)
        return r?.contains("ok") ?? false
    }

    nonisolated func setFontSize(_ size: Double) async -> Bool {
        let r = await execJS("""
        (async () => { var s = figma.currentPage.selection; if (!s || s.length === 0) return 'no sel';
        var n = s[0]; if (n.type !== 'TEXT') return 'not text';
        await figma.loadFontAsync(n.fontName); n.fontSize = \(size); return 'ok'; })()
        """, awaitPromise: true)
        return r?.contains("ok") ?? false
    }

    nonisolated func setTextAlign(_ align: String) async -> Bool {
        let r = await execJS("""
        (() => { var s = figma.currentPage.selection; if (!s || s.length === 0) return 'no sel';
        var n = s[0]; if (n.type !== 'TEXT') return 'not text';
        n.textAlignHorizontal = '\(align)'; return 'ok'; })()
        """)
        return r?.contains("ok") ?? false
    }

    nonisolated func getCanvasInfo() async -> CanvasInfo? {
        let js = """
        (() => {
            var canvases = document.querySelectorAll('canvas');
            var best = null, maxArea = 0;
            for (var c of canvases) {
                var r = c.getBoundingClientRect();
                var a = r.width * r.height;
                if (a > maxArea) { best = r; maxArea = a; }
            }
            if (!best) return null;
            return JSON.stringify({
                left: Math.round(best.left),
                top: Math.round(best.top),
                width: Math.round(best.width),
                height: Math.round(best.height)
            });
        })()
        """
        guard let json = await execJS(js),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CanvasInfo.self, from: data)
    }

    nonisolated func getScreenInfo() async -> (sx: Double, sy: Double, screenH: Double)? {
        let js = """
        JSON.stringify({
            sx: window.screenX || window.screenLeft || 0,
            sy: window.screenY || window.screenTop || 0,
            sh: screen.height
        })
        """
        guard let json = await execJS(js),
              let data = json.data(using: .utf8) else { return nil }
        struct SI: Codable { let sx: Double; let sy: Double; let sh: Double }
        guard let si = try? JSONDecoder().decode(SI.self, from: data) else { return nil }
        return (si.sx, si.sy, si.sh)
    }

    nonisolated func disconnect() { client.disconnect() }
}
