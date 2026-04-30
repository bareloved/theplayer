import AppKit
import SwiftUI

struct LibraryPicker: View {
    @Bindable var libraryService: LibraryService
    let currentSongPath: String?
    let onOpen: (SongEntry) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""
    @AppStorage("libraryPickerSort") private var sortRaw: String = LibrarySortMode.recent.rawValue
    @State private var highlightedId: UUID?
    @State private var pendingDelete: SongEntry?
    @State private var renamingId: UUID?
    @State private var renameText: String = ""
    @FocusState private var searchFocused: Bool

    private var sort: LibrarySortMode {
        LibrarySortMode(rawValue: sortRaw) ?? .recent
    }

    private var visibleSongs: [SongEntry] {
        let sorted = LibraryFiltering.sort(songs: libraryService.library.songs, by: sort)
        return LibraryFiltering.filter(songs: sorted, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .background(KeyEventCatcher(
            onUp: { moveHighlight(by: -1) },
            onDown: { moveHighlight(by: 1) },
            onDelete: { askDeleteHighlighted() },
            onEscape: { onDismiss() },
            onReturn: { openHighlighted() }
        ))
        .onAppear { searchFocused = true; ensureHighlight() }
        .onChange(of: visibleSongs.map(\.id)) { _, _ in ensureHighlight() }
        .confirmationDialog(
            "Remove \(pendingDelete?.title ?? "") from library?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let song = pendingDelete { libraryService.deleteSong(songId: song.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The audio file on disk is not deleted.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search library", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { openHighlighted() }
            Picker("Sort", selection: $sortRaw) {
                Text("Recent").tag(LibrarySortMode.recent.rawValue)
                Text("Alphabetical").tag(LibrarySortMode.alphabetical.rawValue)
                Text("Recently added").tag(LibrarySortMode.recentlyAdded.rawValue)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(12)
    }

    private var list: some View {
        Group {
            if libraryService.library.songs.isEmpty {
                emptyState("No songs yet. Drop a folder anywhere on the window, or use File ▸ Add Songs…")
            } else if visibleSongs.isEmpty {
                emptyState("No songs match \"\(query)\".")
            } else {
                ScrollViewReader { proxy in
                    List(selection: $highlightedId) {
                        ForEach(visibleSongs) { song in
                            row(song)
                                .id(song.id)
                                .tag(song.id)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: highlightedId) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func row(_ song: SongEntry) -> some View {
        HStack {
            if renamingId == song.id {
                TextField("Title", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { libraryService.renameSong(songId: song.id, title: trimmed) }
                        renamingId = nil
                    }
                    .onExitCommand { renamingId = nil }
            } else {
                Text(song.title)
                    .foregroundStyle(song.fileExists ? .primary : .secondary)
                Spacer()
                if song.filePath == currentSongPath {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(song) }
        .onTapGesture { highlightedId = song.id }
        .contextMenu {
            Menu("Add to Setlist") {
                if libraryService.library.setlists.isEmpty {
                    Text("No setlists yet").foregroundStyle(.secondary)
                } else {
                    ForEach(libraryService.library.setlists) { setlist in
                        Button(setlist.name) {
                            libraryService.addSongToSetlist(songId: song.id, setlistId: setlist.id)
                        }
                    }
                }
            }
            Button("Rename…") {
                renameText = song.title
                renamingId = song.id
            }
            Divider()
            Button("Delete from Library", role: .destructive) { pendingDelete = song }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(visibleSongs.count) of \(libraryService.library.songs.count)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("↵ open · ⎋ close · ⌫ delete").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureHighlight() {
        if highlightedId == nil || !visibleSongs.contains(where: { $0.id == highlightedId }) {
            highlightedId = visibleSongs.first?.id
        }
    }

    private func moveHighlight(by delta: Int) {
        guard !visibleSongs.isEmpty else { return }
        let idx = visibleSongs.firstIndex(where: { $0.id == highlightedId }) ?? -1
        let next = max(0, min(visibleSongs.count - 1, idx + delta))
        highlightedId = visibleSongs[next].id
    }

    private func openHighlighted() {
        if let id = highlightedId, let song = visibleSongs.first(where: { $0.id == id }) {
            onOpen(song)
        }
    }

    private func askDeleteHighlighted() {
        if let id = highlightedId, let song = visibleSongs.first(where: { $0.id == id }) {
            pendingDelete = song
        }
    }
}

/// Minimal NSView bridge to capture ↑/↓/⌫/⎋/↵ while the search field has focus.
private struct KeyEventCatcher: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    var onDelete: () -> Void
    var onEscape: () -> Void
    var onReturn: () -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(self) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class CatcherView: NSView {
        let bindings: KeyEventCatcher
        var monitor: Any?
        init(_ bindings: KeyEventCatcher) {
            self.bindings = bindings
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, self.window === event.window else { return event }
                    switch event.keyCode {
                    case 126: self.bindings.onUp(); return nil       // up arrow
                    case 125: self.bindings.onDown(); return nil     // down arrow
                    case 51, 117: self.bindings.onDelete(); return nil // delete / forward delete
                    case 53: self.bindings.onEscape(); return nil    // escape
                    case 36, 76: self.bindings.onReturn(); return nil // return / numpad enter
                    default: return event
                    }
                }
            }
        }
    }
}
