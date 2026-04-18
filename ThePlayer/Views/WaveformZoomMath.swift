import CoreGraphics
import Foundation

enum WaveformZoomMath {
    static let minZoom: CGFloat = 1.0
    static let maxZoom: CGFloat = 20.0
    /// Exponential gain per pixel of vertical drag. Drag-down (positive translation.height)
    /// zooms in. `exp(100 * 0.005) ≈ 1.65x` per 100pt, which matches Ableton's feel.
    static let dragSensitivity: CGFloat = 0.005

    /// Height of the visible ruler band that hosts bar labels, beat ticks,
    /// the downbeat triangle, and the zoom-drag gesture.
    static let rulerHeight: CGFloat = 22

    /// Compute new zoom level from a drag translation, clamped to [minZoom, maxZoom].
    static func zoomFromDrag(startZoom: CGFloat, translationY: CGFloat) -> CGFloat {
        let raw = startZoom * exp(translationY * dragSensitivity)
        return min(max(raw, minZoom), maxZoom)
    }

    /// Horizontal scroll origin that keeps the content-space bar at `anchorFraction`
    /// under the viewport x `cursorXInViewport` after zooming to `newZoom`.
    /// Clamped to the valid scroll range [0, newTotal - geoWidth].
    static func scrollOriginForAnchor(
        anchorFraction: CGFloat,
        cursorXInViewport: CGFloat,
        geoWidth: CGFloat,
        newZoom: CGFloat
    ) -> CGFloat {
        let newTotal = geoWidth * newZoom
        let desired = anchorFraction * newTotal - cursorXInViewport
        let maxOrigin = max(0, newTotal - geoWidth)
        return min(max(desired, 0), maxOrigin)
    }
}
