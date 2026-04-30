import SwiftUI

struct LibrarySidebar: View {
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry) -> Void
    let onSetlistSongSelect: (SongEntry, UUID, Int) -> Void
    let onReanalyze: (SongEntry) -> Void
    let currentSongPath: String?  // file path of currently loaded song

    @State private var isAddingSetlist = false
    @State private var isAddingPlaylist = false
    @State private var renamingSetlistId: UUID?
    @State private var renamingPlaylistId: UUID?
    @State private var renameText = ""
    @State private var query: String = ""
    @AppStorage("librarySidebarSort") private var sortRaw: String = LibrarySortMode.recent.rawValue
    @AppStorage("librarySidebarSetlistsExpanded") private var setlistsExpanded: Bool = true
    @AppStorage("librarySidebarPlaylistsExpanded") private var playlistsExpanded: Bool = true
    @FocusState private var searchFocused: Bool

    private var sort: LibrarySortMode {
        LibrarySortMode(rawValue: sortRaw) ?? .recent
    }

    private var visibleSongs: [SongEntry] {
        let sorted = LibraryFiltering.sort(songs: libraryService.library.songs, by: sort)
        return LibraryFiltering.filter(songs: sorted, query: query)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Library")
                        .font(.title2.bold())
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Search library", text: $query)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                        if !query.isEmpty {
                            Button(action: { query = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    .listRowSeparator(.hidden)

                    Picker("Sort", selection: $sortRaw) {
                        Text("Recent").tag(LibrarySortMode.recent.rawValue)
                        Text("Alphabetical").tag(LibrarySortMode.alphabetical.rawValue)
                        Text("Recently added").tag(LibrarySortMode.recentlyAdded.rawValue)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .listRowSeparator(.hidden)
                }

                Section {
                    let songs = visibleSongs
                    if libraryService.library.songs.isEmpty {
                        Text("No songs yet. Drop a folder anywhere on the window, or use File ▸ Add Songs…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if songs.isEmpty {
                        Text("No songs match \"\(query)\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(songs) { song in
                            SongRow(
                                song: song,
                                libraryService: libraryService,
                                isCurrent: song.filePath == currentSongPath,
                                onSelect: { onSongSelect(song) },
                                onReanalyze: { onReanalyze(song) }
                            )
                        }
                    }
                } header: {
                    Text("\(visibleSongs.count) of \(libraryService.library.songs.count) songs")
                }

                Section(isExpanded: $setlistsExpanded) {
                    ForEach(libraryService.library.setlists) { setlist in
                        if renamingSetlistId == setlist.id {
                            TextField("Setlist name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty { libraryService.renameSetlist(id: setlist.id, name: trimmed) }
                                    renamingSetlistId = nil
                                }
                                .onExitCommand { renamingSetlistId = nil }
                        } else {
                            NavigationLink(value: SetlistDestination.setlist(setlist)) {
                                HStack {
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(.blue)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(setlist.name)
                                        Text("\(setlist.songIds.count) Items")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .contextMenu {
                                Button("Rename...") {
                                    renameText = setlist.name
                                    renamingSetlistId = setlist.id
                                }
                                Button("Delete", role: .destructive) {
                                    libraryService.deleteSetlist(id: setlist.id)
                                }
                            }
                        }
                    }

                    Button(action: { isAddingSetlist = true }) {
                        Label("New Setlist", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Setlists")
                }

                Section(isExpanded: $playlistsExpanded) {
                    ForEach(libraryService.library.playlists) { playlist in
                        if renamingPlaylistId == playlist.id {
                            TextField("Playlist name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty { libraryService.renamePlaylist(id: playlist.id, name: trimmed) }
                                    renamingPlaylistId = nil
                                }
                                .onExitCommand { renamingPlaylistId = nil }
                        } else {
                            NavigationLink(value: SetlistDestination.playlist(playlist)) {
                                HStack {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.purple)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                        Text("\(playlist.songIds.count) Items")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .contextMenu {
                                Button("Rename...") {
                                    renameText = playlist.name
                                    renamingPlaylistId = playlist.id
                                }
                                Button("Delete", role: .destructive) {
                                    libraryService.deletePlaylist(id: playlist.id)
                                }
                            }
                        }
                    }

                    Button(action: { isAddingPlaylist = true }) {
                        Label("New Playlist", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Playlists")
                }

            }
            .listStyle(.sidebar)
            .onReceive(NotificationCenter.default.publisher(for: .openLibraryPicker)) { _ in
                searchFocused = true
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

    // MARK: - Destination Views

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

// MARK: - Song Row

private struct SongRow: View {
    let song: SongEntry
    let libraryService: LibraryService
    var isCurrent: Bool = false
    let onSelect: () -> Void
    let onReanalyze: () -> Void

    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        Group {
            if isRenaming {
                TextField("Song name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            libraryService.renameSong(songId: song.id, title: trimmed)
                        }
                        isRenaming = false
                    }
                    .onExitCommand { isRenaming = false }
            } else {
                Button(action: onSelect) {
                    HStack {
                        Text(song.title.isEmpty ? "Unknown Title" : song.title)
                            .lineLimit(1)
                            .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
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
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button("Rename...") {
                renameText = song.title
                isRenaming = true
            }
            Button("Reanalyze") {
                onReanalyze()
            }
            .disabled(!song.fileExists)
            Divider()
            if !libraryService.library.setlists.isEmpty {
                Menu("Add to Setlist...") {
                    ForEach(libraryService.library.setlists) { setlist in
                        Button(setlist.name) {
                            libraryService.addSongToSetlist(songId: song.id, setlistId: setlist.id)
                        }
                    }
                }
            }
            if !libraryService.library.playlists.isEmpty {
                Menu("Add to Playlist...") {
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
        List {
            Section {
                HStack(spacing: 6) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(setlist.name)
                        .font(.title2.bold())
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Add current song button
            if let path = currentSongPath, let song = libraryService.library.songByPath(path) {
                if !setlist.songIds.contains(song.id) {
                    Button(action: {
                        libraryService.addSongToSetlist(songId: song.id, setlistId: setlist.id)
                    }) {
                        Label("Add \"\(song.title)\"", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            let songs = setlist.songIds.enumerated().compactMap { index, id -> (Int, SongEntry)? in
                guard let song = libraryService.library.song(byId: id) else { return nil }
                return (index, song)
            }

            ForEach(songs, id: \.1.id) { index, song in
                Button(action: {
                    libraryService.setActiveSetlist(setlist.id, startingAt: index)
                    onSongSelect(song, setlist.id, index)
                }) {
                    HStack {
                        Text(song.title.isEmpty ? "Unknown Title" : song.title)
                            .lineLimit(1)
                        Spacer()
                        if libraryService.activeSetlistId == setlist.id &&
                           libraryService.activeSetlistIndex == index {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.blue)
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
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
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
        List {
            Section {
                HStack(spacing: 6) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(playlist.name)
                        .font(.title2.bold())
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let path = currentSongPath, let song = libraryService.library.songByPath(path) {
                if !playlist.songIds.contains(song.id) {
                    Button(action: {
                        libraryService.addSongToPlaylist(songId: song.id, playlistId: playlist.id)
                    }) {
                        Label("Add \"\(song.title)\"", systemImage: "plus.circle.fill")
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                }
            }

            let songs = playlist.songIds.compactMap { libraryService.library.song(byId: $0) }
            ForEach(songs) { song in
                SongRow(song: song, libraryService: libraryService, onSelect: { onSongSelect(song) }, onReanalyze: { onReanalyze(song) })
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }
}

