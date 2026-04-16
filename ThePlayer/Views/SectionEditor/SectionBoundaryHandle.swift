import SwiftUI

/// A draggable vertical handle positioned at a section boundary.
/// `xPosition` is the current pixel x; the parent maps drag-translation back to time.
struct SectionBoundaryHandle: View {
    let xPosition: CGFloat
    let height: CGFloat
    let isHovered: Bool
    let onDragChanged: (CGFloat) -> Void  // delta in pixels from drag start
    let onDragEnded: () -> Void

    @State private var dragStartX: CGFloat?

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
                        if dragStartX == nil { dragStartX = value.startLocation.x }
                        let delta = value.location.x - (dragStartX ?? value.startLocation.x)
                        onDragChanged(delta)
                    }
                    .onEnded { _ in
                        dragStartX = nil
                        onDragEnded()
                    }
            )
            .onHover { _ in
                NSCursor.resizeLeftRight.set()
            }
    }
}
