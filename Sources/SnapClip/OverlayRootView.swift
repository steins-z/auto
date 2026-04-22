import SwiftUI
import AppKit
import ScreenCaptureKit

struct OverlayRootView: View {
    let screenFrame: CGRect
    let display: SCDisplay
    let windows: [SCWindow]
    let onComplete: (CaptureRequest?) -> Void

    @State private var mode: CaptureMode = .region
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(mode == .fullScreen ? 0.3 : 0.25)
                .ignoresSafeArea()

            // Mode-specific content
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if mode == .region {
                        regionLayer(in: geo.size)
                    } else if mode == .window {
                        windowLayer(in: geo.size)
                    } else {
                        fullScreenLayer(in: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(in: geo.size))
                .onContinuousHover { phase in
                    if case let .active(loc) = phase { hoverPoint = loc }
                }
                .onTapGesture { loc in
                    handleClick(at: loc, size: geo.size)
                }
            }

            // Top hint bar
            VStack {
                hintBar
                    .padding(.top, 24)
                Spacer()
            }
        }
        .background(KeyHandlingView(onKey: handleKey))
    }

    private var hintBar: some View {
        HStack(spacing: 16) {
            ForEach(CaptureMode.allCases, id: \.self) { m in
                Text(m.label)
                    .font(.system(size: 13, weight: m == mode ? .semibold : .regular))
                    .foregroundColor(m == mode ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(m == mode ? Color.accentColor.opacity(0.6) : Color.clear)
                    )
            }
            Divider().frame(height: 16).overlay(Color.white.opacity(0.3))
            Text("Tab: switch  •  Esc: cancel")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: - Region

    private func regionLayer(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let rect = currentDragRect() {
                // Cut out the selected area by drawing a brighter rect overlay
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .background(Color.white.opacity(0.05))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)

                Text(dimensionText(for: rect))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    .offset(x: rect.minX, y: max(0, rect.minY - 22))
            }
        }
    }

    private func currentDragRect() -> CGRect? {
        guard let s = dragStart, let c = dragCurrent else { return nil }
        let r = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                       width: abs(c.x - s.x), height: abs(c.y - s.y))
        return r.width > 1 && r.height > 1 ? r : nil
    }

    private func dimensionText(for rect: CGRect) -> String {
        let scale = NSScreen.screens.first(where: { $0.frame == screenFrame })?.backingScaleFactor ?? 1
        let w = Int(rect.width * scale)
        let h = Int(rect.height * scale)
        return "\(w) × \(h) px"
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard mode == .region else { return }
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                guard mode == .region else { return }
                defer { dragStart = nil; dragCurrent = nil }
                guard let rect = currentDragRect() else { return }
                let req = makeRegionRequest(viewRect: rect, viewSize: size)
                onComplete(req)
            }
    }

    private func makeRegionRequest(viewRect: CGRect, viewSize: CGSize) -> CaptureRequest {
        // viewRect is in SwiftUI points (top-left origin, within this screen's view).
        // SCStreamConfiguration.sourceRect is in points within the display, top-left origin.
        // Since the overlay covers the screen 1:1, viewRect coords = display points already.
        return CaptureRequest(kind: .region(rect: viewRect, display: display))
    }

    // MARK: - Window

    private func windowLayer(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let win = windowUnderCursor(size: size) {
                let rect = viewRect(for: win, size: size)
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.1))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
    }

    private func windowUnderCursor(size: CGSize) -> SCWindow? {
        let p = hoverPoint
        // Convert hoverPoint (top-left view space) to global screen coordinates
        let global = CGPoint(x: screenFrame.minX + p.x,
                             y: screenFrame.maxY - p.y)
        // Windows are returned in z-order (front-most first in some APIs); pick first containing
        return windows.first(where: { $0.frame.contains(global) && $0.isOnScreen })
    }

    private func viewRect(for window: SCWindow, size: CGSize) -> CGRect {
        let f = window.frame
        // Convert from global to view coords
        let x = f.minX - screenFrame.minX
        let y = screenFrame.maxY - f.maxY
        return CGRect(x: x, y: y, width: f.width, height: f.height)
            .intersection(CGRect(origin: .zero, size: size))
    }

    private func handleClick(at loc: CGPoint, size: CGSize) {
        switch mode {
        case .window:
            if let win = windowUnderCursor(size: size) {
                onComplete(CaptureRequest(kind: .window(win)))
            }
        case .fullScreen:
            onComplete(CaptureRequest(kind: .fullScreen(display)))
        case .region:
            break
        }
    }

    // MARK: - Full screen

    private func fullScreenLayer(in size: CGSize) -> some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 3)
            .frame(width: size.width, height: size.height)
    }

    // MARK: - Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            onComplete(nil)
            return true
        case 48: // Tab
            cycleMode()
            return true
        case 36, 76: // Return
            if mode == .fullScreen {
                onComplete(CaptureRequest(kind: .fullScreen(display)))
                return true
            }
            return false
        default:
            return false
        }
    }

    private func cycleMode() {
        let all = CaptureMode.allCases
        if let i = all.firstIndex(of: mode) {
            mode = all[(i + 1) % all.count]
        }
    }
}

private struct KeyHandlingView: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.onKey = onKey
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onKey: ((NSEvent) -> Bool)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if onKey?(event) == true { return }
            super.keyDown(with: event)
        }
    }
}
