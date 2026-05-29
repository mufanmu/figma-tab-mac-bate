import SwiftUI

struct ToolbarView: View {
    @ObservedObject var delegate: AppDelegate
    /// 强制使用 Figma 暗色主题
    let theme: FigmaTheme = .dark
    @State private var fillColor: Color = .yellow
    @State private var strokeColor: Color = .black
    @State private var cornerRadius: Double = 0
    @State private var opacityValue: Double = 1
    @State private var fontSize: Double = 16
    @State private var lineHeight: Double = 0
    @State private var letterSpacing: Double = 0
    @State private var paragraphSpacing: Double = 0
    @State private var paragraphIndent: Double = 0
    @State private var strokeWeight: Double = 1
    @State private var selectedFontFamily: String = ""
    @State private var selectedFontStyle: String = "Regular"
    @State private var lineHeightAuto: Bool = false
    @State private var searchText: String = ""
    @State private var showDropdown: Bool = false
    @State private var dismissTask: Task<Void, Never>? = nil
    @State private var showColorEditor = false
    @State private var editingFill = true
    @State private var strokeAlignValue: String = "CENTER"
    @State private var showStylePopover = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let node = delegate.selectedNode {
                if node.selectionCount > 1 || node.allTypes.count > 1 {
                    alignToolbar(node: node)
                } else if node.type == .text {
                    textToolbar(node: node)
                } else if node.type.isShape {
                    shapeToolbar(node: node)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .frame(width: delegate.panelWidth)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "2C2C2C")).shadow(color: theme.shadow, radius: 8, y: 2))
        .onChange(of: "\(delegate.selectedNode?.id ?? "")-\(delegate.selectedNode?.selectionCount ?? 0)-\(delegate.selectedNode?.allTypes.count ?? 0)") { _, _ in
            if let node = delegate.selectedNode {
                updateFromNode(node)
                delegate.panelWidth = desiredWidth
                searchText = ""
                delegate.loadAllFontsForSearch()
            }
        }
        .onAppear { delegate.panelWidth = desiredWidth }
    }

    /// 根据当前工具栏模式计算宽度 (content + 左右各 10px)
    private var desiredWidth: CGFloat {
        guard let node = delegate.selectedNode else { return 498 }
        if node.selectionCount > 1 || node.allTypes.count > 1 {
            return 262
        } else if node.type == .text {
            return 498
        } else if node.type.isShape {
            return 70
        }
        return 537
    }

    private func colorEditorPopover() -> some View {
        AntColorPicker(
            color: editingFill ? $fillColor : $strokeColor,
            title: editingFill ? "填充" : "描边",
            onApply: { c, a in
                guard let rgba = c.toRGBA() else { return }
                Task { if editingFill { _ = await delegate.api.setFillColor(rgba.r, rgba.g, rgba.b, rgba.a) } else { _ = await delegate.api.setStrokeColor(rgba.r, rgba.g, rgba.b, rgba.a) } }
            },
            onRemove: { Task { if self.editingFill { await delegate.api.removeFill() } else { await delegate.api.removeStroke() } } },
            showStrokeOptions: !editingFill,
            strokeWeight: $strokeWeight,
            strokeAlign: $strokeAlignValue,
            onStrokeWeightChange: { v in Task { await delegate.api.setStrokeWeight(v) } },
            onStrokeAlignChange: { a in Task { await delegate.api.setStrokeAlign(a) } },
            api: delegate.api
        )
    }

    private func updateFromNode(_ node: NodeProperties) {
        if let c = node.fillColor { fillColor = Color(red: c.r, green: c.g, blue: c.b); opacityValue = node.fillOpacity ?? node.opacity }
        if let sc = node.strokeColor { let sa = node.strokeOpacity ?? 1.0; strokeColor = Color(red: sc.r, green: sc.g, blue: sc.b, opacity: sa) }
        cornerRadius = node.cornerRadius ?? 0; strokeWeight = node.strokeWeight ?? 1
        if let fs = node.fontSize { fontSize = fs }
        lineHeightAuto = node.lineHeightUnit == "AUTO"
        if !lineHeightAuto { lineHeight = node.lineHeight ?? 0 }
        letterSpacing = node.letterSpacing ?? 0
        paragraphSpacing = node.paragraphSpacing ?? 0; paragraphIndent = node.paragraphIndent ?? 0
        if let fn = node.fontName { selectedFontFamily = fn }
        if let fw = node.fontWeight { selectedFontStyle = fw }
        strokeAlignValue = node.strokeAlign ?? "CENTER"
    }

    // MARK: - Text

    private func textToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 6) {
            HStack(spacing:2) {
                ColorDotButton(color: fillColor, isFill: true, hasColor: node.fillColor != nil, isActive: showColorEditor && editingFill, theme: theme) { editingFill = true; showColorEditor = true }
                ColorDotButton(color: strokeColor, isFill: false, hasColor: node.strokeColor != nil, isActive: showColorEditor && !editingFill, theme: theme) { editingFill = false; showColorEditor = true }
            }
            .popover(isPresented: $showColorEditor, arrowEdge: .bottom) {
                colorEditorPopover()
            }
            Separator(theme: theme)
            fontPicker(node: node)
            PresetField(labelIcon: "text font size", value: $fontSize, presets: [10, 12, 14, 16, 18, 20, 24, 32], onChange: { v in Task { _ = await delegate.api.setFontSize(v) } }, theme: theme)
            Separator(theme: theme)
            // 行高：输入数字或 "auto" 回车确认
            LineHeightField(theme: theme, lineHeight: $lineHeight, lineHeightAuto: $lineHeightAuto, api: delegate.api)
            PresetField(labelIcon: "text letter spacing", value: $letterSpacing, presets: [0, 2, 4, 8, 12, 16, 20, 32, 40], onChange: { v in Task { _ = await delegate.api.setLetterSpacing(v) } }, theme: theme)
            Separator(theme: theme)
            alignButtons(node: node)
            settingDropdown(node: node)
        }
    }

    /// 搜索时全量过滤；未搜索时仅显示已加载的部分（fontLoadCount）
    private var filteredFonts: [FontInfo] {
        guard !searchText.isEmpty else {
            return Array(delegate.fonts.prefix(delegate.fontLoadCount))
        }
        return delegate.fonts.filter { $0.family.localizedCaseInsensitiveContains(searchText) }
    }

    private func fontPicker(node: NodeProperties) -> some View {
        HStack(spacing: 3) {
            // 搜索输入框（带字体图标）
            HStack(spacing: 4) {
                toolbarIcon("Style Text", size: 24).foregroundColor(searchText.isEmpty ? theme.ink.opacity(0.35) : theme.ink)
                ZStack(alignment: .leading) {
                    if searchText.isEmpty {
                        Text(selectedFontFamily.isEmpty ? "字体" : selectedFontFamily)
                            .font(FigmaTokens.fontBody)
                            .foregroundColor(theme.ink.opacity(0.35))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $searchText)
                        .font(FigmaTokens.fontBody)
                        .foregroundColor(theme.ink)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                }
            }
            .frame(width: 84)
            .padding(.horizontal, 4)
            .frame(height: 24)
            .background(Color(hex: "383838"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(theme.surfaceSoft, lineWidth: 1)
            )
            // 透明层捕获点击：聚焦 + 展开列表 + 定位当前字体
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isSearchFocused = true
                        delegate.loadAllFontsForSearch()
                        showDropdown = true
                    }
            )
            .popover(isPresented: $showDropdown, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    let items = filteredFonts
                    if items.isEmpty {
                        Text("无匹配字体")
                            .font(FigmaTokens.fontBodySmall)
                            .foregroundColor(theme.ink)
                            .padding(12)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.family) { idx, f in
                                        Button {
                                            let family = f.family
                                            let style = f.styles.first ?? "Regular"
                                            let api = delegate.api
                                            selectedFontFamily = family
                                            selectedFontStyle = style
                                            searchText = ""
                                            // 延迟关闭 popover 以掩盖 CDP 延迟
                                            dismissTask?.cancel()
                                            dismissTask = Task { @MainActor in
                                                try? await Task.sleep(nanoseconds: 300_000_000)
                                                showDropdown = false
                                            }
                                            Task { @MainActor in
                                                _ = await api.setFontFamily(family, style)
                                            }
                                        } label: {
                                            HStack {
                                                Text(f.family)
                                                    .font(FigmaTokens.fontBody)
                                                    .foregroundColor(f.family == selectedFontFamily ? FigmaColors.accentBlue : theme.ink)
                                                Spacer()
                                                if f.family == selectedFontFamily {
                                                    Image(systemName: "checkmark")
                                                        .font(FigmaTokens.fontBodySmall)
                                                        .foregroundColor(FigmaColors.accentBlue)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(f.family == selectedFontFamily ? FigmaColors.accentBlue.opacity(0.1) : Color.clear)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        Divider().opacity(0)
                                        // 距底部 30 个时预加载下一组 50
                                        .onAppear {
                                            if idx >= items.count - 30 && searchText.isEmpty {
                                                delegate.loadMoreFonts()
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: min(CGFloat(items.count) * 30, 300))
                            .onAppear {
                                if !selectedFontFamily.isEmpty {
                                    proxy.scrollTo(selectedFontFamily, anchor: .center)
                                }
                            }
                        }
                    }
                }
                .frame(width: 180)
                .padding(.vertical, 4)
                .background(theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedMd))
            }

            // 样式选择（仅一种样式时不可点击）
            let fontStyles = delegate.fonts.first(where: { $0.family == selectedFontFamily })?.styles ?? []
            Button {
                showStylePopover = true
            } label: {
                Text(selectedFontStyle).font(FigmaTokens.fontBodySmall).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            .frame(width: 56, height: 24)
            .background(Color(hex: "383838"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(fontStyles.count <= 1 ? 0.35 : 1)
            .disabled(fontStyles.count <= 1)
            .popover(isPresented: $showStylePopover, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    ForEach(fontStyles, id: \.self) { s in
                        Button {
                            selectedFontStyle = s
                            Task { await delegate.api.setFontFamily(selectedFontFamily, s) }
                            showStylePopover = false
                        } label: {
                            HStack {
                                Text(s)
                                    .font(FigmaTokens.fontBody)
                                    .foregroundColor(s == selectedFontStyle ? FigmaColors.accentBlue : theme.ink)
                                Spacer()
                                if s == selectedFontStyle {
                                    Image(systemName: "checkmark")
                                        .font(FigmaTokens.fontBodySmall)
                                        .foregroundColor(FigmaColors.accentBlue)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(s == selectedFontStyle ? FigmaColors.accentBlue.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 100)
                .padding(.vertical, 4)
                .background(theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedMd))
            }
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                showDropdown = true
            }
        }
        // 不自动展开：只在点击搜索区域时通过 overlay onTapGesture 打开
    }

    private struct AlignDropButton: View {
        let current: String
        let api: FigmaAPI
        let svgMap: [String:String]
        let theme: FigmaTheme
        @State private var showPopover = false

        var body: some View {
            Button { showPopover = true } label: {
                toolbarIcon(svgMap[current] ?? "text align left", size:24).foregroundColor(theme.ink)
            }
            .buttonStyle(.plain).frame(width:24, height:24)
            .background(Color(hex: "383838")).clipShape(RoundedRectangle(cornerRadius: 4))
            .onHover { over in if over { showPopover = true } }
            .popover(isPresented:$showPopover, arrowEdge:.bottom) {
                VStack(spacing:2) {
                    ForEach(["LEFT","CENTER","RIGHT","JUSTIFIED"], id:\.self) { t in
                        Button {
                            Task { _ = await api.setTextAlign(t) }
                            showPopover = false
                        } label: {
                            HStack {
                                toolbarIcon(svgMap[t] ?? "text align left", size:16).foregroundColor(theme.ink)
                                Text(["LEFT":"左对齐","CENTER":"居中","RIGHT":"右对齐","JUSTIFIED":"两端对齐"][t] ?? t)
                                    .font(FigmaTokens.fontBody).foregroundColor(theme.ink)
                            }
                            .frame(maxWidth:.infinity, alignment:.leading)
                            .padding(.horizontal,8).padding(.vertical,5)
                            .background(t == current ? Color(hex:"0D99FF").opacity(0.3) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical,4).frame(width:100)
                .background(theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedMd))
            }
        }
    }

    private func alignButtons(node: NodeProperties) -> some View {
        let svgMap = ["LEFT":"text align left", "CENTER":"text align center", "RIGHT":"text align right", "JUSTIFIED":"text align justified"]
        return AlignDropButton(current: node.textAlign ?? "LEFT", api: delegate.api, svgMap: svgMap, theme: theme)
    }

    private func settingDropdown(node: NodeProperties) -> some View {
        let d = node.textDecoration ?? "NONE"
        let c = node.textCase ?? "ORIGINAL"
        let r = node.textAutoResize ?? "NONE"
        return SettingDropdown(currentD:d, currentC:c, currentR:r,
            ps: $paragraphSpacing, pi: $paragraphIndent,
            onPS:{ v in Task{ _=await delegate.api.setParagraphSpacing(v) } },
            onPI:{ v in Task{ _=await delegate.api.setParagraphIndent(v) } },
            api:delegate.api, theme:theme)
    }

    private struct SettingDropdown: View {
        let currentD: String; let currentC: String; let currentR: String
        @Binding var ps: Double; @Binding var pi: Double
        let onPS: (Double) -> Void; let onPI: (Double) -> Void
        let api: FigmaAPI; let theme: FigmaTheme
        @State private var show = false
        private let svgMap = ["WIDTH_AND_HEIGHT":"text Auto width", "HEIGHT":"text Auto height", "NONE":"text Fixed size"]
        private let cases: [(String,String)] = [("ORIGINAL","Remove"),("UPPER","text caps"),("LOWER","lowercase"),("TITLE","title case")]
        var body: some View {
            Button { show = true } label: {
                toolbarIcon("Setting", size:24).foregroundColor(theme.ink)
            }
            .buttonStyle(.plain).frame(width:24, height:24)
            .background(Color(hex: "383838")).clipShape(RoundedRectangle(cornerRadius: 4))
            .onHover { over in if over { show = true } }
            .popover(isPresented:$show, arrowEdge:.bottom) {
                VStack(spacing:0) {
                    Text("装饰").font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink.opacity(0.5))
                        .frame(maxWidth:.infinity, alignment:.leading).padding(.leading,8).padding(.top,4)
                    HStack(spacing:2) {
                        ToggleBtn(svg:"underline", system:nil, active:currentD=="UNDERLINE", size:20, theme:theme) {
                            Task { _ = await api.setTextDecoration(currentD=="UNDERLINE" ? "NONE" : "UNDERLINE") }
                        }
                        ToggleBtn(svg:"false", system:nil, active:currentD=="STRIKETHROUGH", size:20, theme:theme) {
                            Task { _ = await api.setTextDecoration(currentD=="STRIKETHROUGH" ? "NONE" : "STRIKETHROUGH") }
                        }
                    }.frame(maxWidth:.infinity, alignment:.leading).padding(.leading,4)
                    Divider().overlay(theme.hairline.opacity(0.7)).padding(.horizontal,4)
                    Text("大小写").font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink.opacity(0.5))
                        .frame(maxWidth:.infinity, alignment:.leading).padding(.leading,8).padding(.top,2)
                    HStack(spacing:2) {
                        let cases:[(String,String)] = [("ORIGINAL","Remove"),("UPPER","text caps"),("LOWER","lowercase"),("TITLE","title case")]
                        ForEach(cases, id:\.0) { v,svg in
                            Button { Task { _ = await api.setTextCase(v) } } label: {
                                toolbarIcon(svg, size:20).foregroundColor(theme.ink)
                            }
                            .buttonStyle(.plain).frame(width:22, height:22)
                            .background(currentC==v ? Color(hex: "383838") : Color.clear).clipShape(RoundedRectangle(cornerRadius:4))
                        }
                    }.frame(maxWidth:.infinity, alignment:.leading).padding(.leading,4)
                    Divider().overlay(theme.hairline.opacity(0.7)).padding(.horizontal,4)
                    Text("自动尺寸").font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink.opacity(0.5))
                        .frame(maxWidth:.infinity, alignment:.leading).padding(.leading,8).padding(.top,2)
                    HStack(spacing:2) {
                        ForEach(["WIDTH_AND_HEIGHT","HEIGHT","NONE"], id:\.self) { v in
                            Button { Task { _ = await api.setTextAutoResize(v) } } label: {
                                toolbarIcon(svgMap[v] ?? "text Fixed size", size:20).foregroundColor(theme.ink)
                            }
                            .buttonStyle(.plain).frame(width:22, height:22)
                            .background(currentR==v ? Color(hex: "383838") : Color.clear).clipShape(RoundedRectangle(cornerRadius:4))
                        }
                    }.frame(maxWidth:.infinity, alignment:.leading).padding(.leading,4)
                    Divider().overlay(theme.hairline.opacity(0.7)).padding(.horizontal,4)
                    Text("段落").font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink.opacity(0.5))
                        .frame(maxWidth:.infinity, alignment:.leading).padding(.leading,8).padding(.top,2)
                    HStack(spacing:6) {
                        toolbarIcon("text paragraph spacing", size:16).foregroundColor(theme.ink)
                        TextField("0", text:Binding(get:{String(Int(ps))}, set:{if let v=Double($0){ps=v;onPS(ps)}}))
                            .textFieldStyle(.plain).font(FigmaTokens.fontCaption).foregroundColor(theme.ink)
                            .multilineTextAlignment(.center).frame(width:44, height:22)
                            .background(theme.surfaceSoft).clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.hairline.opacity(0.7),lineWidth:1))
                            .onSubmit { onPS(ps) }
                        toolbarIcon("text paragraph indent", size:16).foregroundColor(theme.ink)
                        TextField("0", text:Binding(get:{String(Int(pi))}, set:{if let v=Double($0){pi=v;onPI(pi)}}))
                            .textFieldStyle(.plain).font(FigmaTokens.fontCaption).foregroundColor(theme.ink)
                            .multilineTextAlignment(.center).frame(width:44, height:22)
                            .background(theme.surfaceSoft).clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.hairline.opacity(0.7),lineWidth:1))
                            .onSubmit { onPI(pi) }
                    }.frame(maxWidth:.infinity, alignment:.leading).padding(.horizontal,8)
                }
                .padding(.vertical,4).frame(width:170)
                .background(theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedMd))
            }
        }
    }

    // MARK: - Shape

    private func shapeToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 6) {
            HStack(spacing:2) {
                ColorDotButton(color: fillColor, isFill: true, hasColor: node.fillColor != nil, isActive: showColorEditor && editingFill, theme: theme) { editingFill = true; showColorEditor = true }
                ColorDotButton(color: strokeColor, isFill: false, hasColor: node.strokeColor != nil, isActive: showColorEditor && !editingFill, theme: theme) { editingFill = false; showColorEditor = true }
            }
            .popover(isPresented: $showColorEditor, arrowEdge: .bottom) {
                colorEditorPopover()
            }
        }
    }

    // MARK: - Align

    private func alignToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 4) {
            // 垂直对齐组：左/中/右
            HStack(spacing: 6) {
                IconBtn(svg: "Align vertical left", theme: theme) { Task { _ = await delegate.api.alignLeft() } }
                IconBtn(svg: "Align vertical center", theme: theme) { Task { _ = await delegate.api.alignHorizontalCenter() } }
                IconBtn(svg: "Align vertical right", theme: theme) { Task { _ = await delegate.api.alignRight() } }
            }
            .padding(.horizontal, 2)
            .background(Color(hex: "383838"))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // 水平对齐组：上/中/下
            HStack(spacing: 6) {
                IconBtn(svg: "Align horizontal top", theme: theme) { Task { _ = await delegate.api.alignTop() } }
                IconBtn(svg: "Align horizontal center", theme: theme) { Task { _ = await delegate.api.alignVerticalCenter() } }
                IconBtn(svg: "Align horizontal bottom", theme: theme) { Task { _ = await delegate.api.alignBottom() } }
            }
            .padding(.horizontal, 2)
            .background(Color(hex: "383838"))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // 分布组：水平/垂直
            HStack(spacing: 6) {
                IconBtn(svg: "Distribute horizontal spacing", theme: theme) { Task { _ = await delegate.api.distributeHorizontal() } }
                IconBtn(svg: "Distribute vertical spacing", theme: theme) { Task { _ = await delegate.api.distributeVertical() } }
            }
            .padding(.horizontal, 2)
            .background(Color(hex: "383838"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Shared

    private struct Separator: View { let theme: FigmaTheme; var body: some View {
        Rectangle().fill(theme.hairline.opacity(0.7)).frame(width: 1, height: 20)
    }}

    private struct NumField: View {
        let label: String
        let labelIcon: String?
        @Binding var value: Double
        let range: ClosedRange<Double>
        let mult: Double
        let theme: FigmaTheme
        let onChange: () -> Void
        @FocusState private var isFocused: Bool
        @State private var inputText: String = ""

        init(label: String, labelIcon: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, mult: Double = 1, theme: FigmaTheme, onChange: @escaping () -> Void) {
            self.label = label
            self.labelIcon = labelIcon
            self._value = value
            self.range = range
            self.mult = mult
            self.theme = theme
            self.onChange = onChange
        }

        var body: some View {
            HStack(spacing: 2) {
                if let icon = labelIcon {
                    toolbarIcon(icon, size: 16).foregroundColor(theme.ink)
                } else {
                    Text(label).font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink)
                }

                // ZStack: 占位显示当前值（35%），输入后替换，回车确认
                ZStack(alignment: .center) {
                    if inputText.isEmpty {
                        Text("\(Int(value * mult))")
                            .font(FigmaTokens.fontCaption)
                            .foregroundColor(theme.ink.opacity(0.35))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $inputText)
                        .font(FigmaTokens.fontCaption)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .foregroundColor(theme.ink)
                        .focused($isFocused)
                        .onSubmit {
                            if let n = Double(inputText) {
                                let clamped = max(range.lowerBound, min(range.upperBound, n / mult))
                                value = clamped
                                onChange()
                            }
                            inputText = ""
                            isFocused = false
                        }
                }
                .frame(width: 26)
                .onChange(of: isFocused) { _, focused in
                    if !focused { inputText = "" }
                }

                VStack(spacing: -2) {
                    UpDownBtn(icon: "chevron.up") { value = min(value + 1, range.upperBound); onChange(); inputText = "" }
                    UpDownBtn(icon: "chevron.down") { value = max(value - 1, range.lowerBound); onChange(); inputText = "" }
                }
            }
            .frame(height: 22).padding(.horizontal, 4).background(theme.surfaceSoft).clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private struct UpDownBtn: View { let icon: String; let a: () -> Void; var body: some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 6, weight: .bold)) }
            .buttonStyle(.plain).frame(width: 14, height: 10)
    }}

    private struct ToggleBtn: View { let svg: String?; let system: String?; let active: Bool; let size: CGFloat; let theme: FigmaTheme; let a: () -> Void; var body: some View {
        Button(action: a) {
            if let s = svg { toolbarIcon(s, size: size).foregroundColor(theme.ink) }
            else if let s = system { Image(systemName: s).font(.system(size: 10)).foregroundColor(theme.ink) }
        }
            .buttonStyle(.plain).frame(width: size, height: size)
            .background(active ? Color(hex: "383838") : Color.clear).clipShape(RoundedRectangle(cornerRadius: 4))
    }}

    /// 带预设下拉菜单的数值输入（点击展开，可选预设或输入自定义）
    private struct PresetField: View {
        let labelIcon: String
        @Binding var value: Double
        let presets: [Double]
        let onChange: (Double) -> Void
        let theme: FigmaTheme
        @State private var inputText: String = ""
        @State private var showDropdown: Bool = false
        @FocusState private var isFocused: Bool

        var body: some View {
            HStack(spacing: 2) {
                toolbarIcon(labelIcon, size: 16).foregroundColor(theme.ink)
                ZStack(alignment: .center) {
                    if inputText.isEmpty {
                        Text("\(Int(value))")
                            .font(FigmaTokens.fontCaption)
                            .foregroundColor(theme.ink.opacity(0.35))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $inputText)
                        .font(FigmaTokens.fontCaption)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .foregroundColor(theme.ink)
                        .focused($isFocused)
                        .onSubmit {
                            if let n = Double(inputText) { value = n; onChange(n) }
                            inputText = ""; showDropdown = false
                        }
                        .onChange(of: inputText) { _, nv in
                            if !nv.isEmpty { showDropdown = true }
                        }
                }
                .frame(width: 34)
                .onChange(of: isFocused) { _, focused in
                    if !focused { inputText = "" }
                }
            }
            .frame(height: 24).padding(.horizontal, 4)
            .background(Color(hex: "383838"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isFocused = true; showDropdown = true }
            )
            .popover(isPresented: $showDropdown, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    ForEach(presets, id: \.self) { p in
                        Button {
                            value = p; onChange(p)
                            inputText = ""; showDropdown = false
                        } label: {
                            HStack {
                                Text("\(Int(p))")
                                    .font(FigmaTokens.fontBody)
                                    .foregroundColor(p == value ? FigmaColors.accentBlue : theme.ink)
                                Spacer()
                                if p == value {
                                    Image(systemName: "checkmark")
                                        .font(FigmaTokens.fontBodySmall)
                                        .foregroundColor(FigmaColors.accentBlue)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(p == value ? FigmaColors.accentBlue.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 60)
                .padding(.vertical, 4)
                .background(theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedMd))
            }
        }
    }

    /// 行高输入：支持数字或 "auto"，带预设下拉
    private struct LineHeightField: View {
        let theme: FigmaTheme
        @Binding var lineHeight: Double
        @Binding var lineHeightAuto: Bool
        let api: FigmaAPI
        @State private var inputText: String = ""
        @State private var showDropdown: Bool = false
        @FocusState private var isFocused: Bool
        let presets: [Double] = [10, 12, 14, 16, 18, 20, 24, 32]

        var body: some View {
            HStack(spacing: 2) {
                toolbarIcon("text line height", size: 16).foregroundColor(theme.ink)
                ZStack(alignment: .center) {
                    if inputText.isEmpty {
                        Text(lineHeightAuto ? "auto" : "\(Int(lineHeight))")
                            .font(FigmaTokens.fontCaption)
                            .foregroundColor(theme.ink.opacity(0.35))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $inputText)
                        .font(FigmaTokens.fontCaption)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .foregroundColor(theme.ink)
                        .focused($isFocused)
                        .onSubmit {
                            let trimmed = inputText.lowercased().trimmingCharacters(in: .whitespaces)
                            if trimmed == "auto" {
                                lineHeightAuto = true
                                Task { await api.setLineHeightAuto() }
                            } else if let n = Double(inputText) {
                                lineHeightAuto = false
                                lineHeight = max(0, min(999, n))
                                Task { await api.setLineHeight(lineHeight) }
                            }
                            inputText = ""; showDropdown = false
                        }
                        .onChange(of: inputText) { _, nv in
                            if !nv.isEmpty { showDropdown = true }
                        }
                }
                .frame(width: 34)
                .onChange(of: isFocused) { _, focused in
                    if !focused { inputText = "" }
                }
            }
            .frame(height: 24).padding(.horizontal, 4)
            .background(Color(hex: "383838"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isFocused = true; showDropdown = true }
            )
            .popover(isPresented: $showDropdown, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    Button {
                        lineHeightAuto = true
                        Task { await api.setLineHeightAuto() }
                        inputText = ""; showDropdown = false
                    } label: {
                        HStack {
                            Text("auto")
                                .font(FigmaTokens.fontBody)
                                .foregroundColor(lineHeightAuto ? FigmaColors.accentBlue : theme.ink)
                            Spacer()
                            if lineHeightAuto {
                                Image(systemName: "checkmark")
                                    .font(FigmaTokens.fontBodySmall)
                                    .foregroundColor(FigmaColors.accentBlue)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(lineHeightAuto ? FigmaColors.accentBlue.opacity(0.1) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.vertical, 2)
                    ForEach(presets, id: \.self) { p in
                        Button {
                            lineHeightAuto = false
                            lineHeight = p
                            Task { await api.setLineHeight(p) }
                            inputText = ""; showDropdown = false
                        } label: {
                            HStack {
                                Text("\(Int(p))")
                                    .font(FigmaTokens.fontBody)
                                    .foregroundColor(!lineHeightAuto && p == lineHeight ? FigmaColors.accentBlue : theme.ink)
                                Spacer()
                                if !lineHeightAuto && p == lineHeight {
                                    Image(systemName: "checkmark")
                                        .font(FigmaTokens.fontBodySmall)
                                        .foregroundColor(FigmaColors.accentBlue)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(!lineHeightAuto && p == lineHeight ? FigmaColors.accentBlue.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 60)
                .padding(.vertical, 4)
                .background(theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedMd))
            }
        }
    }

    private struct IconBtn: View { let svg: String; let theme: FigmaTheme; let a: () -> Void; var body: some View {
        Button(action: a) { toolbarIcon(svg, size: 24).foregroundColor(theme.ink) }
            .buttonStyle(.plain).frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }}

    private var opacitySlider: some View {
        HStack(spacing: 2) {
            Image(systemName: "circle.lefthalf.filled").font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink)
            Slider(value: Binding(get: { opacityValue }, set: { newVal in opacityValue = newVal; Task { _ = await delegate.api.setOpacity(newVal) } }), in: 0...1).frame(width: 40)
            Text("\(Int(opacityValue * 100))%").font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink).frame(width: 24)
        }
    }

    // MARK: - Color Editor

    /// 色块按钮：填充是实心圆，描边是空心圆环
    private struct ColorDotButton: View {
        let color: Color
        let isFill: Bool
        let hasColor: Bool
        let isActive: Bool
        let theme: FigmaTheme
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                Color.clear.frame(width: 24, height: 24).contentShape(Rectangle())
                    .overlay(
                        Group {
                            if hasColor {
                                if isFill {
                                    Circle().fill(color).frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                } else {
                                    Circle().strokeBorder(color, lineWidth: 3).frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                }
                            } else {
                                if Bundle.module.url(forResource: "None", withExtension: "svg") != nil {
                                    toolbarIcon("None", size: 16).foregroundColor(theme.ink)
                                } else {
                                    Image(systemName: "circle.slash").font(.system(size: 10)).foregroundColor(theme.ink)
                                }
                            }
                        }
                    )
            }
            .buttonStyle(.plain).frame(width: 24, height: 24)
            .background(isActive ? Color(hex: "383838") : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Ant Design ColorPicker

        /// Figma 设计风格颜色选择器 — 从设计稿复刻
    private struct AntColorPicker: View {
        @Binding var color: Color
        let title: String
        let onApply: (Color, Double) -> Void
        let onRemove: () -> Void
        let showStrokeOptions: Bool
        @Binding var strokeWeight: Double
        @Binding var strokeAlign: String
        let onStrokeWeightChange: (Double) -> Void
        let onStrokeAlignChange: (String) -> Void
        let api: FigmaAPI

        enum ColorFormat: String, CaseIterable {
            case hex = "HEX"
            case hsb = "HSB"
            case rgb = "RGB"
        }

        @State private var hue: Double = 0
        @State private var sat: Double = 0
        @State private var bri: Double = 1
        @State private var alpha: Double = 1
        @State private var format: ColorFormat = .hex
        @State private var hexInput: String = "000000"
        @State private var hInput: String = "0"
        @State private var sInput: String = "0"
        @State private var bInput: String = "100"
        @State private var alphaInput: String = "100"
        @State private var showFormatPicker = false

        private let bgColor = Color(red: 0.17, green: 0.17, blue: 0.17)
        private let inputBg = Color(red: 0.12, green: 0.12, blue: 0.12)
        private let inputStroke = Color(red: 0.24, green: 0.24, blue: 0.24)
        private let dividerColor = Color(red: 0.24, green: 0.24, blue: 0.24)

        var body: some View {
            VStack(spacing: 0) {
                // SB 拾色平面
                sbPickerSection()
                    .padding(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))

                // 彩虹色相滑块
                sliderSection(title: "色相") { geo in
                    rainbowSliderBody(geo: geo)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Alpha 滑块
                sliderSection(title: "透明度") { geo in
                    alphaSliderBody(geo: geo)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // 输入行
                inputRow()
                    .padding(12)
            }
            .frame(width: 252)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .onAppear { loadFromColor() }
        }

        private func loadFromColor() {
            let ns = NSColor(color)
            hue = Double(ns.hueComponent)
            sat = Double(ns.saturationComponent)
            bri = Double(ns.brightnessComponent)
            alpha = Double(ns.alphaComponent)
            syncInputs()
        }

        private func syncInputs() {
            let c = NSColor(_color.wrappedValue).usingColorSpace(.deviceRGB)
            let comps = c?.cgColor.components ?? [0,0,0]
            hexInput = String(format: "%02X%02X%02X", lround(comps[0]*255), lround(comps[1]*255), lround(comps[2]*255))
            hInput = "\(lround(hue * 360))"
            sInput = "\(lround(sat * 100))"
            bInput = "\(lround(bri * 100))"
            alphaInput = "\(lround(alpha * 100))"
        }

        private func applyColor() {
            _color.wrappedValue = Color(hue: hue, saturation: sat, brightness: bri, opacity: alpha)
            onApply(_color.wrappedValue, alpha)
            syncInputs()
        }

        private func setColor(_ c: Color) {
            let ns = NSColor(c).usingColorSpace(.deviceRGB)
            guard let comps = ns?.cgColor.components, comps.count >= 3 else { return }
            hue = Double(comps[0])
            sat = Double(comps[1])
            bri = Double(comps[2])
            alpha = Double(ns?.alphaComponent ?? 1)
            applyColor()
        }

        // MARK: - SB Picker
        private func sbPickerSection() -> some View {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color(hue: hue, saturation: 1, brightness: 1)
                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)
                    // 光标
                    Circle()
                        .fill(Color(hue: hue, saturation: sat, brightness: bri, opacity: alpha))
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .offset(x: sat * Double(geo.size.width) - 9, y: (1 - bri) * Double(geo.size.height) - 9)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { loc in
                    let w = Double(geo.size.width); let h = Double(geo.size.height)
                    sat = max(0, min(1, Double(loc.x) / w))
                    bri = max(0, min(1, 1 - Double(loc.y) / h))
                    applyColor()
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                    let w = Double(geo.size.width); let h = Double(geo.size.height)
                    sat = max(0, min(1, Double(val.location.x) / w))
                    bri = max(0, min(1, 1 - Double(val.location.y) / h))
                    applyColor()
                })
            }
            .frame(height: 172)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        // MARK: - Sliders
        private func sliderSection(title: String, @ViewBuilder content: @escaping (GeometryProxy) -> some View) -> some View {
            GeometryReader { geo in
                content(geo)
            }
            .frame(height: 16)
        }

        private func rainbowSliderBody(geo: GeometryProxy) -> some View {
            ZStack(alignment: .leading) {
                LinearGradient(colors: (0...36).map { i in Color(hue: Double(i) / 36, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                // Thumb
                Circle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .offset(x: hue * Double(geo.size.width) - 8, y: 0)
            }
            .onTapGesture { loc in
                let w = Double(geo.size.width)
                hue = max(0, min(1, Double(loc.x) / w))
                applyColor()
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                let w = Double(geo.size.width)
                hue = max(0, min(1, Double(val.location.x) / w))
                applyColor()
            })
        }

        private func alphaSliderBody(geo: GeometryProxy) -> some View {
            ZStack(alignment: .leading) {
                // Checkerboard
                Canvas { ctx, size in
                    let step: CGFloat = 5
                    for row in 0..<Int(ceil(size.height / step)) {
                        for col in 0..<Int(ceil(size.width / step)) {
                            let isLight = (row + col).isMultiple(of: 2)
                            ctx.fill(Path(CGRect(x: CGFloat(col) * step, y: CGFloat(row) * step, width: step, height: step)),
                                     with: .color(isLight ? Color.white.opacity(0.3) : Color.gray.opacity(0.25)))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                // Gradient
                LinearGradient(colors: [.clear, Color(hue: hue, saturation: sat, brightness: bri)], startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                // Thumb
                Circle()
                    .fill(Color(hue: hue, saturation: sat, brightness: bri, opacity: alpha))
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .offset(x: alpha * Double(geo.size.width) - 8, y: 0)
            }
            .onTapGesture { loc in
                let w = Double(geo.size.width)
                alpha = max(0, min(1, Double(loc.x) / w))
                applyColor()
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                let w = Double(geo.size.width)
                alpha = max(0, min(1, Double(val.location.x) / w))
                applyColor()
            })
        }

        // MARK: - Input Row
        private func inputRow() -> some View {
            VStack(spacing: 8) {
                // 格式切换 + 数值 + 透明度
                HStack(spacing: 6) {
                    // Eyedropper
                    Button(action: {
                        NSApp.activate(ignoringOtherApps: true)
                        Task { @MainActor in
                            let ns = await NSColorSampler().sample()
                            guard let ns, let srgb = ns.usingColorSpace(.sRGB) else { return }
                            setColor(Color(srgb))
                        }
                    }) {
                        toolbarIcon("Style Fill", size: 16).foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24)

                    // Format selector
                    Button {
                        showFormatPicker = true
                    } label: {
                        HStack(spacing: 2) {
                            Text(format.rawValue).font(.system(size: 11)).foregroundColor(.white)
                            Image(systemName: "chevron.down").font(.system(size: 6)).foregroundColor(.white.opacity(0.5))
                        }
                        .frame(width: 52, height: 22)
                        .background(inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(inputStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFormatPicker, arrowEdge: .bottom) {
                        VStack(spacing: 0) {
                            ForEach(ColorFormat.allCases, id: \.self) { fmt in
                                Button(fmt.rawValue) { format = fmt; showFormatPicker = false }
                                    .font(.system(size: 11)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(format == fmt ? Color.accentColor.opacity(0.3) : Color.clear)
                                    .contentShape(Rectangle())
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4).frame(width: 60)
                        .background(bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Value input
                    switch format {
                    case .hex:
                        HStack(spacing: 2) {
                            Text("#").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                            TextField("000000", text: $hexInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                                .onSubmit { parseHex() }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(inputStroke, lineWidth: 1))

                    case .hsb:
                        HStack(spacing: 4) {
                            numericField(label: "H", value: $hInput, onSubmit: parseHSB)
                            numericField(label: "S", value: $sInput, onSubmit: parseHSB)
                            numericField(label: "B", value: $bInput, onSubmit: parseHSB)
                        }

                    case .rgb:
                        HStack(spacing: 4) {
                            numericField(label: "R", value: $hInput, onSubmit: parseRGB)
                            numericField(label: "G", value: $sInput, onSubmit: parseRGB)
                            numericField(label: "B", value: $bInput, onSubmit: parseRGB)
                        }
                    }
                }

                // 预设颜色 + 描边选项
                HStack {
                    // Remove color
                    Button(action: onRemove) {
                        toolbarIcon("None", size: 16).foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Rectangle().fill(inputStroke).frame(width: 1, height: 14)

                    // White preset
                    Button(action: { setColor(Color.white) }) {
                        Circle().fill(Color.white).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    // Black preset
                    Button(action: { setColor(Color.black) }) {
                        Circle().fill(Color.black).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if showStrokeOptions {
                        strokeOptionsView()
                    }
                }
            }
        }

        private func numericField(label: String, value: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
            VStack(spacing: 0) {
                Text(label).font(.system(size: 8)).foregroundColor(.white.opacity(0.5))
                TextField("0", text: value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 36, height: 22)
                    .background(inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(inputStroke, lineWidth: 1))
                    .onSubmit(onSubmit)
            }
        }

        private func parseHex() {
            let c = Color(hex: hexInput)
            let ns = NSColor(c)
            hue = Double(ns.hueComponent)
            sat = Double(ns.saturationComponent)
            bri = Double(ns.brightnessComponent)
            applyColor()
        }

        private func parseHSB() {
            guard let h = Double(hInput), let s = Double(sInput), let b = Double(bInput) else { return }
            hue = max(0, min(360, h)) / 360
            sat = max(0, min(100, s)) / 100
            bri = max(0, min(100, b)) / 100
            applyColor()
        }

        private func parseRGB() {
            guard let r = Double(hInput), let g = Double(sInput), let bl = Double(bInput) else { return }
            let c = Color(red: r / 255, green: g / 255, blue: bl / 255)
            let ns = NSColor(c)
            hue = Double(ns.hueComponent)
            sat = Double(ns.saturationComponent)
            bri = Double(ns.brightnessComponent)
            applyColor()
        }

        // MARK: - Stroke Options
        private func strokeOptionsView() -> some View {
            VStack(spacing: 4) {
                HStack {
                    Text("粗细").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                    Slider(value: $strokeWeight, in: 0...20)
                        .onChange(of: strokeWeight) { _, _ in onStrokeWeightChange(strokeWeight) }
                    Text("\(Int(strokeWeight))").font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
                        .frame(width: 18)
                }
                HStack(spacing: 4) {
                    Text("位置").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                    ForEach(["INSIDE", "CENTER", "OUTSIDE"], id: \.self) { align in
                        Button(action: { strokeAlign = align; onStrokeAlignChange(align) }) {
                            Text(["INSIDE":"内部","CENTER":"居中","OUTSIDE":"外部"][align] ?? align)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(strokeAlign == align ? Color(red: 0.3, green: 0.5, blue: 0.9) : Color.clear)
                                .foregroundColor(strokeAlign == align ? .white : .white.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    func toHex() -> String {
        guard let rgba = toRGBA() else { return "000000" }
        return String(format: "%02X%02X%02X", Int(rgba.r*255), Int(rgba.g*255), Int(rgba.b*255))
    }
}
