import SwiftUI

struct ToolbarView: View {
    @ObservedObject var delegate: AppDelegate
    @State private var fillColor: Color = .yellow
    @State private var cornerRadius: Double = 0
    @State private var opacityValue: Double = 1
    @State private var fontSize: Double = 16

    var body: some View {
        HStack(spacing: 0) {
            if let node = delegate.selectedNode {
                if node.type == .text {
                    textToolbar(node: node)
                } else if node.type.isShape {
                    shapeToolbar(node: node)
                } else {
                    basicToolbar(node: node)
                }
            } else {
                idleView
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: FigmaTokens.cornerRadius)
                .fill(FigmaColors.bg)
                .shadow(color: FigmaColors.shadow, radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FigmaTokens.cornerRadius)
                .stroke(FigmaColors.border, lineWidth: 1)
        )
        .onChange(of: delegate.selectedNode?.id ?? "") { _, _ in
            if let node = delegate.selectedNode { updateFromNode(node) }
        }
    }

    private var idleView: some View {
        HStack(spacing: 6) {
            Image(systemName: delegate.isConnected
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 11))
                .foregroundColor(delegate.isConnected ? .green : .red)
            Text(delegate.statusText)
                .font(.system(size: 11))
                .foregroundColor(FigmaColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updateFromNode(_ node: NodeProperties) {
        if let c = node.fillColor {
            fillColor = Color(red: c.r, green: c.g, blue: c.b)
            opacityValue = node.fillOpacity ?? node.opacity
        }
        cornerRadius = node.cornerRadius ?? 0
        if let fs = node.fontSize { fontSize = fs }
    }

    private func textToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 8) {
            nodeLabel(node)

            Separator()

            ColorPicker("", selection: $fillColor)
                .labelsHidden().frame(width: 22).scaleEffect(0.75)
                .onChange(of: fillColor) { _, c in applyColor(c) }

            stepper("字号", value: $fontSize, range: 1...999) {
                Task { _ = await delegate.api.setFontSize(fontSize) }
            }

            Separator()
            Text(node.characters?.prefix(30) ?? "")
                .font(.system(size: 10))
                .foregroundColor(FigmaColors.textSecondary)
                .lineLimit(1)
            Separator()
            opacityControl
        }
    }

    private func shapeToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 8) {
            nodeLabel(node)

            Separator()

            ColorPicker("", selection: $fillColor)
                .labelsHidden().frame(width: 22).scaleEffect(0.75)
                .onChange(of: fillColor) { _, c in applyColor(c) }

            stepper("圆角", value: $cornerRadius, range: 0...999) {
                Task { _ = await delegate.api.setCornerRadius(cornerRadius) }
            }

            Separator()
            opacityControl

            if node.selectionCount > 1 {
                Separator()
                Text("+\(node.selectionCount - 1)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(FigmaColors.accent)
            }
        }
    }

    private func basicToolbar(node: NodeProperties) -> some View {
        HStack(spacing: 8) {
            nodeLabel(node)
            Separator()
            Text("\(Int(node.width))×\(Int(node.height))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(FigmaColors.textSecondary)
        }
    }

    private func nodeLabel(_ node: NodeProperties) -> some View {
        Text(node.name.prefix(14))
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(FigmaColors.textPrimary)
            .lineLimit(1)
    }

    private struct Separator: View {
        var body: some View {
            Rectangle()
                .fill(FigmaColors.border)
                .frame(width: 1, height: 20)
        }
    }

    private func stepper(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(FigmaColors.textSecondary)
            TextField("", value: value, format: .number)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 30)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .onSubmit { onChange() }
            VStack(spacing: -2) {
                upDownButton("chevron.up") {
                    value.wrappedValue = min(value.wrappedValue + 1, range.upperBound)
                    onChange()
                }
                upDownButton("chevron.down") {
                    value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound)
                    onChange()
                }
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 4)
        .background(FigmaColors.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func upDownButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 6, weight: .bold))
        }
        .buttonStyle(.plain)
        .frame(width: 12, height: 8)
    }

    private var opacityControl: some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 9))
                .foregroundColor(FigmaColors.textSecondary)
            Slider(value: $opacityValue, in: 0...1)
                .frame(width: 50)
                .onChange(of: opacityValue) { _, v in
                    Task { _ = await delegate.api.setOpacity(v) }
                }
            Text("\(Int(opacityValue * 100))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(FigmaColors.textSecondary)
                .frame(width: 24)
        }
    }

    private func applyColor(_ color: Color) {
        guard let rgba = color.toRGBA() else { return }
        Task { _ = await delegate.api.setFillColor(rgba.r, rgba.g, rgba.b, rgba.a) }
    }
}
