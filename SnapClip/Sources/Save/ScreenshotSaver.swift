import Foundation
import AppKit
import UniformTypeIdentifiers

enum ScreenshotSaverError: Error {
    case encodingFailed
    case noBitmap
}

@MainActor
enum ScreenshotSaver {
    static func defaultFilename(date: Date = Date(), format: ImageFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "SnapClip_\(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// Saves the image into the configured directory. Acquires security-scoped access for
    /// the directory before writing so this works under sandbox.
    @discardableResult
    static func save(image: NSImage,
                     format: ImageFormat? = nil,
                     quality: Double? = nil) throws -> URL {
        let settings = SettingsManager.shared
        let fmt = format ?? settings.imageFormat
        let q = quality ?? settings.jpegQuality
        let data = try encode(image: image, format: fmt, quality: q)
        let filename = defaultFilename(format: fmt)

        return try settings.withSaveDirectoryAccess { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    /// "Save As…" with the configured directory pre-filled. The save panel itself returns
    /// a security-scoped URL, so writing through it works regardless of the persisted bookmark.
    static func saveAs(image: NSImage,
                       format: ImageFormat? = nil,
                       quality: Double? = nil,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        let settings = SettingsManager.shared
        let fmt = format ?? settings.imageFormat
        let q = quality ?? settings.jpegQuality

        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename(format: fmt)
        panel.directoryURL = settings.saveDirectory
        if let type = UTType(filenameExtension: fmt.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(.failure(CocoaError(.userCancelled)))
                return
            }
            do {
                let data = try encode(image: image, format: fmt, quality: q)
                try data.write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func encode(image: NSImage, format: ImageFormat, quality: Double) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            throw ScreenshotSaverError.noBitmap
        }
        let properties: [NSBitmapImageRep.PropertyKey: Any]
        let type: NSBitmapImageRep.FileType
        switch format {
        case .png:
            type = .png
            properties = [:]
        case .jpeg:
            type = .jpeg
            properties = [.compressionFactor: max(0, min(1, quality))]
        }
        guard let data = rep.representation(using: type, properties: properties) else {
            throw ScreenshotSaverError.encodingFailed
        }
        return data
    }
}
