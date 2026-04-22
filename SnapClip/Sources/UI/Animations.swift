import SwiftUI

enum SnapClipAnimation {
    /// Spring used for overlay/preview appear/dismiss transitions.
    static let overlay: Animation = .spring(response: 0.32, dampingFraction: 0.78, blendDuration: 0)
    /// Spring used for toolbar reveals — slightly snappier.
    static let toolbar: Animation = .spring(response: 0.22, dampingFraction: 0.86, blendDuration: 0)
}

extension AnyTransition {
    /// Soft scale + fade — the overlay fades in from 96% to 100% with opacity rising.
    static var overlayAppear: AnyTransition {
        .scale(scale: 0.96).combined(with: .opacity)
    }

    /// Toolbar transition — slides down from the top with opacity.
    static var toolbarReveal: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }
}
