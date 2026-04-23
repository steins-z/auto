import Foundation
import SwiftUI

/// Codable RGBA color suitable for annotation styling.
public struct AnnotationColor: Codable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    public static let red    = AnnotationColor(red: 1.00, green: 0.23, blue: 0.19)
    public static let blue   = AnnotationColor(red: 0.00, green: 0.48, blue: 1.00)
    public static let green  = AnnotationColor(red: 0.20, green: 0.78, blue: 0.35)
    public static let yellow = AnnotationColor(red: 1.00, green: 0.84, blue: 0.04)
    public static let black  = AnnotationColor(red: 0.00, green: 0.00, blue: 0.00)
    public static let white  = AnnotationColor(red: 1.00, green: 1.00, blue: 1.00)
    public static let highlightYellow = AnnotationColor(red: 1.0, green: 0.93, blue: 0.20, opacity: 0.35)
}

public extension Color {
    init(_ c: AnnotationColor) {
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.opacity)
    }
}

/// Style describing how an annotation is rendered.
public struct AnnotationStyle: Codable, Equatable, Hashable {
    public var strokeColor: AnnotationColor
    public var fillColor: AnnotationColor?
    public var strokeWidth: CGFloat
    public var fontSize: CGFloat
    /// Pixel size for blur/mosaic intensity (radius for Gaussian / pixel block size).
    public var blurRadius: CGFloat

    public init(
        strokeColor: AnnotationColor = .red,
        fillColor: AnnotationColor? = nil,
        strokeWidth: CGFloat = 3,
        fontSize: CGFloat = 18,
        blurRadius: CGFloat = 12
    ) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.blurRadius = blurRadius
    }

    public static let `default` = AnnotationStyle()
}
