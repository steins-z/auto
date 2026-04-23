import Foundation
import SwiftUI

public enum AnnotationTool: String, CaseIterable, Identifiable, Hashable {
    case select
    case rectangle
    case ellipse
    case line
    case arrow
    case pen
    case text
    case highlight
    case blur
    case numberedStep
    case crop

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .select:       return "Select"
        case .rectangle:    return "Rectangle"
        case .ellipse:      return "Ellipse"
        case .line:         return "Line"
        case .arrow:        return "Arrow"
        case .pen:          return "Pen"
        case .text:         return "Text"
        case .highlight:    return "Highlight"
        case .blur:         return "Blur"
        case .numberedStep: return "Number"
        case .crop:         return "Crop"
        }
    }

    public var systemImage: String {
        switch self {
        case .select:       return "arrow.up.left.and.arrow.down.right"
        case .rectangle:    return "rectangle"
        case .ellipse:      return "circle"
        case .line:         return "line.diagonal"
        case .arrow:        return "arrow.up.right"
        case .pen:          return "pencil.tip"
        case .text:         return "textformat"
        case .highlight:    return "highlighter"
        case .blur:         return "drop.fill"
        case .numberedStep: return "1.circle.fill"
        case .crop:         return "crop"
        }
    }

    /// Whether this tool supports a stroke color/width control.
    public var supportsStroke: Bool {
        switch self {
        case .rectangle, .ellipse, .line, .arrow, .pen, .numberedStep:
            return true
        default:
            return false
        }
    }

    public var supportsFill: Bool {
        switch self {
        case .rectangle, .ellipse, .numberedStep:
            return true
        default:
            return false
        }
    }

    public var supportsFontSize: Bool { self == .text }
}
