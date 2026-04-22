import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
public final class AnnotationEditorViewModel: ObservableObject {

    // MARK: - Inputs / Outputs

    @Published public private(set) var image: NSImage
    /// Image size in points (independent of display scale).
    public var imageSize: CGSize { image.size }

    @Published public var annotations: [Annotation] = []
    @Published public var selectedTool: AnnotationTool = .select
    @Published public var style: AnnotationStyle = .default

    /// Drag-in-progress annotation (preview during gesture).
    @Published public var inProgress: Annotation?

    /// Crop rectangle in image coordinates. nil = full image.
    @Published public var cropRect: CGRect?
    /// Crop selection currently being dragged (preview).
    @Published public var pendingCropRect: CGRect?

    /// Text being edited (for text tool focus).
    @Published public var editingTextID: UUID?

    private var nextStepNumber: Int { (annotations.compactMap { ann -> Int? in
        if case .numberedStep(_, let n) = ann.kind { return n } else { return nil }
    }.max() ?? 0) + 1 }

    // Undo / redo stacks
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    public init(image: NSImage) {
        self.image = image
    }

    // MARK: - History

    public func snapshot() {
        undoStack.append(annotations)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    public func clearAll() {
        snapshot()
        annotations.removeAll()
    }

    // MARK: - Drag handlers (image-space coordinates)

    public func beginDrag(at point: CGPoint) {
        switch selectedTool {
        case .select:
            inProgress = nil
        case .rectangle:
            inProgress = Annotation(kind: .rectangle(rect: CGRect(origin: point, size: .zero)),
                                    style: style)
        case .ellipse:
            inProgress = Annotation(kind: .ellipse(rect: CGRect(origin: point, size: .zero)),
                                    style: style)
        case .line:
            inProgress = Annotation(kind: .line(start: point, end: point), style: style)
        case .arrow:
            inProgress = Annotation(kind: .arrow(start: point, end: point), style: style)
        case .pen:
            inProgress = Annotation(kind: .pen(points: [point]), style: style)
        case .highlight:
            var s = style
            if s.fillColor == nil { s.fillColor = .highlightYellow }
            inProgress = Annotation(kind: .highlight(rect: CGRect(origin: point, size: .zero)),
                                    style: s)
        case .blur:
            inProgress = Annotation(kind: .blur(rect: CGRect(origin: point, size: .zero)),
                                    style: style)
        case .text:
            inProgress = nil
        case .numberedStep:
            inProgress = nil
        case .crop:
            pendingCropRect = CGRect(origin: point, size: .zero)
        }
    }

    public func updateDrag(to point: CGPoint, from start: CGPoint) {
        guard var current = inProgress else {
            if selectedTool == .crop, let origin = pendingCropRect?.origin {
                pendingCropRect = CGRect(x: min(origin.x, point.x),
                                         y: min(origin.y, point.y),
                                         width: abs(point.x - origin.x),
                                         height: abs(point.y - origin.y))
            }
            return
        }
        switch current.kind {
        case .rectangle:
            current.kind = .rectangle(rect: rect(from: start, to: point))
        case .ellipse:
            current.kind = .ellipse(rect: rect(from: start, to: point))
        case .line:
            current.kind = .line(start: start, end: point)
        case .arrow:
            current.kind = .arrow(start: start, end: point)
        case .pen(var pts):
            pts.append(point)
            current.kind = .pen(points: pts)
        case .highlight:
            current.kind = .highlight(rect: rect(from: start, to: point))
        case .blur:
            current.kind = .blur(rect: rect(from: start, to: point))
        default:
            break
        }
        inProgress = current
    }

    public func endDrag(at point: CGPoint, from start: CGPoint) {
        if selectedTool == .crop {
            if let pending = pendingCropRect, pending.width > 4, pending.height > 4 {
                snapshot()
                cropRect = pending
            }
            pendingCropRect = nil
            return
        }
        guard let current = inProgress else { return }
        defer { inProgress = nil }
        // Skip degenerate shapes
        if current.boundingRect.width < 2 && current.boundingRect.height < 2,
           case .pen = current.kind {
            return
        }
        snapshot()
        annotations.append(current)
    }

    // MARK: - Click-place handlers (text & numbered steps)

    public func placeText(at point: CGPoint) {
        snapshot()
        let ann = Annotation(kind: .text(origin: point, string: ""), style: style)
        annotations.append(ann)
        editingTextID = ann.id
    }

    public func updateText(_ id: UUID, string: String) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if case .text(let origin, _) = annotations[idx].kind {
            annotations[idx].kind = .text(origin: origin, string: string)
        }
    }

    public func placeNumberedStep(at point: CGPoint) {
        snapshot()
        var s = style
        if s.fillColor == nil { s.fillColor = s.strokeColor }
        let ann = Annotation(
            kind: .numberedStep(center: point, number: nextStepNumber),
            style: s
        )
        annotations.append(ann)
    }

    // MARK: - Crop / Resize

    public func resetCrop() {
        snapshot()
        cropRect = nil
    }

    /// Effective canvas size after applying any crop.
    public var effectiveSize: CGSize {
        cropRect?.size ?? imageSize
    }

    // MARK: - Helpers

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
