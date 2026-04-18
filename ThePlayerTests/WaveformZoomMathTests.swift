import XCTest
@testable import ThePlayer

final class WaveformZoomMathTests: XCTestCase {
    func testZoomFromDragDownZoomsIn() {
        // Drag down (+translation.height) zooms in.
        let z = WaveformZoomMath.zoomFromDrag(startZoom: 2.0, translationY: 100)
        XCTAssertGreaterThan(z, 2.0)
    }

    func testZoomFromDragUpZoomsOut() {
        let z = WaveformZoomMath.zoomFromDrag(startZoom: 2.0, translationY: -100)
        XCTAssertLessThan(z, 2.0)
    }

    func testZoomFromDragIsExponentialAndSymmetric() {
        // +100 then -100 should return to (approximately) the starting zoom.
        let up = WaveformZoomMath.zoomFromDrag(startZoom: 4.0, translationY: 100)
        let back = WaveformZoomMath.zoomFromDrag(startZoom: up, translationY: -100)
        XCTAssertEqual(back, 4.0, accuracy: 0.0001)
    }

    func testZoomFromDragClampsLow() {
        let z = WaveformZoomMath.zoomFromDrag(startZoom: 1.0, translationY: -10000)
        XCTAssertEqual(z, 1.0, accuracy: 0.0001)
    }

    func testZoomFromDragClampsHigh() {
        let z = WaveformZoomMath.zoomFromDrag(startZoom: 20.0, translationY: 10000)
        XCTAssertEqual(z, 20.0, accuracy: 0.0001)
    }

    func testScrollOriginForAnchorKeepsCursorBarFixed() {
        // geoWidth=1000, startZoom=2 -> oldTotal=2000. Anchor at content x=800 => fraction=0.4.
        // Cursor is at viewport x=300 at mouse-down => scrollOriginX at start = 800 - 300 = 500.
        // After zoom to 4x: newTotal=4000, new anchor content x = 0.4*4000 = 1600.
        // To keep cursor x=300 on the same bar: newOriginX = 1600 - 300 = 1300.
        let origin = WaveformZoomMath.scrollOriginForAnchor(
            anchorFraction: 0.4,
            cursorXInViewport: 300,
            geoWidth: 1000,
            newZoom: 4.0
        )
        XCTAssertEqual(origin, 1300, accuracy: 0.0001)
    }

    func testScrollOriginForAnchorClampsToValidRange() {
        // newTotal=1000, viewport=1000 => max scroll = 0. Origin must clamp >= 0.
        let origin = WaveformZoomMath.scrollOriginForAnchor(
            anchorFraction: 0.0,
            cursorXInViewport: 500,
            geoWidth: 1000,
            newZoom: 1.0
        )
        XCTAssertEqual(origin, 0, accuracy: 0.0001)
    }

    func testScrollOriginForAnchorClampsToMax() {
        // newTotal=2000, viewport=1000 => max scroll = 1000. Extreme right anchor can't exceed.
        let origin = WaveformZoomMath.scrollOriginForAnchor(
            anchorFraction: 1.0,
            cursorXInViewport: 0,
            geoWidth: 1000,
            newZoom: 2.0
        )
        XCTAssertEqual(origin, 1000, accuracy: 0.0001)
    }
}
