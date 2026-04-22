import Foundation
import SwiftUI
import CoreGraphics

/// Pure rendering primitives shared by the SwiftUI Canvas and the offscreen exporter.
public enum AnnotationRenderer {

    /// Draw a single annotation using the GraphicsContext API.
    /// Coordinates passed in are already transformed to the target context space.
    public static func draw(_ annotation: Annotation, in context: inout GraphicsContext) {
        let style = annotation.style
        let strokeColor = Color(style.strokeColor)
        let fillColor = style.fillColor.map { Color($0) }

        switch annotation.kind {
        case .rectangle(let rect):
            let path = Path(rect.standardized)
            if let fillColor { context.fill(path, with: .color(fillColor)) }
            context.stroke(path, with: .color(strokeColor), lineWidth: style.strokeWidth)

        case .ellipse(let rect):
            let path = Path(ellipseIn: rect.standardized)
            if let fillColor { context.fill(path, with: .color(fillColor)) }
            context.stroke(path, with: .color(strokeColor), lineWidth: style.strokeWidth)

        case .line(let s, let e):
            var path = Path()
            path.move(to: s); path.addLine(to: e)
            context.stroke(path, with: .color(strokeColor),
                           style: StrokeStyle(lineWidth: style.strokeWidth, lineCap: .round))

        case .arrow(let s, let e):
            drawArrow(from: s, to: e, color: strokeColor, width: style.strokeWidth, in: &context)

        case .pen(let points):
            guard points.count > 1 else { return }
            var path = Path()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            context.stroke(path, with: .color(strokeColor),
                           style: StrokeStyle(lineWidth: style.strokeWidth,
                                              lineCap: .round, lineJoin: .round))

        case .text(let origin, let string):
            let attrText = Text(string)
                .font(.system(size: style.fontSize, weight: .semibold))
                .foregroundColor(strokeColor)
            context.draw(attrText, at: origin, anchor: .topLeading)

        case .highlight(let rect):
            let color = fillColor ?? Color(AnnotationColor.highlightYellow)
            context.fill(Path(rect.standardized), with: .color(color))

        case .blur:
            // Blur regions are composited by the exporter / canvas layer separately —
            // they require source-image pixel data, which the GraphicsContext does not
            // expose. We draw a thin marker stroke for editor visibility.
            if case .blur(let rect) = annotation.kind {
                let path = Path(rect.standardized)
                context.stroke(path,
                               with: .color(strokeColor.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

        case .numberedStep(let center, let number):
            let radius: CGFloat = max(14, style.strokeWidth * 6)
            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            let circle = Path(ellipseIn: rect)
            context.fill(circle, with: .color(fillColor ?? strokeColor))
            context.stroke(circle, with: .color(Color(AnnotationColor.white)),
                           lineWidth: max(1, style.strokeWidth * 0.4))
            let label = Text("\(number)")
                .font(.system(size: radius, weight: .bold))
                .foregroundColor(Color(AnnotationColor.white))
            context.draw(label, at: center, anchor: .center)
        }
    }

    private static func drawArrow(from start: CGPoint,
                                  to end: CGPoint,
                                  color: Color,
                                  width: CGFloat,
                                  in context: inout GraphicsContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.5 else { return }

        let headLength = max(12, width * 4)
        let angle = atan2(dy, dx)

        // Shaft (shortened so arrowhead doesn't overshoot)
        let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.6,
                               y: end.y - sin(angle) * headLength * 0.6)
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: shaftEnd)
        context.stroke(shaft, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))

        // Arrowhead
        let left = CGPoint(
            x: end.x - cos(angle - .pi / 7) * headLength,
            y: end.y - sin(angle - .pi / 7) * headLength
        )
        let right = CGPoint(
            x: end.x - cos(angle + .pi / 7) * headLength,
            y: end.y - sin(angle + .pi / 7) * headLength
        )
        var head = Path()
        head.move(to: end)
        head.addLine(to: left)
        head.addLine(to: CGPoint(
            x: end.x - cos(angle) * headLength * 0.7,
            y: end.y - sin(angle) * headLength * 0.7
        ))
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}
