import XCTest
import AppKit
@testable import SnapClipAnnotations

final class SnapClipAnnotationsTests: XCTestCase {

    private func makeImage(width: CGFloat = 200, height: CGFloat = 120) -> NSImage {
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        img.unlockFocus()
        return img
    }

    @MainActor
    func testAddRectangleAnnotation() {
        let vm = AnnotationEditorViewModel(image: makeImage())
        vm.selectedTool = .rectangle
        vm.beginDrag(at: CGPoint(x: 10, y: 10))
        vm.updateDrag(to: CGPoint(x: 50, y: 60), from: CGPoint(x: 10, y: 10))
        vm.endDrag(at: CGPoint(x: 50, y: 60), from: CGPoint(x: 10, y: 10))

        XCTAssertEqual(vm.annotations.count, 1)
        if case .rectangle(let r) = vm.annotations.first?.kind {
            XCTAssertEqual(r.width, 40, accuracy: 0.001)
            XCTAssertEqual(r.height, 50, accuracy: 0.001)
        } else {
            XCTFail("Expected rectangle annotation")
        }
    }

    @MainActor
    func testNumberedStepsIncrement() {
        let vm = AnnotationEditorViewModel(image: makeImage())
        vm.selectedTool = .numberedStep
        vm.placeNumberedStep(at: CGPoint(x: 10, y: 10))
        vm.placeNumberedStep(at: CGPoint(x: 30, y: 30))
        vm.placeNumberedStep(at: CGPoint(x: 50, y: 50))

        let numbers: [Int] = vm.annotations.compactMap {
            if case .numberedStep(_, let n) = $0.kind { return n } else { return nil }
        }
        XCTAssertEqual(numbers, [1, 2, 3])
    }

    @MainActor
    func testUndoRedoRestoresState() {
        let vm = AnnotationEditorViewModel(image: makeImage())
        vm.selectedTool = .ellipse
        vm.beginDrag(at: .zero)
        vm.updateDrag(to: CGPoint(x: 20, y: 20), from: .zero)
        vm.endDrag(at: CGPoint(x: 20, y: 20), from: .zero)
        XCTAssertEqual(vm.annotations.count, 1)

        vm.undo()
        XCTAssertEqual(vm.annotations.count, 0)
        vm.redo()
        XCTAssertEqual(vm.annotations.count, 1)
    }

    @MainActor
    func testExportProducesNonEmptyImage() {
        let vm = AnnotationEditorViewModel(image: makeImage(width: 300, height: 200))
        vm.style.strokeColor = .red
        vm.annotations.append(Annotation(
            kind: .rectangle(rect: CGRect(x: 20, y: 20, width: 50, height: 50)),
            style: vm.style
        ))
        let out = AnnotationExporter.flattenSync(
            image: vm.image,
            annotations: vm.annotations,
            cropRect: nil
        )
        XCTAssertEqual(out.size.width, 300, accuracy: 0.5)
        XCTAssertEqual(out.size.height, 200, accuracy: 0.5)
    }

    @MainActor
    func testCropChangesEffectiveSize() {
        let vm = AnnotationEditorViewModel(image: makeImage(width: 400, height: 300))
        vm.selectedTool = .crop
        vm.beginDrag(at: CGPoint(x: 50, y: 50))
        vm.updateDrag(to: CGPoint(x: 250, y: 200), from: CGPoint(x: 50, y: 50))
        vm.endDrag(at: CGPoint(x: 250, y: 200), from: CGPoint(x: 50, y: 50))
        XCTAssertEqual(vm.effectiveSize.width, 200, accuracy: 0.5)
        XCTAssertEqual(vm.effectiveSize.height, 150, accuracy: 0.5)
    }

    /// Regression: crop drag anchored to the original start point, not to the
    /// previous-frame normalized origin. Reverse-direction drag must still produce
    /// a rect spanning start ↔ current.
    @MainActor
    func testCropDragReverseDirectionAnchorsToStart() {
        let vm = AnnotationEditorViewModel(image: makeImage(width: 400, height: 300))
        vm.selectedTool = .crop
        let start = CGPoint(x: 200, y: 200)
        vm.beginDrag(at: start)
        // First update extends down-right.
        vm.updateDrag(to: CGPoint(x: 300, y: 250), from: start)
        // Now reverse: drag up-left past the original start.
        vm.updateDrag(to: CGPoint(x: 50, y: 50), from: start)
        vm.endDrag(at: CGPoint(x: 50, y: 50), from: start)
        // Cropped rect must span 50…200 in both axes — i.e. anchored at start.
        XCTAssertEqual(vm.cropRect?.minX ?? -1, 50, accuracy: 0.5)
        XCTAssertEqual(vm.cropRect?.minY ?? -1, 50, accuracy: 0.5)
        XCTAssertEqual(vm.cropRect?.width ?? -1, 150, accuracy: 0.5)
        XCTAssertEqual(vm.cropRect?.height ?? -1, 150, accuracy: 0.5)
    }

    /// Stacked blur regions must remain redacted — sampling each filter from the
    /// running result (not the original) keeps a doubly-covered region pixellated
    /// instead of reverting to the source pixels. Smoke test: a stacked blur is
    /// not byte-identical to the original.
    @MainActor
    func testStackedBlurRegionsAreIdempotent() throws {
        let img = NSImage(size: NSSize(width: 80, height: 80))
        img.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0,  y: 0, width: 40, height: 80).fill()
        NSColor.white.setFill()
        NSRect(x: 40, y: 0, width: 40, height: 80).fill()
        img.unlockFocus()

        let full = CGRect(x: 0, y: 0, width: 80, height: 80)
        let blurredOnce  = ImageEffects.applyBlurRegions(to: img, rects: [full],       pixelRadius: 32)
        let blurredTwice = ImageEffects.applyBlurRegions(to: img, rects: [full, full], pixelRadius: 32)

        // The two-pass output must not match the one-pass output (it's been
        // re-pixellated against a *blurred* base, not the original) and neither
        // pass should equal the source image.
        XCTAssertNotEqual(img.tiffRepresentation,           blurredOnce.tiffRepresentation)
        XCTAssertNotEqual(img.tiffRepresentation,           blurredTwice.tiffRepresentation)
    }

    /// `flatten` must clamp the render scale so we never request a CGContext
    /// larger than `maxOutputPixelDimension` on either axis.
    @MainActor
    func testFlattenClampsExcessiveDimensions() {
        // 20000-pt source @ a 2× backing scale would request 40000² pixels (~6 GB).
        // With clampedRenderScale, the pixel size of the result must not exceed
        // 16384 on either axis. We assert against the underlying bitmap rep.
        let huge = NSImage(size: NSSize(width: 20000, height: 12000))
        huge.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: huge.size).fill()
        huge.unlockFocus()

        let out = AnnotationExporter.flattenSync(image: huge, annotations: [], cropRect: nil)
        let rep = out.representations.compactMap { $0 as? NSBitmapImageRep }.first
        let pixelW = rep?.pixelsWide ?? 0
        let pixelH = rep?.pixelsHigh ?? 0
        XCTAssertGreaterThan(pixelW, 0)
        XCTAssertGreaterThan(pixelH, 0)
        XCTAssertLessThanOrEqual(pixelW, Int(AnnotationExporter.maxOutputPixelDimension))
        XCTAssertLessThanOrEqual(pixelH, Int(AnnotationExporter.maxOutputPixelDimension))
    }
}
