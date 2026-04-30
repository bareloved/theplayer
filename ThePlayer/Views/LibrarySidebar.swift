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
    @AppStorage("librarySidebarShowFolders") private var showFolders: Bool = true

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
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    header
                    PullToRevealSearch(query: $query, scrollOffset: scrollOffset, pinned: $searchPinned)
                    scroll
                    if isEditing { editActionBar }
                }
                if !isEditing {
                    floatingNewFolderButton
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                }
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
            HStack(spacing: 4) {
                LibrarySortMenu(sortRaw: $sortRaw, showFolders: $showFolders)
                Button(action: { isEditing.toggle() }) {
                    Image(systemName: isEditing ? "checkmark" : "list.bullet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isEditing ? Color.accentColor : Color.primary)
                        .frame(width: 22, height: 22)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
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
                    Divider().padding(.horizontal, 16)
                }
            }
        }
    }

    private var setlistsSection: some View {
        collapsibleSection(title: "Setlists", isExpanded: $setlistsExpanded) {
            VStack(spacing: 0) {
                if showFolders {
                    ForEach(libraryService.library.setlistFolders) { folder in
                        FolderDisclosureRow(
                            folder: folder,
                            iconColor: .blue,
                            content: {
                                ForEach(libraryService.library.setlists.filter { $0.folderId == folder.id }) { setlist in
                                    setlistRow(setlist).padding(.leading, 24)
                                    Divider().padding(.horizontal, 16)
                                }
                            },
                            onRename: { libraryService.renameSetlistFolder(id: folder.id, name: $0) },
                            onDelete: { libraryService.deleteSetlistFolder(id: folder.id) }
                        )
                        Divider().padding(.horizontal, 16)
                    }
                    ForEach(libraryService.library.setlists.filter { $0.folderId == nil }) { setlist in
                        setlistRow(setlist)
                        Divider().padding(.horizontal, 16)
                    }
                } else {
                    ForEach(libraryService.library.setlists) { setlist in
                        setlistRow(setlist)
                        Divider().padding(.horizontal, 16)
                    }
                }
                if isEditing {
                    Button(action: { promptNewFolder(kind: .setlist) }) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
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
        }
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
        collapsibleSection(title: "Playlists", isExpanded: $playlistsExpanded) {
            VStack(spacing: 0) {
                if showFolders {
                    ForEach(libraryService.library.playlistFolders) { folder in
                        FolderDisclosureRow(
                            folder: folder,
                            iconColor: .purple,
                            content: {
                                ForEach(libraryService.library.playlists.filter { $0.folderId == folder.id }) { playlist in
                                    playlistRow(playlist).padding(.leading, 24)
                                    Divider().padding(.horizontal, 16)
                                }
                            },
                            onRename: { libraryService.renamePlaylistFolder(id: folder.id, name: $0) },
                            onDelete: { libraryService.deletePlaylistFolder(id: folder.id) }
                        )
                        Divider().padding(.horizontal, 16)
                    }
                    ForEach(libraryService.library.playlists.filter { $0.folderId == nil }) { playlist in
                        playlistRow(playlist)
                        Divider().padding(.horizontal, 16)
                    }
                } else {
                    ForEach(libraryService.library.playlists) { playlist in
                        playlistRow(playlist)
                        Divider().padding(.horizontal, 16)
                    }
                }
                if isEditing {
                    Button(action: { promptNewFolder(kind: .playlist) }) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
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
        }
    }

    private enum FolderKind { case setlist, playlist }

    private func promptNewFolder(kind: FolderKind) {
        let alert = NSAlert()
        alert.messageText = kind == .setlist ? "New setlist folder" : "New playlist folder"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "")
        field.placeholderString = "Folder name"
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            switch kind {
            case .setlist: libraryService.createSetlistFolder(name: trimmed)
            case .playlist: libraryService.createPlaylistFolder(name: trimmed)
            }
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
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func toggleSelection(of id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private var floatingNewFolderButton: some View {
        Menu {
            Button("New setlist folder") { promptNewFolder(kind: .setlist) }
            Button("New playlist folder") { promptNewFolder(kind: .playlist) }
        } label: {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.background.secondary, in: Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var editActionBar: some View {
        HStack(spacing: 14) {
            iconButton(systemName: "trash", tint: .red, badge: totalSelected) {
                if !selectedSetlistIds.isEmpty {
                    libraryService.deleteSetlists(ids: Array(selectedSetlistIds))
                    selectedSetlistIds.removeAll()
                }
                if !selectedPlaylistIds.isEmpty {
                    libraryService.deletePlaylists(ids: Array(selectedPlaylistIds))
                    selectedPlaylistIds.removeAll()
                }
            }
            .disabled(totalSelected == 0)
            .help(totalSelected == 0 ? "Delete" : "Delete \(totalSelected)")

            Menu {
                Button("Root (no folder)") { moveSelected(toFolder: nil) }
                if !libraryService.library.setlistFolders.isEmpty
                    || !libraryService.library.playlistFolders.isEmpty {
                    Divider()
                }
                ForEach(libraryService.library.setlistFolders) { folder in
                    Button(folder.name) { moveSelectedSetlists(toFolder: folder.id) }
                        .disabled(selectedSetlistIds.isEmpty)
                }
                ForEach(libraryService.library.playlistFolders) { folder in
                    Button(folder.name) { moveSelectedPlaylists(toFolder: folder.id) }
                        .disabled(selectedPlaylistIds.isEmpty)
                }
            } label: {
                iconLabel(systemName: "folder", tint: .primary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(totalSelected == 0)
            .help("Move to folder")

            Spacer()

            iconButton(systemName: "checkmark.circle.fill", tint: .accentColor, badge: 0) {
                isEditing = false
            }
            .keyboardShortcut(.escape, modifiers: [])
            .help("Done")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    private func iconLabel(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconButton(systemName: String, tint: Color, badge: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                iconLabel(systemName: systemName, tint: tint)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func moveSelected(toFolder folderId: UUID?) {
        moveSelectedSetlists(toFolder: folderId)
        moveSelectedPlaylists(toFolder: folderId)
    }

    private func moveSelectedSetlists(toFolder folderId: UUID?) {
        for id in selectedSetlistIds {
            libraryService.moveSetlist(id: id, toFolder: folderId)
        }
        selectedSetlistIds.removeAll()
    }

    private func moveSelectedPlaylists(toFolder folderId: UUID?) {
        for id in selectedPlaylistIds {
            libraryService.movePlaylist(id: id, toFolder: folderId)
        }
        selectedPlaylistIds.removeAll()
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

    /// Custom collapsible section: chevron sits on the right of the title and
    /// rotates when expanded. Avoids the default DisclosureGroup chevron that
    /// hangs off the leading edge.
    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded.wrappedValue {
                content()
            }
        }
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

/// A folder row that remembers its expanded/collapsed state per-folder UUID
/// in `UserDefaults`.
struct FolderDisclosureRow<Content: View>: View {
    let folder: LibraryFolder
    let iconColor: Color
    @ViewBuilder let content: () -> Content
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isExpanded: Bool = true

    private var key: String { "libraryFolderExpanded.\(folder.id.uuidString)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(iconColor)
                        .frame(width: 32, alignment: .center)
                    Text(folder.name).font(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rename Folder…") { promptRename() }
                Button("Delete Folder", role: .destructive) { onDelete() }
            }
            if isExpanded {
                content()
            }
        }
        .onAppear {
            if let stored = UserDefaults.standard.object(forKey: key) as? Bool {
                isExpanded = stored
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    private func promptRename() {
        let alert = NSAlert()
        alert.messageText = "Rename folder"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: folder.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { onRename(trimmed) }
        }
    }
}

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
        .padding(.vertical, 12)
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
                        Divider().padding(.horizontal, 16)
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
                        Divider().padding(.horizontal, 16)
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
                        Divider().padding(.horizontal, 16)
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
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }
}
