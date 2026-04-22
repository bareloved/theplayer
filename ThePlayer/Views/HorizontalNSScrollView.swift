import AppKit
import SwiftUI

/// Horizontal `NSScrollView` host for SwiftUI content. Gives us:
///   - programmatic scroll (`setScrollOriginX`) for anchor-preserving zoom
///   - ⌘-scroll-wheel zoom hook (onCommandScroll)
/// The `content` closure is hosted via `NSHostingView` inside the documentView.
struct HorizontalNSScrollView<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let onCommandScroll: (CGFloat) -> Void
    let controller: ScrollController
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        // Force legacy (non-overlay) scrollers so the horizontal bar reserves
        // layout space at the bottom instead of floating over the waveform.
        scroll.scrollerStyle = .legacy
        scroll.onCommandScroll = onCommandScroll

        // Use a flipped clip view so the SwiftUI-hosted content (top-left origin)
        // anchors to the top-left of the visible area. Without this the doc view
        // either floats against the bottom (when shorter than the clip) or the
        // top gets cut off (when equal height) due to default bottom-up origin.
        let flippedClip = FlippedClipView()
        flippedClip.drawsBackground = false
        scroll.contentView = flippedClip

        let hosting = TiledHostingView(rootView: AnyView(content()))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(x: 0, y: 0, width: contentWidth, height: Self.docHeight(contentHeight))
        scroll.documentView = hosting

        controller.scrollView = scroll
        context.coordinator.hosting = hosting
        return scroll
    }

    func updateNSView(_ nsView: ZoomScrollView, context: Context) {
        nsView.onCommandScroll = onCommandScroll
        controller.scrollView = nsView
        if let hosting = context.coordinator.hosting as? TiledHostingView<AnyView> {
            hosting.rootView = AnyView(content())
            let newSize = NSSize(width: contentWidth, height: Self.docHeight(contentHeight))
            if hosting.frame.size != newSize {
                hosting.setFrameSize(newSize)
            }
        }
    }

    /// Reserve vertical room for the legacy horizontal scroller so the doc view
    /// fits inside the clip view with no overflow.
    private static func docHeight(_ containerHeight: CGFloat) -> CGFloat {
        let thickness = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        return max(0, containerHeight - thickness)
    }

    final class Coordinator {
        var hosting: NSView?
    }
}

/// NSClipView with a top-left origin, so SwiftUI-hosted flipped content anchors
/// to the top of the visible area instead of floating against the bottom.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// Exposed handle the SwiftUI view holds as `@StateObject` so it can push scroll-origin
/// changes to the underlying NSScrollView during a drag.
final class ScrollController: ObservableObject {
    weak var scrollView: NSScrollView?

    func setScrollOriginX(_ x: CGFloat) {
        guard let clip = scrollView?.contentView else { return }
        var origin = clip.bounds.origin
        origin.x = x
        clip.setBoundsOrigin(origin)
        scrollView?.reflectScrolledClipView(clip)
    }

    var scrollOriginX: CGFloat {
        scrollView?.contentView.bounds.origin.x ?? 0
    }
}

/// NSScrollView subclass that reports ⌘-scroll vertical deltas to a closure
/// (mirrors the previous `ScrollWheelHandler` behaviour).
final class ZoomScrollView: NSScrollView {
    var onCommandScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command)
            && abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            onCommandScroll?(event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
