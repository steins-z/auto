import SwiftUI
import AppKit

struct PreviewView: View {
    let image: CGImage
    let onCopy: () -> Void
    let onSave: () -> Void
    let onAnnotate: () -> Void
    let onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Image(decorative: image, scale: 1.0)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .background(checkerBackground)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: { onCopy(); flashCopied() }) {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            Button(action: onAnnotate) {
                Label("Annotate", systemImage: "pencil.tip.crop.circle")
            }
            .disabled(true)
            .help("Annotation coming soon")

            Spacer()

            Text("\(image.width) × \(image.height)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var checkerBackground: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            let cols = Int(ceil(size.width / s))
            let rows = Int(ceil(size.height / s))
            for r in 0..<rows {
                for c in 0..<cols {
                    let dark = (r + c) % 2 == 0
                    let rect = CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s, height: s)
                    ctx.fill(Path(rect), with: .color(dark ? .gray.opacity(0.15) : .gray.opacity(0.05)))
                }
            }
        }
    }

    private func flashCopied() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}
