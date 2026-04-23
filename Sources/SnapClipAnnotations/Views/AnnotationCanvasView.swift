import SwiftUI
import AppKit

/// Canvas surface that draws the source image plus all annotation overlays
/// and translates pointer gestures into model updates.
public struct AnnotationCanvasView: View {
    @ObservedObject var viewModel: AnnotationEditorViewModel

    @State private var dragStart: CGPoint?

    public init(viewModel: AnnotationEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { proxy in
            let displayRect = imageDisplayRect(containerSize: proxy.size,
                                               imageSize: viewModel.imageSize)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001) // hit-test surface

                // Source image
                Image(nsImage: viewModel.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)

                // Blur regions are baked in the exporter; here we render a live
                // preview by overlaying a CIImage-pixellated version on top.
                blurOverlay(displayRect: displayRect)

                // Vector annotation layer (Canvas, image-coordinate space)
                Canvas { ctx, _ in
                    let scale = displayRect.width / viewModel.imageSize.width
                    ctx.translateBy(x: displayRect.minX, y: displayRect.minY)
                    ctx.scaleBy(x: scale, y: scale)
                    for ann in viewModel.annotations {
                        var c = ctx
                        AnnotationRenderer.draw(ann, in: &c)
                    }
                    if let preview = viewModel.inProgress {
                        var c = ctx
                        AnnotationRenderer.draw(preview, in: &c)
                    }
                }
                .allowsHitTesting(false)
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)

                // Crop overlay
                cropOverlay(displayRect: displayRect)

                // Text edit fields (overlaid on text annotations)
                ForEach(textAnnotations) { ann in
                    if case .text(let origin, let string) = ann.kind {
                        textField(for: ann, origin: origin, string: string,
                                  displayRect: displayRect)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(displayRect: displayRect))
            .onTapGesture { location in
                handleTap(at: location, displayRect: displayRect)
            }
        }
        .background(Color(white: 0.12))
    }

    // MARK: - Layout

    /// Aspect-fit the image inside the container.
    private func imageDisplayRect(containerSize: CGSize, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let inset: CGFloat = 24
        let avail = CGSize(width: max(0, containerSize.width - inset * 2),
                           height: max(0, containerSize.height - inset * 2))
        let scale = min(avail.width / imageSize.width, avail.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (containerSize.width - w) / 2,
                      y: (containerSize.height - h) / 2,
                      width: w, height: h)
    }

    private func toImageSpace(_ point: CGPoint, displayRect: CGRect) -> CGPoint {
        let scale = viewModel.imageSize.width / displayRect.width
        return CGPoint(
            x: (point.x - displayRect.minX) * scale,
            y: (point.y - displayRect.minY) * scale
        )
    }

    private func toViewSpace(_ point: CGPoint, displayRect: CGRect) -> CGPoint {
        let scale = displayRect.width / viewModel.imageSize.width
        return CGPoint(
            x: displayRect.minX + point.x * scale,
            y: displayRect.minY + point.y * scale
        )
    }

    // MARK: - Gestures

    private func canvasGesture(displayRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let imgPoint = toImageSpace(value.location, displayRect: displayRect)
                let imgStart = toImageSpace(value.startLocation, displayRect: displayRect)
                if dragStart == nil {
                    dragStart = imgStart
                    viewModel.beginDrag(at: imgStart)
                }
                viewModel.updateDrag(to: imgPoint, from: imgStart)
            }
            .onEnded { value in
                let imgPoint = toImageSpace(value.location, displayRect: displayRect)
                let imgStart = toImageSpace(value.startLocation, displayRect: displayRect)
                viewModel.endDrag(at: imgPoint, from: imgStart)
                dragStart = nil
            }
    }

    private func handleTap(at location: CGPoint, displayRect: CGRect) {
        let imgPoint = toImageSpace(location, displayRect: displayRect)
        switch viewModel.selectedTool {
        case .text:           viewModel.placeText(at: imgPoint)
        case .numberedStep:   viewModel.placeNumberedStep(at: imgPoint)
        default:              break
        }
    }

    // MARK: - Text annotations

    private var textAnnotations: [Annotation] {
        viewModel.annotations.filter {
            if case .text = $0.kind { return true } else { return false }
        }
    }

    private func textField(for annotation: Annotation,
                           origin: CGPoint,
                           string: String,
                           displayRect: CGRect) -> some View {
        let viewPoint = toViewSpace(origin, displayRect: displayRect)
        let scale = displayRect.width / viewModel.imageSize.width
        let displayFontSize = annotation.style.fontSize * scale
        let editorWidth: CGFloat = 200
        let editorHeight = displayFontSize * 1.4
        return TextField("Text", text: Binding(
            get: { string },
            set: { viewModel.updateText(annotation.id, string: $0) }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: displayFontSize, weight: .semibold))
        .foregroundColor(Color(annotation.style.strokeColor))
        .frame(width: editorWidth, height: editorHeight, alignment: .leading)
        // SwiftUI .position centers the frame on (x, y). Offset by half the
        // editor frame so the *left edge* lands at viewPoint.x — matching where
        // AnnotationRenderer.draw places the text with anchor: .topLeading.
        .position(x: viewPoint.x + editorWidth / 2,
                  y: viewPoint.y + editorHeight / 2)
        .opacity(viewModel.editingTextID == annotation.id || string.isEmpty ? 1 : 0)
        .allowsHitTesting(viewModel.selectedTool == .text || viewModel.editingTextID == annotation.id)
    }

    // MARK: - Crop overlay

    @ViewBuilder
    private func cropOverlay(displayRect: CGRect) -> some View {
        let activeRect = viewModel.pendingCropRect ?? viewModel.cropRect
        if let r = activeRect {
            let scale = displayRect.width / viewModel.imageSize.width
            let frame = CGRect(
                x: displayRect.minX + r.minX * scale,
                y: displayRect.minY + r.minY * scale,
                width: r.width * scale,
                height: r.height * scale
            )
            ZStack {
                // Dim outside
                Path { path in
                    path.addRect(displayRect)
                    path.addRect(frame)
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            // Re-drawing the crop rectangle replaces the existing one. Interactive
            // resize handles will be added in a follow-up — see issue tracker.
            .allowsHitTesting(false)
        }
    }

    // MARK: - Blur live preview

    @ViewBuilder
    private func blurOverlay(displayRect: CGRect) -> some View {
        let blurRects: [CGRect] = viewModel.annotations.compactMap {
            if case .blur(let r) = $0.kind { return r } else { return nil }
        } + (viewModel.inProgress.flatMap { ann -> [CGRect] in
            if case .blur(let r) = ann.kind { return [r] } else { return [] }
        } ?? [])

        if !blurRects.isEmpty {
            BlurRegionOverlay(
                source: viewModel.image,
                pixelRadius: viewModel.style.blurRadius,
                rects: blurRects,
                displayRect: displayRect,
                imageSize: viewModel.imageSize
            )
        }
    }
}

/// Renders blur regions using the same Core Image pixellation that the exporter
/// bakes in, so the live preview matches the saved output exactly.
private struct BlurRegionOverlay: View {
    let source: NSImage
    let pixelRadius: CGFloat
    let rects: [CGRect]
    let displayRect: CGRect
    let imageSize: CGSize

    @State private var pixellated: NSImage?
    @State private var cacheKey: CGFloat = -1

    var body: some View {
        Group {
            if let pixellated {
                let scale = displayRect.width / imageSize.width
                ZStack {
                    ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                        let frame = CGRect(
                            x: displayRect.minX + r.minX * scale,
                            y: displayRect.minY + r.minY * scale,
                            width: r.width * scale,
                            height: r.height * scale
                        )
                        Image(nsImage: pixellated)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: displayRect.width, height: displayRect.height)
                            .frame(width: frame.width, height: frame.height,
                                   alignment: .topLeading)
                            .clipped()
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                .allowsHitTesting(false)
            } else {
                Color.clear
            }
        }
        .task(id: pixelRadius) {
            if cacheKey == pixelRadius, pixellated != nil { return }
            let radius = pixelRadius
            let img = source
            let result = await Task.detached(priority: .userInitiated) {
                ImageEffects.pixellated(img, pixelRadius: radius)
            }.value
            await MainActor.run {
                self.pixellated = result
                self.cacheKey = radius
            }
        }
    }
}
