import SwiftUI
import AppKit

struct SectionLabelBadge: View {
    let label: String
    let color: Color
    let isSelected: Bool
    @Binding var isRenaming: Bool
    let onCommitRename: (String) -> Void
    let onTap: () -> Void
    let contextMenuContent: () -> AnyView

    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                TextField("Label", text: $draft, onCommit: { commitAndExit() })
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .frame(minWidth: 60, maxWidth: 140)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color, in: Capsule())
                .background(ClickOutsideMonitor { commitAndExit() })
                .foregroundStyle(textColor)
                .onAppear {
                    draft = label
                    DispatchQueue.main.async { fieldFocused = true }
                }
                .onExitCommand { isRenaming = false }
                // Commit when focus leaves the field (tab, etc.).
                .onChange(of: fieldFocused) { _, nowFocused in
                    if !nowFocused { commitAndExit() }
                }
            } else {
                Text(label.isEmpty ? "Untitled" : label)
                    .font(.caption).bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color, in: Capsule())
                    .foregroundStyle(textColor)
                    .overlay(
                        Capsule().strokeBorder(color, lineWidth: isSelected ? 2 : 0)
                    )
                    .onTapGesture(count: 2) { isRenaming = true }
                    .onTapGesture(count: 1) { onTap() }
                    .contextMenu { contextMenuContent() }
            }
        }
    }

    private var textColor: Color {
        // Cheap contrast heuristic: dark text on light fills, white otherwise.
        switch color {
        case .yellow, .cyan: return .black
        default:             return .white
        }
    }

    private func commitAndExit() {
        guard isRenaming else { return }
        onCommitRename(draft)
        isRenaming = false
    }
}

/// Bridges AppKit mouse events into SwiftUI: invokes `onClickOutside` whenever
/// a left/right mouse-down lands outside this view's frame in the host window.
/// Needed because clicking non-focusable AppKit views (e.g. the waveform) does
/// not relinquish SwiftUI `@FocusState`, so the rename field stays focused.
private struct ClickOutsideMonitor: NSViewRepresentable {
    let onClickOutside: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onClickOutside = onClickOutside
        return v
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onClickOutside = onClickOutside
    }

    final class TrackingView: NSView {
        var onClickOutside: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let existing = monitor {
                NSEvent.removeMonitor(existing)
                monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let win = self.window, event.window === win else { return event }
                let frameInWindow = self.convert(self.bounds, to: nil)
                if !frameInWindow.contains(event.locationInWindow) {
                    DispatchQueue.main.async { self.onClickOutside?() }
                }
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
