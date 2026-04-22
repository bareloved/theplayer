import SwiftUI

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
                TextField("Label", text: $draft, onCommit: {
                    onCommitRename(draft)
                    isRenaming = false
                })
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .frame(minWidth: 60, maxWidth: 140)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.6), in: Capsule())
                .foregroundStyle(textColor)
                .onAppear {
                    draft = label
                    DispatchQueue.main.async { fieldFocused = true }
                }
                .onExitCommand { isRenaming = false }
            } else {
                Text(label.isEmpty ? "Untitled" : label)
                    .font(.caption).bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.6), in: Capsule())
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
}
