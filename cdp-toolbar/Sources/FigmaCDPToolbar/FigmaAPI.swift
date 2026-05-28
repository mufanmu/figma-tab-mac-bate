import Foundation

final class FigmaAPI: @unchecked Sendable {
    let client: CDPClient

    init(client: CDPClient) { self.client = client }

    nonisolated func discoverAndConnect(port: Int = 9222) async -> Bool {
        return await discoverAndSkip(port: port, skipURL: client.currentURL)
    }

    /// 发现 CDP 目标，跳过指定 URL，连接到第一个其他可用目标
    nonisolated func discoverAndSkip(port: Int = 9222, skipURL: String) async -> Bool {
        guard let url = URL(string: "http://localhost:\(port)/json") else { return false }
        let targets: [[String: Any]]
        do {
            let d = try Data(contentsOf: url)
            targets = (try JSONSerialization.jsonObject(with: d) as? [[String: Any]]) ?? []
        } catch { return false }
        for t in targets {
            let u = t["url"] as? String ?? ""
            let ws = t["webSocketDebuggerUrl"] as? String ?? ""
            if ws.isEmpty || u.contains("shell.html") { continue }
            if u.contains("figma.com/design/") || u.contains("figma.com/file/") || u.contains("figma.com/board/") {
                if ws == skipURL { continue }
                return await client.connect(to: ws)
            }
        }
        return false
    }

    private nonisolated func exec(_ js: String, ap: Bool = false) async -> String? {
        var p: [String: Any] = ["expression": js, "returnByValue": true, "timeout": 10000]
        if ap { p["awaitPromise"] = true }
        return await client.send("Runtime.evaluate", params: p)
    }

    nonisolated func getState() async -> (node: NodeProperties?, viewport: ViewportInfo?) {
        guard let json = await exec(stateJS),
              let d = json.data(using: .utf8) else { return (nil, nil) }
        struct S: Codable { let node: NodeProperties?; let vp: ViewportInfo }
        guard let s = try? JSONDecoder().decode(S.self, from: d) else { return (nil, nil) }
        return (s.node, s.vp)
    }

    nonisolated func getViewport() async -> ViewportInfo? {
        let js = "JSON.stringify({zoom:figma.viewport.zoom,centerX:figma.viewport.center.x,centerY:figma.viewport.center.y})"
        guard let json = await exec(js), let d = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ViewportInfo.self, from: d)
    }

    nonisolated func getCanvasInfo() async -> CanvasInfo? {
        guard let json = await exec("""
        (()=>{var cs=document.querySelectorAll('canvas');var b=null,m=0;for(var c of cs)
        {var r=c.getBoundingClientRect();var a=r.width*r.height;if(a>m){b=r;m=a}}
        if(!b)return null;return JSON.stringify({left:Math.round(b.left),top:Math.round(b.top),
        width:Math.round(b.width),height:Math.round(b.height)})})()
        """), let d = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CanvasInfo.self, from: d)
    }

    // MARK: - Fonts

    nonisolated func loadFonts() async -> [String: [String]] {
        guard let json = await exec("""
        (async()=>{var f=await figma.listAvailableFontsAsync();var m={};
        f.forEach(function(x){var n=x.fontName;if(!m[n.family])m[n.family]=[];
        m[n.family].push(n.style)});return JSON.stringify(m)})()
        """, ap: true) else { return [:] }
        guard let d = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: d) else { return [:] }
        return dict
    }

    // MARK: - Properties

    nonisolated func setFillColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) async -> Bool {
        let res = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].fills=[{type:'SOLID',color:{r:\(r),g:\(g),b:\(b)},opacity:\(a)}];return'ok'})()")
        return res?.contains("ok") ?? false
    }

    nonisolated func setOpacity(_ v: Double) async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].opacity=\(v);return'ok'})()")
        return r?.contains("ok") ?? false
    }

    nonisolated func setCornerRadius(_ v: Double) async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].cornerRadius=\(v);return'ok'})()")
        return r?.contains("ok") ?? false
    }

    nonisolated func setStrokeColor(_ r: Double, _ g: Double, _ b: Double) async -> Bool {
        let res = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].strokes=[{type:'SOLID',color:{r:\(r),g:\(g),b:\(b)}}];return'ok'})()")
        return res?.contains("ok") ?? false
    }

    nonisolated func setStrokeWeight(_ w: Double) async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].strokeWeight=\(w);return'ok'})()")
        return r?.contains("ok") ?? false
    }

    nonisolated func setStrokeAlign(_ a: String) async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].strokeAlign='\(a)';return'ok'})()")
        return r?.contains("ok") ?? false
    }

    nonisolated func removeFill() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].fills=[];return'ok'})()")
        return r?.contains("ok") ?? false
    }

    nonisolated func removeStroke() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].strokes=[];return'ok'})()")
        return r?.contains("ok") ?? false
    }

    // MARK: - Text

    private func textCmd(_ js: String) async -> Bool {
        let r = await exec("(async()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';var n=s[0];if(n.type!=='TEXT')return'not';await figma.loadFontAsync(n.fontName);\(js);return'ok'})()", ap: true)
        return r?.contains("ok") ?? false
    }

    nonisolated func setFontSize(_ v: Double) async -> Bool { await textCmd("n.fontSize=\(v)") }
    nonisolated func setFontFamily(_ family: String, _ style: String) async -> Bool {
        // 安全转义字体名中的特殊字符
        let safeFamily = family.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")
        let safeStyle = style.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
        // 加载目标字体（而非当前字体）+ try/catch 兜底
        let js = """
        (async()=>{try{var s=figma.currentPage.selection;
        if(!s||!s.length)return'no';var n=s[0];
        if(n.type!=='TEXT')return'not';
        await figma.loadFontAsync({family:"\(safeFamily)",style:"\(safeStyle)"});
        n.fontName={family:"\(safeFamily)",style:"\(safeStyle)"};return'ok'}
        catch(e){return'err:'+e.message}})()
        """
        let r = await exec(js, ap: true)
        return r?.contains("ok") ?? false
    }
    nonisolated func setTextAlign(_ a: String) async -> Bool { await textCmd("n.textAlignHorizontal='\(a)'") }
    nonisolated func setLineHeight(_ v: Double) async -> Bool { await textCmd("n.lineHeight={value:\(v),unit:'PIXELS'}") }
    nonisolated func setLineHeightAuto() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';var n=s[0];if(n.type!=='TEXT')return'not';n.lineHeight={unit:'AUTO'};return'ok'})()")
        return r?.contains("ok") ?? false
    }

    nonisolated func clearSelection() async -> Bool {
        let r = await exec("(()=>{figma.currentPage.selection=[];return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func setLetterSpacing(_ v: Double) async -> Bool { await textCmd("n.letterSpacing={value:\(v),unit:'PIXELS'}") }
    nonisolated func setParagraphSpacing(_ v: Double) async -> Bool { await textCmd("n.paragraphSpacing=\(v)") }
    nonisolated func setParagraphIndent(_ v: Double) async -> Bool { await textCmd("n.paragraphIndent=\(v)") }
    nonisolated func setTextDecoration(_ d: String) async -> Bool { await textCmd("n.textDecoration='\(d)'") }
    nonisolated func setTextCase(_ c: String) async -> Bool { await textCmd("n.textCase='\(c)'") }
    nonisolated func setTextAutoResize(_ a: String) async -> Bool { await textCmd("n.textAutoResize='\(a)'") }

    // MARK: - Align

    private func alignCmd(_ n: String) async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';figma.\(n)(s);return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func alignLeft() async -> Bool { await alignCmd("alignLeft") }
    nonisolated func alignHorizontalCenter() async -> Bool { await alignCmd("alignHorizontalCenter") }
    nonisolated func alignRight() async -> Bool { await alignCmd("alignRight") }
    nonisolated func alignTop() async -> Bool { await alignCmd("alignTop") }
    nonisolated func alignVerticalCenter() async -> Bool { await alignCmd("alignVerticalCenter") }
    nonisolated func alignBottom() async -> Bool { await alignCmd("alignBottom") }
    nonisolated func distributeHorizontal() async -> Bool { await alignCmd("distributeHorizontalSpacing") }
    nonisolated func distributeVertical() async -> Bool { await alignCmd("distributeVerticalSpacing") }

    nonisolated func disconnect() { client.disconnect() }

    // MARK: - JS

    private nonisolated var stateJS: String {
        """
        (()=>{var s=figma.currentPage.selection;var n=(s&&s.length)?s[0]:null;
        var vb=figma.viewport.bounds;
        var vp={zoom:figma.viewport.zoom,centerX:figma.viewport.center.x,centerY:figma.viewport.center.y,
        bounds:vb?{x:vb.x,y:vb.y,width:vb.width,height:vb.height}:null};
        if(!n)return JSON.stringify({vp:vp,node:null});
        var info={id:n.id,name:n.name,type:n.type,width:n.width,height:n.height,x:n.x,y:n.y,
        opacity:n.opacity,visible:n.visible,locked:n.locked,cornerRadius:n.cornerRadius,
        selectionCount:s.length,allTypes:s.map(function(x){return x.type})};
        if(n.type==='TEXT'){
        info.characters=n.characters?n.characters.slice(0,100):'';
        info.fontSize=n.fontSize;
        if(n.fontName){info.fontName=n.fontName.family;info.fontWeight=n.fontName.style}
        info.textAlign=n.textAlignHorizontal;
        if(n.lineHeight){info.lineHeight=n.lineHeight.value;info.lineHeightUnit=n.lineHeight.unit}
        if(n.letterSpacing&&n.letterSpacing.value!==undefined)info.letterSpacing=n.letterSpacing.value;
        info.paragraphSpacing=n.paragraphSpacing||0;
        info.paragraphIndent=n.paragraphIndent||0;
        info.textDecoration=n.textDecoration||'NONE';
        info.textCase=n.textCase||'ORIGINAL';
        info.textAutoResize=n.textAutoResize||'NONE';
        }
        if(n.fills&&n.fills.length&&n.fills[0].type==='SOLID'){info.fillColor=n.fills[0].color;info.fillOpacity=n.fills[0].opacity}
        if(n.strokes&&n.strokes.length&&n.strokes[0].type==='SOLID'){info.strokeColor=n.strokes[0].color;info.strokeWeight=n.strokeWeight;info.strokeAlign=n.strokeAlign}
        return JSON.stringify({vp:vp,node:info})})()
        """
    }
}
