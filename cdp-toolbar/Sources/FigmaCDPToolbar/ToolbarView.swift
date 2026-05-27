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
    @State private var searchText: String = ""
    @State private var showDropdown: Bool = false
    @State private var dismissTask: Task<Void, Never>? = nil
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
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: FigmaTokens.roundedMd).fill(theme.canvas).shadow(color: theme.shadow, radius: 8, y: 2))
        .overlay(RoundedRectangle(cornerRadius: FigmaTokens.roundedMd).stroke(theme.hairline, lineWidth: 1))
        .onChange(of: delegate.selectedNode?.id ?? "") { _, _ in
            if let node = delegate.selectedNode {
                updateFromNode(node)
                searchText = ""
                delegate.loadAllFontsForSearch()
            }
        }
    }

    private func updateFromNode(_ node: NodeProperties) {
        if let c = node.fillColor { fillColor = Color(red: c.r, green: c.g, blue: c.b); opacityValue = node.fillOpacity ?? node.opacity }
        if let sc = node.strokeColor { strokeColor = Color(red: sc.r, green: sc.g, blue: sc.b) }
        cornerRadius = node.cornerRadius ?? 0; strokeWeight = node.strokeWeight ?? 1
        if let fs = node.fontSize { fontSize = fs }
        lineHeight = node.lineHeight ?? 0; letterSpacing = node.letterSpacing ?? 0
        paragraphSpacing = node.paragraphSpacing ?? 0; paragraphIndent = node.paragraphIndent ?? 0
        if let fn = node.fontName { selectedFontFamily = fn }
        if let fw = node.fontWeight { selectedFontStyle = fw }
    }

    // MARK: - Text

    private func textToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 6) {
            fontPicker(node: node)
            Separator(theme: theme)
            NumField("字号", value: $fontSize, range: 1...999) { Task { _ = await delegate.api.setFontSize(fontSize) } }
            alignButtons(node: node)
            Separator(theme: theme)
            NumField("行高", value: $lineHeight, range: 0...999) { Task { _ = await delegate.api.setLineHeight(lineHeight) } }
            NumField("字距", value: $letterSpacing, range: -100...100) { Task { _ = await delegate.api.setLetterSpacing(letterSpacing) } }
            NumField("段距", value: $paragraphSpacing, range: 0...999) { Task { _ = await delegate.api.setParagraphSpacing(paragraphSpacing) } }
            NumField("缩进", value: $paragraphIndent, range: 0...999) { Task { _ = await delegate.api.setParagraphIndent(paragraphIndent) } }
            Separator(theme: theme)
            decorationButtons(node: node)
            textCasePicker(node: node)
            autoResizePicker(node: node)
            Separator(theme: theme)
            ColorPicker("", selection: $fillColor).labelsHidden().frame(width: 22).scaleEffect(0.75)
                .onChange(of: fillColor) { _, c in applyFill(c) }
            opacitySlider
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
            // 搜索输入框
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
            .frame(width: 130)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(theme.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedSm))
            .overlay(
                RoundedRectangle(cornerRadius: FigmaTokens.roundedSm)
                    .stroke(theme.hairline, lineWidth: 1)
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
            }

            // 样式选择（仅一种样式时不可点击）
            let fontStyles = delegate.fonts.first(where: { $0.family == selectedFontFamily })?.styles ?? []
            Menu {
                ForEach(fontStyles, id: \.self) { s in
                    Button {
                        selectedFontStyle = s
                        Task { await delegate.api.setFontFamily(selectedFontFamily, s) }
                    } label: { Text(s) }
                }
            } label: {
                Text(selectedFontStyle).font(FigmaTokens.fontBodySmall).lineLimit(1)
                    .frame(width: 75, alignment: .leading)
                    .opacity(fontStyles.count <= 1 ? 0.35 : 1)
            }
            .menuStyle(.borderlessButton).frame(width: 80)
            .disabled(fontStyles.count <= 1)
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                showDropdown = true
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if focused && searchText.isEmpty {
                delegate.loadFontsIfNeeded()
                showDropdown = true
            }
        }
    }

    private func alignButtons(node: NodeProperties) -> some View {
        let a = node.textAlign ?? "LEFT"
        return HStack(spacing: 2) {
            ForEach(["LEFT","CENTER","RIGHT","JUSTIFIED"], id: \.self) { t in
                let icon = switch t { case "LEFT":"text.alignleft"; case "CENTER":"text.aligncenter"; case "RIGHT":"text.alignright"; default:"text.justify" }
                Button { Task { _ = await delegate.api.setTextAlign(t) } } label: {
                    Image(systemName: icon).font(.system(size: 10))
                }
                .buttonStyle(.plain).frame(width: 24, height: 24)
                .background(a == t ? theme.hairline : Color.clear).clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedSm))
            }
        }
    }

    private func decorationButtons(node: NodeProperties) -> some View {
        let d = node.textDecoration ?? "NONE"
        return HStack(spacing: 2) {
            ToggleBtn(icon: "underline", active: d == "UNDERLINE", size: 24, theme: theme) {
                Task { _ = await delegate.api.setTextDecoration(d == "UNDERLINE" ? "NONE" : "UNDERLINE") }
            }
            ToggleBtn(icon: "strikethrough", active: d == "STRIKETHROUGH", size: 24, theme: theme) {
                Task { _ = await delegate.api.setTextDecoration(d == "STRIKETHROUGH" ? "NONE" : "STRIKETHROUGH") }
            }
        }
    }

    private func textCasePicker(node: NodeProperties) -> some View {
        let c = node.textCase ?? "ORIGINAL"
        return HStack(spacing: 2) {
            ForEach(Array(zip(["ORIGINAL","UPPER","LOWER","TITLE"], ["Aa","AA","aa","Aa"])), id: \.0) { v, label in
                Button { Task { _ = await delegate.api.setTextCase(v) } } label: {
                    Text(label).font(FigmaTokens.fontBodySmall.weight(.medium))
                }
                .buttonStyle(.plain).frame(width: 24, height: 24)
                .background(c == v ? theme.hairline : Color.clear).clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedSm))
            }
        }
    }

    private func autoResizePicker(node: NodeProperties) -> some View {
        let r = node.textAutoResize ?? "NONE"
        return HStack(spacing: 2) {
            ForEach(Array(zip(["NONE","WIDTH_AND_HEIGHT","HEIGHT"], ["rectangle","rectangle.expand.vertical","rectangle.expand.diagonal"])), id: \.0) { v, icon in
                Button { Task { _ = await delegate.api.setTextAutoResize(v) } } label: {
                    Image(systemName: icon).font(.system(size: 10))
                }
                .buttonStyle(.plain).frame(width: 24, height: 24)
                .background(r == v ? theme.hairline : Color.clear).clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedSm))
            }
        }
    }

    // MARK: - Shape

    private func shapeToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 6) {
            Text(node.name.prefix(14)).font(FigmaTokens.fontBodyMedium).foregroundColor(theme.ink).lineLimit(1)
            Separator(theme: theme)
            ColorPicker("", selection: $fillColor).labelsHidden().frame(width: 22).scaleEffect(0.75)
                .onChange(of: fillColor) { _, c in applyFill(c) }
            NumField("不透明", value: $opacityValue, range: 0...1, mult: 100, fmt: "%.0f%%") { Task { _ = await delegate.api.setOpacity(opacityValue) } }
            Separator(theme: theme)
            ColorPicker("", selection: $strokeColor).labelsHidden().frame(width: 22).scaleEffect(0.75)
                .onChange(of: strokeColor) { _, c in applyStroke(c) }
            NumField("粗细", value: $strokeWeight, range: 0...100) { Task { _ = await delegate.api.setStrokeWeight(strokeWeight) } }
            NumField("圆角", value: $cornerRadius, range: 0...999) { Task { _ = await delegate.api.setCornerRadius(cornerRadius) } }
            Spacer()
            opacitySlider
        }
    }

    // MARK: - Align

    private func alignToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 6) {
            Text("\(node.selectionCount) 个").font(FigmaTokens.fontBodyMedium).foregroundColor(theme.ink)
            Separator(theme: theme)
            IconBtn(icon: "align.horizontal.left") { Task { _ = await delegate.api.alignLeft() } }
            IconBtn(icon: "align.horizontal.center") { Task { _ = await delegate.api.alignHorizontalCenter() } }
            IconBtn(icon: "align.horizontal.right") { Task { _ = await delegate.api.alignRight() } }
            Separator(theme: theme)
            IconBtn(icon: "align.vertical.top") { Task { _ = await delegate.api.alignTop() } }
            IconBtn(icon: "align.vertical.center") { Task { _ = await delegate.api.alignVerticalCenter() } }
            IconBtn(icon: "align.vertical.bottom") { Task { _ = await delegate.api.alignBottom() } }
            Separator(theme: theme)
            IconBtn(icon: "arrow.left.and.right") { Task { _ = await delegate.api.distributeHorizontal() } }
            IconBtn(icon: "arrow.up.and.down") { Task { _ = await delegate.api.distributeVertical() } }
        }
    }

    // MARK: - Shared

    private struct Separator: View { let theme: FigmaTheme; var body: some View {
        Rectangle().fill(theme.hairline).frame(width: 1, height: 26)
    }}

    private func NumField(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, mult: Double = 1, fmt: String = "%.0f", onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Text(label).font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink)
            TextField("", value: Binding(get: { value.wrappedValue * mult }, set: { value.wrappedValue = $0 / mult }), format: .number)
                .font(FigmaTokens.fontCaption).frame(width: 34).multilineTextAlignment(.center).textFieldStyle(.plain)
                .onSubmit { onChange() }
            VStack(spacing: -3) {
                UpDownBtn(icon: "chevron.up") { value.wrappedValue = min(value.wrappedValue + 1, range.upperBound); onChange() }
                UpDownBtn(icon: "chevron.down") { value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound); onChange() }
            }
        }
        .frame(height: 28).padding(.horizontal, 4).background(theme.surfaceSoft).clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedSm))
    }

    private struct UpDownBtn: View { let icon: String; let a: () -> Void; var body: some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 6, weight: .bold)) }
            .buttonStyle(.plain).frame(width: 14, height: 10)
    }}

    private struct ToggleBtn: View { let icon: String; let active: Bool; let size: CGFloat; let theme: FigmaTheme; let a: () -> Void; var body: some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 10)) }
            .buttonStyle(.plain).frame(width: size, height: size)
            .background(active ? theme.hairline : Color.clear).clipShape(RoundedRectangle(cornerRadius: FigmaTokens.roundedSm))
    }}

    private struct IconBtn: View { let icon: String; let a: () -> Void; var body: some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 11)) }
            .buttonStyle(.plain).frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }}

    private var opacitySlider: some View {
        HStack(spacing: 2) {
            Image(systemName: "circle.lefthalf.filled").font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink)
            Slider(value: $opacityValue, in: 0...1).frame(width: 40)
                .onChange(of: opacityValue) { _, v in Task { _ = await delegate.api.setOpacity(v) } }
            Text("\(Int(opacityValue * 100))%").font(FigmaTokens.fontCaptionSmall).foregroundColor(theme.ink).frame(width: 24)
        }
    }

    private func applyFill(_ c: Color) { guard let rgba = c.toRGBA() else { return }; Task { _ = await delegate.api.setFillColor(rgba.r, rgba.g, rgba.b, rgba.a) } }
    private func applyStroke(_ c: Color) { guard let rgba = c.toRGBA() else { return }; Task { _ = await delegate.api.setStrokeColor(rgba.r, rgba.g, rgba.b) } }
}
