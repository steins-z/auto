import SwiftUI
import AppKit

/// SwiftUI wrapper around NSVisualEffectView to give SnapClip's toolbars a frosted-glass feel.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.autoresizingMask = [.width, .height]
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.layer?.cornerRadius = cornerRadius
    }
}

extension View {
    /// Apply a frosted-glass background — used for capture toolbars and floating previews.
    func frostedBackground(material: NSVisualEffectView.Material = .hudWindow,
                           cornerRadius: CGFloat = 12) -> some View {
        background(
            VisualEffectBackground(material: material, cornerRadius: cornerRadius)
        )
    }
}
