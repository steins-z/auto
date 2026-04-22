import SwiftUI
import AppKit

/// Full annotation editor: image canvas + floating toolbar.
public struct AnnotationEditorView: View {
    @StateObject private var viewModel: AnnotationEditorViewModel
    private let onCommit: (NSImage) -> Void
    private let onCancel: (() -> Void)?

    public init(image: NSImage,
                onCommit: @escaping (NSImage) -> Void,
                onCancel: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: AnnotationEditorViewModel(image: image))
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack(alignment: .top) {
            AnnotationCanvasView(viewModel: viewModel)
                .ignoresSafeArea()

            AnnotationToolbar(viewModel: viewModel) {
                let result = AnnotationExporter.flatten(
                    image: viewModel.image,
                    annotations: viewModel.annotations,
                    cropRect: viewModel.cropRect
                )
                onCommit(result)
            }
            .padding(.top, 14)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(white: 0.10))
        .onExitCommand {
            onCancel?()
        }
    }
}

#if DEBUG
struct AnnotationEditorView_Previews: PreviewProvider {
    static var previews: some View {
        let img = NSImage(size: NSSize(width: 800, height: 500))
        img.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.unlockFocus()
        return AnnotationEditorView(image: img, onCommit: { _ in })
            .frame(width: 1000, height: 700)
    }
}
#endif
