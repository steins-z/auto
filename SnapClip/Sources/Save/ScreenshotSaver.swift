import Foundation
import AppKit
import UniformTypeIdentifiers

enum ScreenshotSaverError: Error {
    case encodingFailed
    case noBitmap
}

enum ScreenshotSaver {
    static func defaultFilename(date: Date = Date(), format: ImageFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "SnapClip_\(formatter.string(from: date)).\(format.fileExtension)"
    }

    @discardableResult
    static func save(image: NSImage,
                     to directory: URL? = nil,
                     format: ImageFormat? = nil,
                     quality: Double? = nil) throws -> URL {
        let settings = SettingsManager.shared
        let dir = directory ?? settings.saveDirectory
        let fmt = format ?? settings.imageFormat
        let q = quality ?? settings.jpegQuality

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = defaultFilename(format: fmt)
        let url = dir.appendingPathComponent(filename)

        let data = try encode(image: image, format: fmt, quality: q)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func saveAs(image: NSImage,
                       suggestedDirectory: URL? = nil,
                       format: ImageFormat? = nil,
                       quality: Double? = nil,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        let settings = SettingsManager.shared
        let fmt = format ?? settings.imageFormat
        let q = quality ?? settings.jpegQuality

        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename(format: fmt)
        panel.directoryURL = suggestedDirectory ?? settings.saveDirectory
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
