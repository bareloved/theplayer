import SwiftUI

// MARK: - Scroll offset preference

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Sidebar

struct LibrarySidebar: View {
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry) -> Void
    let onSetlistSongSelect: (SongEntry, UUID, Int) -> Void
    let onReanalyze: (SongEntry) -> Void
    let currentSongPath: String?

    @State private var isAddingSetlist = false
    @State private var isAddingPlaylist = false
    @State private var query: String = ""
    @State private var searchPinned: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var isEditing: Bool = false
    @State private var selectedSetlistIds: Set<UUID> = []
    @State private var selectedPlaylistIds: Set<UUID> = []
    @AppStorage("librarySidebarSort") private var sortRaw: String = LibrarySortMode.recent.rawValue
    @AppStorage("librarySidebarSetlistsExpanded") private var setlistsExpanded: Bool = true
    @AppStorage("librarySidebarPlaylistsExpanded") private var playlistsExpanded: Bool = true

    private var sort: LibrarySortMode {
        LibrarySortMode(rawValue: sortRaw) ?? .recent
    }

    private var visibleSongs: [SongEntry] {
        let sorted = LibraryFiltering.sort(songs: libraryService.library.songs, by: sort)
        return LibraryFiltering.filter(songs: sorted, query: query)
    }

    private var totalSelected: Int { selectedSetlistIds.count + selectedPlaylistIds.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                PullToRevealSearch(query: $query, scrollOffset: scrollOffset, pinned: $searchPinned)
                scroll
                if isEditing { editActionBar }
            }
            .onChange(of: isEditing) { _, editing in
                if !editing {
                    selectedSetlistIds.removeAll()
                    selectedPlaylistIds.removeAll()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLibraryPicker)) { _ in
                searchPinned = true
            }
            .navigationDestination(for: SetlistDestination.self) { destination in
                destinationView(for: destination)
            }
            .sheet(isPresented: $isAddingSetlist) {
                NewCollectionSheet(kind: .setlist) { name, description in
                    libraryService.createSetlist(name: name, description: description)
                }
            }
            .sheet(isPresented: $isAddingPlaylist) {
                NewCollectionSheet(kind: .playlist) { name, description in
                    libraryService.createPlaylist(name: name, description: description)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Library").font(.largeTitle.bold())
            Spacer()
            HStack(spacing: 0) {
                LibrarySortMenu(sortRaw: $sortRaw)
                Divider().frame(height: 18)
                Button(action: { isEditing.toggle() }) {
                    Image(systemName: isEditing ? "checkmark" : "list.bullet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isEditing ? Color.accentColor : Color.primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .background(.background.secondary, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Scroll content

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("librarySidebarScroll")).minY)
                }
                .frame(height: 0)

                allSongsSection
                setlistsSection
                playlistsSection

                Color.clear.frame(height: 32)
            }
        }
        .coordinateSpace(name: "librarySidebarScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
        }
        .scrollContentBackground(.hidden)
    }

    private var allSongsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "\(visibleSongs.count) of \(libraryService.library.songs.count) songs")
            if libraryService.library.songs.isEmpty {
                emptyHint("No songs yet. Drop a folder anywhere on the window, or use File ▸ Add Songs…")
            } else if visibleSongs.isEmpty {
                emptyHint("No songs match \"\(query)\".")
            } else {
                ForEach(visibleSongs) { song in
                    SongItemRow(
                        song: song,
                        libraryService: libraryService,
                        isCurrent: song.filePath == currentSongPath,
                        onSelect: { onSongSelect(song) },
                        onReanalyze: { onReanalyze(song) }
                    )
                    Divider().padding(.leading, 56)
                }
            }
        }
    }

    private var setlistsSection: some View {
        DisclosureGroup(isExpanded: $setlistsExpanded) {
            VStack(spacing: 0) {
                ForEach(libraryService.library.setlists) { setlist in
                    setlistRow(setlist)
                    Divider().padding(.leading, 56)
                }
                if !isEditing {
                    Button(action: { isAddingSetlist = true }) {
                        Label("New Setlist", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            sectionHeader(title: "Setlists")
        }
        .padding(.horizontal, 0)
        .accentColor(.secondary)
    }

    @ViewBuilder
    private func setlistRow(_ setlist: Setlist) -> some View {
        if isEditing {
            Button {
                toggleSelection(of: setlist.id, in: &selectedSetlistIds)
            } label: {
                editableRow(
                    selected: selectedSetlistIds.contains(setlist.id),
                    iconSystemName: "music.note.list",
                    iconColor: .blue,
                    title: setlist.name,
                    subtitle: "\(setlist.songIds.count) Items"
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: SetlistDestination.setlist(setlist)) {
                LibraryItemRow(
                    iconSystemName: "music.note.list",
                    iconColor: .blue,
                    title: setlist.name,
                    subtitle: "\(setlist.songIds.count) Items"
                )
            }
            .buttonStyle(.plain)
            .contextMenu { setlistContextMenu(setlist) }
        }
    }

    private var playlistsSection: some View {
        DisclosureGroup(isExpanded: $playlistsExpanded) {
            VStack(spacing: 0) {
                ForEach(libraryService.library.playlists) { playlist in
                    playlistRow(playlist)
                    Divider().padding(.leading, 56)
                }
                if !isEditing {
                    Button(action: { isAddingPlaylist = true }) {
                        Label("New Playlist", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            sectionHeader(title: "Playlists")
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        if isEditing {
            Button {
                toggleSelection(of: playlist.id, in: &selectedPlaylistIds)
            } label: {
                editableRow(
                    selected: selectedPlaylistIds.contains(playlist.id),
                    iconSystemName: "music.note",
                    iconColor: .purple,
                    title: playlist.name,
                    subtitle: "\(playlist.songIds.count) Items"
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: SetlistDestination.playlist(playlist)) {
                LibraryItemRow(
                    iconSystemName: "music.note",
                    iconColor: .purple,
                    title: playlist.name,
                    subtitle: "\(playlist.songIds.count) Items"
                )
            }
            .buttonStyle(.plain)
            .contextMenu { playlistContextMenu(playlist) }
        }
    }

    private func editableRow(
        selected: Bool,
        iconSystemName: String,
        iconColor: Color,
        title: String,
        subtitle: String?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Image(systemName: iconSystemName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func toggleSelection(of id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private var editActionBar: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                if !selectedSetlistIds.isEmpty {
                    libraryService.deleteSetlists(ids: Array(selectedSetlistIds))
                    selectedSetlistIds.removeAll()
                }
                if !selectedPlaylistIds.isEmpty {
                    libraryService.deletePlaylists(ids: Array(selectedPlaylistIds))
                    selectedPlaylistIds.removeAll()
                }
            } label: {
                Text(totalSelected == 0 ? "Delete" : "Delete \(totalSelected)")
            }
            .disabled(totalSelected == 0)

            Spacer()

            Button("Done") { isEditing = false }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    // MARK: Helpers

    private func sectionHeader(title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func setlistContextMenu(_ setlist: Setlist) -> some View {
        Button("Rename…") { renameSetlistInline(setlist) }
        Button("Delete", role: .destructive) {
            libraryService.deleteSetlist(id: setlist.id)
        }
    }

    @ViewBuilder
    private func playlistContextMenu(_ playlist: Playlist) -> some View {
        Button("Rename…") { renamePlaylistInline(playlist) }
        Button("Delete", role: .destructive) {
            libraryService.deletePlaylist(id: playlist.id)
        }
    }

    private func renameSetlistInline(_ setlist: Setlist) {
        let alert = NSAlert()
        alert.messageText = "Rename setlist"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: setlist.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                libraryService.renameSetlist(id: setlist.id, name: trimmed)
            }
        }
    }

    private func renamePlaylistInline(_ playlist: Playlist) {
        let alert = NSAlert()
        alert.messageText = "Rename playlist"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: playlist.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                libraryService.renamePlaylist(id: playlist.id, name: trimmed)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: SetlistDestination) -> some View {
        switch destination {
        case .setlist(let setlist):
            SetlistDetailView(
                setlist: setlist,
                libraryService: libraryService,
                onSongSelect: onSetlistSongSelect,
                currentSongPath: currentSongPath
            )
        case .playlist(let playlist):
            PlaylistDetailView(
                playlist: playlist,
                libraryService: libraryService,
                onSongSelect: onSongSelect,
                onReanalyze: onReanalyze,
                currentSongPath: currentSongPath
            )
        }
    }
}

// MARK: - Navigation Model

private enum SetlistDestination: Hashable {
    case setlist(Setlist)
    case playlist(Playlist)
}

// MARK: - Reusable rows

/// Generic row used for setlists, playlists, and folders. forScore-style:
/// icon on the left, title + subtitle stacked, optional trailing chevron.
struct LibraryItemRow: View {
    let iconSystemName: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Song row used in the All Songs list AND inside setlist/playlist detail views.
struct SongItemRow: View {
    let song: SongEntry
    let libraryService: LibraryService
    var isCurrent: Bool = false
    let onSelect: () -> Void
    let onReanalyze: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title.isEmpty ? "Unknown Title" : song.title)
                        .font(.body)
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .font(.caption)
                }
                if !song.fileExists {
                    Text("Missing")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reanalyze") { onReanalyze() }.disabled(!song.fileExists)
            if !libraryService.library.setlists.isEmpty {
                Menu("Add to Setlist…") {
                    ForEach(libraryService.library.setlists) { setlist in
                        Button(setlist.name) {
                            libraryService.addSongToSetlist(songId: song.id, setlistId: setlist.id)
                        }
                    }
                }
            }
            if !libraryService.library.playlists.isEmpty {
                Menu("Add to Playlist…") {
                    ForEach(libraryService.library.playlists) { playlist in
                        Button(playlist.name) {
                            libraryService.addSongToPlaylist(songId: song.id, playlistId: playlist.id)
                        }
                    }
                }
            }
            Divider()
            Button("Remove from Library", role: .destructive) {
                libraryService.deleteSong(songId: song.id)
            }
        }
    }
}

// MARK: - Setlist Detail

private struct SetlistDetailView: View {
    let setlist: Setlist
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry, UUID, Int) -> Void
    var currentSongPath: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text(setlist.name).font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let path = currentSongPath, let song = libraryService.library.songByPath(path),
                       !setlist.songIds.contains(song.id) {
                        Button(action: {
                            libraryService.addSongToSetlist(songId: song.id, setlistId: setlist.id)
                        }) {
                            Label("Add \"\(song.title)\"", systemImage: "plus.circle.fill")
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 56)
                    }

                    let songs = setlist.songIds.enumerated().compactMap { index, id -> (Int, SongEntry)? in
                        guard let song = libraryService.library.song(byId: id) else { return nil }
                        return (index, song)
                    }
                    ForEach(songs, id: \.1.id) { index, song in
                        SongItemRow(
                            song: song,
                            libraryService: libraryService,
                            isCurrent: libraryService.activeSetlistId == setlist.id &&
                                       libraryService.activeSetlistIndex == index,
                            onSelect: {
                                libraryService.setActiveSetlist(setlist.id, startingAt: index)
                                onSongSelect(song, setlist.id, index)
                            },
                            onReanalyze: {}
                        )
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Playlist Detail

private struct PlaylistDetailView: View {
    let playlist: Playlist
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry) -> Void
    let onReanalyze: (SongEntry) -> Void
    var currentSongPath: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text(playlist.name).font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let path = currentSongPath, let song = libraryService.library.songByPath(path),
                       !playlist.songIds.contains(song.id) {
                        Button(action: {
                            libraryService.addSongToPlaylist(songId: song.id, playlistId: playlist.id)
                        }) {
                            Label("Add \"\(song.title)\"", systemImage: "plus.circle.fill")
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 56)
                    }

                    let songs = playlist.songIds.compactMap { libraryService.library.song(byId: $0) }
                    ForEach(songs) { song in
                        SongItemRow(
                            song: song,
                            libraryService: libraryService,
                            isCurrent: song.filePath == currentSongPath,
                            onSelect: { onSongSelect(song) },
                            onReanalyze: { onReanalyze(song) }
                        )
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }
}
