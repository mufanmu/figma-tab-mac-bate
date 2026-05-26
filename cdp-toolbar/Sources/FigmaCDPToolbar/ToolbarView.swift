import SwiftUI

struct ToolbarView: View {
    @ObservedObject var delegate: AppDelegate
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
    @State private var showFontPopover = false

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
        .background(RoundedRectangle(cornerRadius: 8).fill(FigmaColors.bg).shadow(color: FigmaColors.shadow, radius: 8, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FigmaColors.border, lineWidth: 1))
        .onChange(of: delegate.selectedNode?.id ?? "") { _, _ in
            if let node = delegate.selectedNode { updateFromNode(node) }
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
            Separator()
            NumField("字号", value: $fontSize, range: 1...999) { Task { _ = await delegate.api.setFontSize(fontSize) } }
            alignButtons(node: node)
            Separator()
            NumField("行高", value: $lineHeight, range: 0...999) { Task { _ = await delegate.api.setLineHeight(lineHeight) } }
            NumField("字距", value: $letterSpacing, range: -100...100) { Task { _ = await delegate.api.setLetterSpacing(letterSpacing) } }
            NumField("段距", value: $paragraphSpacing, range: 0...999) { Task { _ = await delegate.api.setParagraphSpacing(paragraphSpacing) } }
            NumField("缩进", value: $paragraphIndent, range: 0...999) { Task { _ = await delegate.api.setParagraphIndent(paragraphIndent) } }
            Separator()
            decorationButtons(node: node)
            textCasePicker(node: node)
            autoResizePicker(node: node)
            Separator()
            ColorPicker("", selection: $fillColor).labelsHidden().frame(width: 22).scaleEffect(0.75)
                .onChange(of: fillColor) { _, c in applyFill(c) }
            opacitySlider
        }
    }

    private func fontPicker(node: NodeProperties) -> some View {
        HStack(spacing: 3) {
            Button {
                delegate.loadFontsIfNeeded()
                if !selectedFontFamily.isEmpty {
                    delegate.expandToInclude(font: selectedFontFamily)
                }
                showFontPopover.toggle()
            } label: {
                Text(selectedFontFamily.isEmpty ? "字体" : selectedFontFamily)
                    .font(.system(size: 11)).lineLimit(1)
                    .frame(width: 105, alignment: .leading)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFontPopover, arrowEdge: .bottom) {
                ScrollViewReader { proxy in
                    List {
                        let items = Array(delegate.fonts.prefix(delegate.fontLoadCount))
                        ForEach(Array(items.enumerated()), id: \.element.family) { idx, f in
                            Button {
                                selectedFontFamily = f.family
                                if let first = f.styles.first {
                                    selectedFontStyle = first
                                    Task { _ = await delegate.api.setFontFamily(f.family, first) }
                                }
                                showFontPopover = false
                            } label: {
                                HStack {
                                    Text(f.family).font(.system(size: 11))
                                        .foregroundColor(f.family == selectedFontFamily ? .accentColor : .primary)
                                    Spacer()
                                    if f.family == selectedFontFamily {
                                        Image(systemName: "checkmark").font(.system(size: 10))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if idx >= 15 && delegate.fontLoadCount < delegate.fonts.count {
                                    delegate.loadMoreFonts()
                                }
                            }
                        }
                    }
                    .frame(width: 220, height: 260)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if !selectedFontFamily.isEmpty {
                                proxy.scrollTo(selectedFontFamily, anchor: .center)
                            }
                        }
                    }
                }
            }

            Menu {
                ForEach(delegate.fonts.first(where: { $0.family == selectedFontFamily })?.styles ?? [], id: \.self) { s in
                    Button {
                        selectedFontStyle = s
                        Task { _ = await delegate.api.setFontFamily(selectedFontFamily, s) }
                    } label: { Text(s) }
                }
            } label: {
                Text(selectedFontStyle).font(.system(size: 10)).lineLimit(1)
                    .frame(width: 75, alignment: .leading)
            }
            .menuStyle(.borderlessButton).frame(width: 80)
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
                .background(a == t ? FigmaColors.border : Color.clear).clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func decorationButtons(node: NodeProperties) -> some View {
        let d = node.textDecoration ?? "NONE"
        return HStack(spacing: 2) {
            ToggleBtn(icon: "underline", active: d == "UNDERLINE", size: 24) {
                Task { _ = await delegate.api.setTextDecoration(d == "UNDERLINE" ? "NONE" : "UNDERLINE") }
            }
            ToggleBtn(icon: "strikethrough", active: d == "STRIKETHROUGH", size: 24) {
                Task { _ = await delegate.api.setTextDecoration(d == "STRIKETHROUGH" ? "NONE" : "STRIKETHROUGH") }
            }
        }
    }

    private func textCasePicker(node: NodeProperties) -> some View {
        let c = node.textCase ?? "ORIGINAL"
        return HStack(spacing: 2) {
            ForEach(Array(zip(["ORIGINAL","UPPER","LOWER","TITLE"], ["Aa","AA","aa","Aa"])), id: \.0) { v, label in
                Button { Task { _ = await delegate.api.setTextCase(v) } } label: {
                    Text(label).font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain).frame(width: 24, height: 24)
                .background(c == v ? FigmaColors.border : Color.clear).clipShape(RoundedRectangle(cornerRadius: 4))
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
                .background(r == v ? FigmaColors.border : Color.clear).clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Shape

    private func shapeToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 6) {
            Text(node.name.prefix(14)).font(.system(size: 11, weight: .medium)).foregroundColor(FigmaColors.textPrimary).lineLimit(1)
            Separator()
            ColorPicker("", selection: $fillColor).labelsHidden().frame(width: 22).scaleEffect(0.75)
                .onChange(of: fillColor) { _, c in applyFill(c) }
            NumField("不透明", value: $opacityValue, range: 0...1, mult: 100, fmt: "%.0f%%") { Task { _ = await delegate.api.setOpacity(opacityValue) } }
            Separator()
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
            Text("\(node.selectionCount) 个").font(.system(size: 11, weight: .medium)).foregroundColor(FigmaColors.textPrimary)
            Separator()
            IconBtn(icon: "align.horizontal.left") { Task { _ = await delegate.api.alignLeft() } }
            IconBtn(icon: "align.horizontal.center") { Task { _ = await delegate.api.alignHorizontalCenter() } }
            IconBtn(icon: "align.horizontal.right") { Task { _ = await delegate.api.alignRight() } }
            Separator()
            IconBtn(icon: "align.vertical.top") { Task { _ = await delegate.api.alignTop() } }
            IconBtn(icon: "align.vertical.center") { Task { _ = await delegate.api.alignVerticalCenter() } }
            IconBtn(icon: "align.vertical.bottom") { Task { _ = await delegate.api.alignBottom() } }
            Separator()
            IconBtn(icon: "arrow.left.and.right") { Task { _ = await delegate.api.distributeHorizontal() } }
            IconBtn(icon: "arrow.up.and.down") { Task { _ = await delegate.api.distributeVertical() } }
        }
    }

    // MARK: - Shared

    private struct Separator: View { var body: some View {
        Rectangle().fill(FigmaColors.border).frame(width: 1, height: 26)
    }}

    private func NumField(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, mult: Double = 1, fmt: String = "%.0f", onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 8)).foregroundColor(FigmaColors.textSecondary)
            TextField("", value: Binding(get: { value.wrappedValue * mult }, set: { value.wrappedValue = $0 / mult }), format: .number)
                .font(.system(size: 10, design: .monospaced)).frame(width: 34).multilineTextAlignment(.center).textFieldStyle(.plain)
                .onSubmit { onChange() }
            VStack(spacing: -3) {
                UpDownBtn(icon: "chevron.up") { value.wrappedValue = min(value.wrappedValue + 1, range.upperBound); onChange() }
                UpDownBtn(icon: "chevron.down") { value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound); onChange() }
            }
        }
        .frame(height: 28).padding(.horizontal, 4).background(FigmaColors.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private struct UpDownBtn: View { let icon: String; let a: () -> Void; var body: some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 6, weight: .bold)) }
            .buttonStyle(.plain).frame(width: 14, height: 10)
    }}

    private struct ToggleBtn: View { let icon: String; let active: Bool; let size: CGFloat; let a: () -> Void; var body: some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 10)) }
            .buttonStyle(.plain).frame(width: size, height: size)
            .background(active ? FigmaColors.border : Color.clear).clipShape(RoundedRectangle(cornerRadius: 4))
    }}

    private struct IconBtn: View { let icon: String; let a: () -> Void; var body: some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 11)) }
            .buttonStyle(.plain).frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }}

    private var opacitySlider: some View {
        HStack(spacing: 2) {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 8)).foregroundColor(FigmaColors.textSecondary)
            Slider(value: $opacityValue, in: 0...1).frame(width: 40)
                .onChange(of: opacityValue) { _, v in Task { _ = await delegate.api.setOpacity(v) } }
            Text("\(Int(opacityValue * 100))%").font(.system(size: 8, design: .monospaced)).foregroundColor(FigmaColors.textSecondary).frame(width: 24)
        }
    }

    private func applyFill(_ c: Color) { guard let rgba = c.toRGBA() else { return }; Task { _ = await delegate.api.setFillColor(rgba.r, rgba.g, rgba.b, rgba.a) } }
    private func applyStroke(_ c: Color) { guard let rgba = c.toRGBA() else { return }; Task { _ = await delegate.api.setStrokeColor(rgba.r, rgba.g, rgba.b) } }
}
