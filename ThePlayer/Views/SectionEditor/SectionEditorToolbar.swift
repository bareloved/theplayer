import SwiftUI

struct SectionEditorToolbar: View {
    @Bindable var viewModel: SectionsViewModel
    let canDelete: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                Label("Add", systemImage: "plus")
            }
            Button(action: onDelete) {
                Label("Delete", systemImage: "minus")
            }
            .disabled(!canDelete)

            Divider().frame(height: 16)

            Button(action: { viewModel.undoManager.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.undoManager.canUndo)
            .help("Undo")

            Button(action: { viewModel.undoManager.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.undoManager.canRedo)
            .help("Redo")

            Divider().frame(height: 16)

            Button(action: onReset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .help("Revert all section edits to analyzer output")

            Spacer()

            Button(action: onDone) {
                Label("Done", systemImage: "checkmark")
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
