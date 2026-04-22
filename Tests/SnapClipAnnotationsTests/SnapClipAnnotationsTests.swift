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
}
