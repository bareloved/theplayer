import SwiftUI

struct NewCollectionSheet: View {
    enum Kind {
        case setlist
        case playlist

        var title: String {
            switch self {
            case .setlist: return "New Setlist"
            case .playlist: return "New Playlist"
            }
        }

        var titlePlaceholder: String {
            switch self {
            case .setlist: return "Setlist Title"
            case .playlist: return "Playlist Title"
            }
        }
    }

    let kind: Kind
    let onCreate: (_ name: String, _ description: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var description: String = ""
    @FocusState private var titleFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var canCreate: Bool { !trimmedName.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Text(kind.title)
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                TextField(kind.titlePlaceholder, text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .focused($titleFocused)
                    .onSubmit { if canCreate { submit() } }

                TextField("Description (Optional)", text: $description, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3, reservesSpace: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 380)
        .onAppear { titleFocused = true }
    }

    private func submit() {
        guard canCreate else { return }
        let desc = description.trimmingCharacters(in: .whitespaces)
        onCreate(trimmedName, desc.isEmpty ? nil : desc)
        dismiss()
    }
}
