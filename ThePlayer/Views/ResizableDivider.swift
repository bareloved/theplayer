import SwiftUI

/// A draggable divider that resizes an adjacent panel, like Finder's sidebar edge.
struct ResizableDivider: View {
    @Binding var dimension: Double
    let minSize: Double
    let maxSize: Double
    var isLeading: Bool = true  // true = divider is on the right edge of left panel
    /// Pixels reserved at the top so the visible separator line doesn't run up
    /// into the window toolbar/title area.
    var topInset: CGFloat = 60

    @State private var isDragging = false
    @State private var startDimension: Double = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.3) : Color.clear)
            .frame(width: 6)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Spacer().frame(height: topInset)
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startDimension = dimension
                        }
                        let delta = Double(isLeading ? value.translation.width : -value.translation.width)
                        dimension = min(max(startDimension + delta, minSize), maxSize)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
