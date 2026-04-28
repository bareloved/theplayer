import SwiftUI

/// A draggable vertical handle positioned at a section boundary.
/// `xPosition` is the current pixel x; the parent maps the reported
/// absolute target X back to time.
struct SectionBoundaryHandle: View {
    let xPosition: CGFloat
    let height: CGFloat
    let isHovered: Bool
    /// When true the handle does not respond to clicks/drags, so other
    /// gestures layered on the waveform (e.g. option-drag to create a new
    /// section) can fire without being intercepted by this handle.
    let isDisabled: Bool
    /// Reports the absolute target x position (in the parent's coordinate
    /// space) the boundary should snap to. Computed from the handle's
    /// position at drag-start plus the gesture's translation, so it stays
    /// stable across re-renders that update `xPosition`.
    let onDragChanged: (CGFloat) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    @State private var dragStartXPosition: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.white.opacity(isHovered ? 0.95 : 0.8))
            .frame(width: 3, height: height)
            .overlay(
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(radius: 2)
                    .offset(y: -height / 2 + 6)
            )
            .contentShape(Rectangle().size(width: 12, height: height))
            .offset(x: xPosition - 1.5)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartXPosition == nil {
                            dragStartXPosition = xPosition
                            onDragStarted()
                        }
                        let startX = dragStartXPosition ?? xPosition
                        onDragChanged(startX + value.translation.width)
                    }
                    .onEnded { _ in
                        dragStartXPosition = nil
                        onDragEnded()
                    }
            )
            .onHover { hovering in
                if hovering && !isDisabled { NSCursor.resizeLeftRight.set() }
            }
            .allowsHitTesting(!isDisabled)
    }
}
