import SwiftUI

/// A search field that hides at the top of a scroll view and reveals itself
/// when the user pulls past the top. Once revealed it stays visible until the
/// user scrolls the list back to its natural top position.
///
/// Usage: place at the very top of a `VStack` inside a `ScrollView`, and pass
/// in the same `scrollOffset` that you read with a `GeometryReader` inside the
/// scroll content. See `LibrarySidebar.swift` for the wiring.
struct PullToRevealSearch: View {
    @Binding var query: String
    /// Vertical offset of the scroll content. > 0 means the user pulled down
    /// past the top.
    let scrollOffset: CGFloat
    /// External "pin open" signal — e.g. ⌘L. While true the field is fully
    /// visible regardless of scroll position.
    @Binding var pinned: Bool
    @FocusState private var focused: Bool

    /// Pull distance after which the field is fully revealed.
    private let revealThreshold: CGFloat = 60

    private var revealProgress: CGFloat {
        if pinned { return 1 }
        return min(1, max(0, scrollOffset / revealThreshold))
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body)
            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36 * revealProgress)
        .opacity(revealProgress)
        .clipped()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, revealProgress > 0 ? 6 : 0)
        .animation(.easeOut(duration: 0.15), value: revealProgress)
        .onChange(of: pinned) { _, newValue in
            focused = newValue
        }
        .onChange(of: scrollOffset) { _, offset in
            // Auto-unpin when the user scrolls the list back up past the top.
            if pinned && offset < -10 && query.isEmpty {
                pinned = false
                focused = false
            }
        }
    }
}
