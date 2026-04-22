import AppKit
import SwiftUI

/// NSHostingView subclass whose backing layer is a `CATiledLayer`, removing the
/// ~16384pt width cap that a standard CALayer imposes via GPU texture limits.
/// Used by `HorizontalNSScrollView` so the waveform can scroll/zoom past x9
/// on typical viewports.
final class TiledHostingView<Content: View>: NSHostingView<Content> {
    override func makeBackingLayer() -> CALayer {
        let layer = CATiledLayer()
        layer.tileSize = CGSize(width: 512, height: 512)
        layer.levelsOfDetail = 1
        layer.levelsOfDetailBias = 0
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scale = window?.backingScaleFactor {
            layer?.contentsScale = scale
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor {
            layer?.contentsScale = scale
        }
    }
}
