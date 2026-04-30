import SwiftUI

/// The forScore-style "…" overflow button that opens a sort menu with
/// checkmarks. Used in the top-right of the library sidebar header.
struct LibrarySortMenu: View {
    @Binding var sortRaw: String
    @Binding var showFolders: Bool

    var body: some View {
        Menu {
            Section("Sorting") {
                option(.recent, label: "Recent", systemImage: "clock")
                option(.alphabetical, label: "Alphabetical", systemImage: "textformat")
                option(.recentlyAdded, label: "Recently added", systemImage: "calendar.badge.plus")
            }
            Section("Grouping") {
                Button {
                    showFolders.toggle()
                } label: {
                    if showFolders {
                        Label("Show Folders", systemImage: "checkmark")
                    } else {
                        Label("Show Folders", systemImage: "folder")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.55), lineWidth: 1))
                .padding(6)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func option(_ mode: LibrarySortMode, label: String, systemImage: String) -> some View {
        Button {
            sortRaw = mode.rawValue
        } label: {
            if sortRaw == mode.rawValue {
                Label(label, systemImage: "checkmark")
            } else {
                Label(label, systemImage: systemImage)
            }
        }
    }
}
