import Foundation
import CoreGraphics

/// A single annotation overlaid on the canvas.
/// Geometry is stored in **image coordinates** (origin top-left, points).
public struct Annotation: Identifiable, Equatable, Hashable {
    public enum Kind: Equatable, Hashable {
        case rectangle(rect: CGRect)
        case ellipse(rect: CGRect)
        case line(start: CGPoint, end: CGPoint)
        case arrow(start: CGPoint, end: CGPoint)
        case pen(points: [CGPoint])
        case text(origin: CGPoint, string: String)
        case highlight(rect: CGRect)
        case blur(rect: CGRect)
        case numberedStep(center: CGPoint, number: Int)
    }

    public let id: UUID
    public var kind: Kind
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), kind: Kind, style: AnnotationStyle) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    /// Approximate bounding rect in image coordinates (used for hit-testing / culling).
    public var boundingRect: CGRect {
        switch kind {
        case .rectangle(let r), .ellipse(let r), .highlight(let r), .blur(let r):
            return r.standardized
        case .line(let s, let e), .arrow(let s, let e):
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(e.x - s.x), height: abs(e.y - s.y))
        case .pen(let pts):
            guard let first = pts.first else { return .zero }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in pts {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text(let origin, let string):
            let approxWidth = CGFloat(string.count) * style.fontSize * 0.6
            return CGRect(x: origin.x, y: origin.y, width: approxWidth, height: style.fontSize * 1.3)
        case .numberedStep(let center, _):
            let r: CGFloat = max(18, style.strokeWidth * 8)
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }
}
