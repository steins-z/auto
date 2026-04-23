# SnapClipAnnotations

Standalone Swift package providing the **annotation editor** for the SnapClip
macOS screenshot app.

- Swift 5.9+, SwiftUI, macOS 13+
- No third-party dependencies — pure SwiftUI + AppKit + Core Image

## Usage

```swift
import SnapClipAnnotations
import AppKit

let editor = AnnotationEditorView(image: someNSImage) { flattened in
    // `flattened` is an NSImage with all annotations burned in
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([flattened])
}
```

## Tools

Rectangle · Ellipse · Line · Arrow · Pen · Text · Highlight · Blur/Mosaic ·
Numbered Steps · Crop & Resize.

Each tool exposes contextual sub-controls (color, stroke width, font size,
blur intensity) in a vibrancy-backed floating toolbar.

## Architecture

```
Models/      Annotation, AnnotationStyle, AnnotationTool, AnnotationColor
ViewModels/  AnnotationEditorViewModel  (drag state, history, tool state)
Views/       AnnotationEditorView, AnnotationCanvasView,
             AnnotationToolbar, VibrancyBackground
Rendering/   AnnotationRenderer (vector primitives), ImageEffects (Core Image)
Export/      AnnotationExporter (flatten to NSImage, blur baked from CI)
```

The canvas works in **image-coordinate space** (top-left origin, points), so
drawn annotations are independent of the on-screen display size and zoom.

## Build / test

```bash
swift build
swift test
```

Or open `Package.swift` in Xcode.
