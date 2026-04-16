import SwiftUI

struct LibrarySidebar: View {
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry) -> Void
    let onSetlistSongSelect: (SongEntry, UUID, Int) -> Void

    @State private var recentExpanded = true
    @State private var setlistsExpanded = true
    @State private var playlistsExpanded = true
    @State private var mostPracticedExpanded = false
    @State private var needsWorkExpanded = false

    @State private var newSetlistName = ""
    @State private var isAddingSetlist = false
    @State private var newPlaylistName = ""
    @State private var isAddingPlaylist = false

    @State private var setlistToAddTo: UUID?
    @State private var playlistToAddTo: UUID?

    var body: some View {
        List {
            // MARK: Recent Songs
            Section {
                DisclosureGroup(isExpanded: $recentExpanded) {
                    let recent = libraryService.library.recentSongs()
                    if recent.isEmpty {
                        Text("No recent songs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        ForEach(recent) { song in
                            SongRow(
                                song: song,
                                library: libraryService.library,
                                onSelect: { onSongSelect(song) },
                                onAddToSetlist: { id in libraryService.addSongToSetlist(songId: song.id, setlistId: id) },
                                onAddToPlaylist: { id in libraryService.addSongToPlaylist(songId: song.id, playlistId: id) },
                                onRelocate: { relocateSong(song) }
                            )
                        }
                    }
                } label: {
                    Label("Recent", systemImage: "clock")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // MARK: Setlists
            Section {
                DisclosureGroup(isExpanded: $setlistsExpanded) {
                    ForEach(libraryService.library.setlists) { setlist in
                        SetlistRow(
                            setlist: setlist,
                            library: libraryService.library,
                            libraryService: libraryService,
                            onSongSelect: { song, idx in onSetlistSongSelect(song, setlist.id, idx) }
                        )
                    }

                    if isAddingSetlist {
                        HStack {
                            TextField("Setlist name", text: $newSetlistName)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .onSubmit { submitNewSetlist() }
                            Button("Add", action: submitNewSetlist)
                                .font(.caption2)
                            Button("Cancel") { isAddingSetlist = false; newSetlistName = "" }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    } else {
                        Button(action: { isAddingSetlist = true }) {
                            Label("New Setlist", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Setlists", systemImage: "music.note.list")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // MARK: Playlists
            Section {
                DisclosureGroup(isExpanded: $playlistsExpanded) {
                    ForEach(libraryService.library.playlists) { playlist in
                        PlaylistRow(
                            playlist: playlist,
                            library: libraryService.library,
                            onSongSelect: onSongSelect
                        )
                    }

                    if isAddingPlaylist {
                        HStack {
                            TextField("Playlist name", text: $newPlaylistName)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .onSubmit { submitNewPlaylist() }
                            Button("Add", action: submitNewPlaylist)
                                .font(.caption2)
                            Button("Cancel") { isAddingPlaylist = false; newPlaylistName = "" }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    } else {
                        Button(action: { isAddingPlaylist = true }) {
                            Label("New Playlist", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Playlists", systemImage: "music.note")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // MARK: Smart Playlists
            Section {
                DisclosureGroup(isExpanded: $mostPracticedExpanded) {
                    let songs = libraryService.library.mostPracticed()
                    if songs.isEmpty {
                        Text("No songs yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        ForEach(songs) { song in
                            SongRow(
                                song: song,
                                library: libraryService.library,
                                onSelect: { onSongSelect(song) },
                                onAddToSetlist: { id in libraryService.addSongToSetlist(songId: song.id, setlistId: id) },
                                onAddToPlaylist: { id in libraryService.addSongToPlaylist(songId: song.id, playlistId: id) },
                                onRelocate: { relocateSong(song) }
                            )
                        }
                    }
                } label: {
                    Label("Most Practiced", systemImage: "star.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }

                DisclosureGroup(isExpanded: $needsWorkExpanded) {
                    let songs = libraryService.library.needsWork()
                    if songs.isEmpty {
                        Text("All caught up!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        ForEach(songs) { song in
                            SongRow(
                                song: song,
                                library: libraryService.library,
                                onSelect: { onSongSelect(song) },
                                onAddToSetlist: { id in libraryService.addSongToSetlist(songId: song.id, setlistId: id) },
                                onAddToPlaylist: { id in libraryService.addSongToPlaylist(songId: song.id, playlistId: id) },
                                onRelocate: { relocateSong(song) }
                            )
                        }
                    }
                } label: {
                    Label("Needs Work", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 220)
    }

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

    private func relocateSong(_ song: SongEntry) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav, .aiff, .mp3]
        panel.allowsMultipleSelection = false
        panel.message = "Locate \"\(song.title)\""
        if panel.runModal() == .OK, let url = panel.url {
            libraryService.relocateSong(songId: song.id, newPath: url.path)
        }
    }
}

// MARK: - SongRow

private struct SongRow: View {
    let song: SongEntry
    let library: PlayerLibrary
    let onSelect: () -> Void
    let onAddToSetlist: (UUID) -> Void
    let onAddToPlaylist: (UUID) -> Void
    let onRelocate: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title.isEmpty ? "Unknown Title" : song.title)
                        .font(.caption)
                        .lineLimit(1)
                    if !song.artist.isEmpty {
                        Text(song.artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !song.fileExists {
                    Text("Missing")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !library.setlists.isEmpty {
                Menu("Add to Setlist...") {
                    ForEach(library.setlists) { setlist in
                        Button(setlist.name) { onAddToSetlist(setlist.id) }
                    }
                }
            }

            if !library.playlists.isEmpty {
                Menu("Add to Playlist...") {
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) { onAddToPlaylist(playlist.id) }
                    }
                }
            }

            if !song.fileExists {
                Divider()
                Button("Relocate...") { onRelocate() }
            }
        }
    }
}

// MARK: - SetlistRow

private struct SetlistRow: View {
    let setlist: Setlist
    let library: PlayerLibrary
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry, Int) -> Void

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(Array(setlist.songIds.enumerated()), id: \.offset) { index, songId in
                if let song = library.song(byId: songId) {
                    Button(action: {
                        libraryService.setActiveSetlist(setlist.id, startingAt: index)
                        onSongSelect(song, index)
                    }) {
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .trailing)

                            if libraryService.activeSetlistId == setlist.id &&
                               libraryService.activeSetlistIndex == index {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title.isEmpty ? "Unknown Title" : song.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                if !song.artist.isEmpty {
                                    Text(song.artist)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if !song.fileExists {
                                Text("Missing")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            Text(setlist.name)
                .font(.caption)
        }
    }
}

// MARK: - PlaylistRow

private struct PlaylistRow: View {
    let playlist: Playlist
    let library: PlayerLibrary
    let onSongSelect: (SongEntry) -> Void

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(playlist.songIds, id: \.self) { songId in
                if let song = library.song(byId: songId) {
                    Button(action: { onSongSelect(song) }) {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title.isEmpty ? "Unknown Title" : song.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                if !song.artist.isEmpty {
                                    Text(song.artist)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if !song.fileExists {
                                Text("Missing")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            Text(playlist.name)
                .font(.caption)
        }
    }
}
