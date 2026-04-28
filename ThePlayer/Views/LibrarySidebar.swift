import SwiftUI

struct LibrarySidebar: View {
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry) -> Void
    let onSetlistSongSelect: (SongEntry, UUID, Int) -> Void
    let onReanalyze: (SongEntry) -> Void
    let currentSongPath: String?  // file path of currently loaded song

    @State private var newSetlistName = ""
    @State private var isAddingSetlist = false
    @State private var newPlaylistName = ""
    @State private var isAddingPlaylist = false
    @State private var renamingSetlistId: UUID?
    @State private var renamingPlaylistId: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                // Recent
                Section {
                    let recent = libraryService.library.recentSongs()
                    if recent.isEmpty {
                        Text("No recent songs")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recent) { song in
                            SongRow(song: song, libraryService: libraryService, onSelect: { onSongSelect(song) }, onReanalyze: { onReanalyze(song) })
                        }
                    }
                } header: {
                    Text("Recent")
                }

                // Setlists
                Section {
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

                    if isAddingSetlist {
                        HStack {
                            TextField("Setlist name", text: $newSetlistName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { submitNewSetlist() }
                            Button("Add", action: submitNewSetlist)
                                .font(.caption)
                            Button("Cancel") { isAddingSetlist = false; newSetlistName = "" }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(action: { isAddingSetlist = true }) {
                            Label("New Setlist", systemImage: "plus")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Setlists")
                }

                // Playlists
                Section {
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

                    if isAddingPlaylist {
                        HStack {
                            TextField("Playlist name", text: $newPlaylistName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { submitNewPlaylist() }
                            Button("Add", action: submitNewPlaylist)
                                .font(.caption)
                            Button("Cancel") { isAddingPlaylist = false; newPlaylistName = "" }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(action: { isAddingPlaylist = true }) {
                            Label("New Playlist", systemImage: "plus")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Playlists")
                }

                // Smart
                Section {
                    NavigationLink(value: SetlistDestination.smart(.mostPracticed)) {
                        Label("Most Practiced", systemImage: "star.fill")
                    }
                    NavigationLink(value: SetlistDestination.smart(.needsWork)) {
                        Label("Needs Work", systemImage: "exclamationmark.triangle")
                    }
                } header: {
                    Text("Smart")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Library")
            .navigationDestination(for: SetlistDestination.self) { destination in
                destinationView(for: destination)
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
        case .smart(let kind):
            SmartPlaylistView(
                kind: kind,
                libraryService: libraryService,
                onSongSelect: onSongSelect,
                onReanalyze: onReanalyze
            )
        }
    }

    // MARK: - Helpers

    private func submitNewSetlist() {
        let name = newSetlistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        libraryService.createSetlist(name: name)
        newSetlistName = ""
        isAddingSetlist = false
    }

    private func submitNewPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        libraryService.createPlaylist(name: name)
        newPlaylistName = ""
        isAddingPlaylist = false
    }
}

// MARK: - Navigation Model

private enum SetlistDestination: Hashable {
    case setlist(Setlist)
    case playlist(Playlist)
    case smart(SmartKind)

    enum SmartKind: Hashable {
        case mostPracticed
        case needsWork
    }
}

// MARK: - Song Row

private struct SongRow: View {
    let song: SongEntry
    let libraryService: LibraryService
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
                        Spacer()
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

    var body: some View {
        List {
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
        .navigationTitle(setlist.name)
    }
}

// MARK: - Playlist Detail

private struct PlaylistDetailView: View {
    let playlist: Playlist
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry) -> Void
    let onReanalyze: (SongEntry) -> Void
    var currentSongPath: String?

    var body: some View {
        List {
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
        .navigationTitle(playlist.name)
    }
}

// MARK: - Smart Playlist

private struct SmartPlaylistView: View {
    let kind: SetlistDestination.SmartKind
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry) -> Void
    let onReanalyze: (SongEntry) -> Void

    var body: some View {
        List {
            let songs: [SongEntry] = switch kind {
            case .mostPracticed: libraryService.library.mostPracticed()
            case .needsWork: libraryService.library.needsWork()
            }

            if songs.isEmpty {
                Text("No songs yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(songs) { song in
                    SongRow(song: song, libraryService: libraryService, onSelect: { onSongSelect(song) }, onReanalyze: { onReanalyze(song) })
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(kind == .mostPracticed ? "Most Practiced" : "Needs Work")
    }
}
