import AppKit
import SwiftUI

final class PreviewWindow: NSWindow {
    var onClose: (() -> Void)?
    private let image: CGImage

    init(image: CGImage) {
        self.image = image
        let maxSize = CGSize(width: 720, height: 540)
        let imgSize = CGSize(width: image.width, height: image.height)
        let scale = min(maxSize.width / imgSize.width, maxSize.height / imgSize.height, 1.0)
        let displaySize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale + 44)

        super.init(contentRect: NSRect(origin: .zero, size: displaySize),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        self.title = "SnapClip Preview"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.center()

        let host = NSHostingView(rootView: PreviewView(
            image: image,
            onCopy: { [weak self] in self?.copyToClipboard() },
            onSave: { [weak self] in self?.saveToFile() },
            onAnnotate: { /* placeholder */ },
            onClose: { [weak self] in self?.closePreview() }
        ))
        self.contentView = host
    }

    private func copyToClipboard() {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    private func saveToFile() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "SnapClip_\(formatter.string(from: Date())).png"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.write(url: url)
        }
    }

    private func write(url: URL) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private func closePreview() {
        self.orderOut(nil)
        onClose?()
    }
}
