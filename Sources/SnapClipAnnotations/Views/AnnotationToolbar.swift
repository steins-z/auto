import SwiftUI

/// Contextual annotation toolbar with vibrancy backing.
public struct AnnotationToolbar: View {
    @ObservedObject var viewModel: AnnotationEditorViewModel
    var onExport: (() -> Void)?

    public init(viewModel: AnnotationEditorViewModel, onExport: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onExport = onExport
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(AnnotationTool.allCases) { tool in
                    toolButton(tool)
                }
                Divider().frame(height: 22).padding(.horizontal, 4)
                historyControls
                Divider().frame(height: 22).padding(.horizontal, 4)
                exportButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Contextual sub-controls — appear only for tools that need them
            if needsContextualControls {
                contextualControls
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(VibrancyBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .animation(.easeInOut(duration: 0.18), value: viewModel.selectedTool)
    }

    // MARK: - Tool buttons

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = viewModel.selectedTool == tool
        return Button {
            viewModel.selectedTool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 26)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }

    // MARK: - History

    private var historyControls: some View {
        HStack(spacing: 4) {
            Button { viewModel.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canUndo)
            .help("Undo")

            Button { viewModel.redo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canRedo)
            .help("Redo")

            Button { viewModel.clearAll() } label: {
                Image(systemName: "trash").frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.annotations.isEmpty)
            .help("Clear all")
        }
    }

    // MARK: - Export

    private var exportButton: some View {
        Button {
            onExport?()
        } label: {
            Label("Done", systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contextual sub-controls

    private var needsContextualControls: Bool {
        viewModel.selectedTool.supportsStroke ||
        viewModel.selectedTool.supportsFill ||
        viewModel.selectedTool.supportsFontSize ||
        viewModel.selectedTool == .blur ||
        viewModel.selectedTool == .crop
    }

    @ViewBuilder
    private var contextualControls: some View {
        HStack(spacing: 12) {
            if viewModel.selectedTool.supportsStroke || viewModel.selectedTool.supportsFontSize {
                colorPicker
            }
            if viewModel.selectedTool.supportsStroke {
                widthSlider(label: "Width", range: 1...20, value: $viewModel.style.strokeWidth)
            }
            if viewModel.selectedTool.supportsFontSize {
                widthSlider(label: "Size", range: 8...96, value: $viewModel.style.fontSize)
            }
            if viewModel.selectedTool == .blur {
                widthSlider(label: "Blur", range: 4...60, value: $viewModel.style.blurRadius)
            }
            if viewModel.selectedTool == .crop {
                Button("Reset crop") { viewModel.resetCrop() }
                    .disabled(viewModel.cropRect == nil)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }

    private var colorPicker: some View {
        ColorPicker("", selection: Binding(
            get: { viewModel.style.strokeColor.swiftUIColor },
            set: { newColor in
                if let c = AnnotationColor(newColor) {
                    viewModel.style.strokeColor = c
                }
            }
        ), supportsOpacity: true)
        .labelsHidden()
        .frame(width: 36)
    }

    private func widthSlider(label: String, range: ClosedRange<CGFloat>, value: Binding<CGFloat>) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Slider(value: value, in: range).frame(width: 100)
            Text(String(format: "%.0f", value.wrappedValue))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

// MARK: - SwiftUI Color → AnnotationColor bridge

extension AnnotationColor {
    init?(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.init(red: Double(ns.redComponent),
                  green: Double(ns.greenComponent),
                  blue: Double(ns.blueComponent),
                  opacity: Double(ns.alphaComponent))
    }
}
