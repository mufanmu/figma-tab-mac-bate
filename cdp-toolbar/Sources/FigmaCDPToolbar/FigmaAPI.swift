import Foundation

final class FigmaAPI: @unchecked Sendable {
    let client: CDPClient

    init(client: CDPClient) { self.client = client }

    nonisolated func discoverAndConnect(port: Int = 9222) async -> Bool {
        return await discoverAndSkip(port: port, skipURL: "")
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
        let rr = Double(lround(r * 1000)) / 1000
        let gg = Double(lround(g * 1000)) / 1000
        let bb = Double(lround(b * 1000)) / 1000
        let aa = Double(lround(a * 100)) / 100
        let res = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].fills=[{type:'SOLID',color:{r:\(rr),g:\(gg),b:\(bb)},opacity:\(aa)}];return'ok'})()")
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

    nonisolated func setStrokeColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) async -> Bool {
        let rr = Double(lround(r * 1000)) / 1000
        let gg = Double(lround(g * 1000)) / 1000
        let bb = Double(lround(b * 1000)) / 1000
        let aa = Double(lround(a * 100)) / 100
        let res = await exec("(()=>{var s=figma.currentPage.selection;if(!s||!s.length)return'no';s[0].strokes=[{type:'SOLID',color:{r:\(rr),g:\(gg),b:\(bb)},opacity:\(aa)}];return'ok'})()")
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

    nonisolated func alignLeft() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';var d=[];for(var i=0;i<s.length;i++){var bb=s[i].absoluteBoundingBox;d.push({n:s[i],x:bb.x})}var m=d[0].x;for(var i=1;i<d.length;i++){if(d[i].x<m){m=d[i].x}}for(var i=d.length-1;i>=0;i--){d[i].n.x=Math.round(d[i].n.x+m-d[i].x)}return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func alignHorizontalCenter() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';var d=[];for(var i=0;i<s.length;i++){var bb=s[i].absoluteBoundingBox;d.push({n:s[i],x:bb.x,w:bb.width})}var l=d[0].x,r=d[0].x+d[0].w;for(var i=1;i<d.length;i++){if(d[i].x<l){l=d[i].x}if(d[i].x+d[i].w>r){r=d[i].x+d[i].w}}var c=(l+r)/2;for(var i=d.length-1;i>=0;i--){var oldCX=d[i].x+d[i].w/2;d[i].n.x=Math.round(d[i].n.x+c-oldCX)}return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func alignRight() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';var d=[];for(var i=0;i<s.length;i++){var bb=s[i].absoluteBoundingBox;d.push({n:s[i],x:bb.x,w:bb.width})}var m=d[0].x+d[0].w;for(var i=1;i<d.length;i++){var ri=d[i].x+d[i].w;if(ri>m){m=ri}}for(var i=d.length-1;i>=0;i--){var oldR=d[i].x+d[i].w;d[i].n.x=Math.round(d[i].n.x+m-oldR)}return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func alignTop() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';var d=[];for(var i=0;i<s.length;i++){var bb=s[i].absoluteBoundingBox;d.push({n:s[i],y:bb.y})}var m=d[0].y;for(var i=1;i<d.length;i++){if(d[i].y<m){m=d[i].y}}for(var i=d.length-1;i>=0;i--){d[i].n.y=Math.round(d[i].n.y+m-d[i].y)}return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func alignVerticalCenter() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';var d=[];for(var i=0;i<s.length;i++){var bb=s[i].absoluteBoundingBox;d.push({n:s[i],y:bb.y,h:bb.height})}var t=d[0].y,b=d[0].y+d[0].h;for(var i=1;i<d.length;i++){if(d[i].y<t){t=d[i].y}if(d[i].y+d[i].h>b){b=d[i].y+d[i].h}}var c=(t+b)/2;for(var i=d.length-1;i>=0;i--){var oldCY=d[i].y+d[i].h/2;d[i].n.y=Math.round(d[i].n.y+c-oldCY)}return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func alignBottom() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';var d=[];for(var i=0;i<s.length;i++){var bb=s[i].absoluteBoundingBox;d.push({n:s[i],y:bb.y,h:bb.height})}var m=d[0].y+d[0].h;for(var i=1;i<d.length;i++){var bi=d[i].y+d[i].h;if(bi>m){m=bi}}for(var i=d.length-1;i>=0;i--){var oldB=d[i].y+d[i].h;d[i].n.y=Math.round(d[i].n.y+m-oldB)}return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func distributeHorizontal() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';var d=[];for(var i=0;i<s.length;i++){d.push({n:s[i],x:s[i].x,w:s[i].width})}d.sort(function(a,b){return a.x-b.x});var w=0;for(var i=0;i<d.length;i++){w+=d[i].w}var g=(d[d.length-1].x+d[d.length-1].w-d[0].x-w)/(d.length-1);var cx=d[0].x;for(var i=d.length-1;i>=0;i--){d[i].n.x=Math.round(cx);cx+=d[i].w+g}return'ok'})()")
        return r?.contains("ok") ?? false
    }
    nonisolated func distributeVertical() async -> Bool {
        let r = await exec("(()=>{var s=figma.currentPage.selection;if(!s||s.length<2)return'no';var d=[];for(var i=0;i<s.length;i++){d.push({n:s[i],y:s[i].y,h:s[i].height})}d.sort(function(a,b){return a.y-b.y});var h=0;for(var i=0;i<d.length;i++){h+=d[i].h}var g=(d[d.length-1].y+d[d.length-1].h-d[0].y-h)/(d.length-1);var cy=d[0].y;for(var i=d.length-1;i>=0;i--){d[i].n.y=Math.round(cy);cy+=d[i].h+g}return'ok'})()")
        return r?.contains("ok") ?? false
    }

    nonisolated func disconnect() { client.disconnect() }

    // MARK: - JS

    private nonisolated var stateJS: String {
        """
        (()=>{var s=figma.currentPage.selection;var n=(s&&s.length)?s[0]:null;
        var vb=figma.viewport.bounds;
        var vp={zoom:figma.viewport.zoom,centerX:figma.viewport.center.x,centerY:figma.viewport.center.y,
        bounds:vb?{x:vb.x,y:vb.y,width:vb.width,height:vb.height}:null};
        if(!n)return JSON.stringify({vp:vp,node:null});
        var ax=n.x,ay=n.y;var p=n.parent;while(p&&p.type!=='PAGE'){ax+=p.x;ay+=p.y;p=p.parent}
        var info={id:n.id,name:n.name,type:n.type,width:n.width,height:n.height,x:n.x,y:n.y,absoluteX:ax,absoluteY:ay,
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
        if(n.strokes&&n.strokes.length&&n.strokes[0].type==='SOLID'){info.strokeColor=n.strokes[0].color;info.strokeOpacity=n.strokes[0].opacity;info.strokeWeight=n.strokeWeight;info.strokeAlign=n.strokeAlign}
        return JSON.stringify({vp:vp,node:info})})()
        """
    }
}
