import SwiftUI

/// The forScore-style "…" overflow button that opens a sort menu with
/// checkmarks. Used in the top-right of the library sidebar header.
struct LibrarySortMenu: View {
    @Binding var sortRaw: String

    var body: some View {
        Menu {
            Section("Sorting") {
                option(.recent, label: "Recent", systemImage: "clock")
                option(.alphabetical, label: "Alphabetical", systemImage: "textformat")
                option(.recentlyAdded, label: "Recently added", systemImage: "calendar.badge.plus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
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
