import SwiftUI

extension View {
    /// Hover-driven tooltip that appears after a short delay (faster than the
    /// system `.help(...)` tooltip, which waits ~2 seconds). Supports newlines
    /// in the text — they render as separate lines.
    func fastTooltip(_ text: String) -> some View {
        modifier(FastTooltipModifier(text: text))
    }
}

private struct FastTooltipModifier: ViewModifier {
    let text: String
    @State private var isShown: Bool = false
    @State private var pendingShow: DispatchWorkItem?

    private static let hoverDelay: TimeInterval = 0.2

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isShown, arrowEdge: .top) {
                Text(text)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .padding(8)
            }
            .onHover { hovering in
                pendingShow?.cancel()
                if hovering {
                    let task = DispatchWorkItem { isShown = true }
                    pendingShow = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: task)
                } else {
                    isShown = false
                }
            }
    }
}
