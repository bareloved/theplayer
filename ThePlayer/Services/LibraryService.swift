import AVFoundation
import Foundation
import Observation

struct LibraryImportResult: Equatable {
    var added: Int = 0
    var skippedDuplicate: Int = 0
    var failed: Int = 0
}

@Observable
final class LibraryService {
    private(set) var library: PlayerLibrary
    private let directory: URL
    private let filePath: URL

    var activeSetlistId: UUID?
    var activeSetlistIndex: Int = 0

    init(directory: URL? = nil) {
        let dir: URL
        if let directory {
            dir = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = appSupport.appendingPathComponent("The Player", isDirectory: true)
        }
        self.directory = dir
        self.filePath = dir.appendingPathComponent("library.json")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: filePath.path) {
            do {
                let data = try Data(contentsOf: filePath)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                library = try decoder.decode(PlayerLibrary.self, from: data)
            } catch {
                let backup = dir.appendingPathComponent("library.json.backup")
                try? FileManager.default.copyItem(at: filePath, to: backup)
                library = PlayerLibrary()
            }
        } else {
            library = PlayerLibrary()
        }
    }

    // MARK: - Songs

    @discardableResult
    func addSong(filePath: String, title: String, artist: String, bpm: Float, duration: Float) -> SongEntry {
        if let existing = library.songByPath(filePath) {
            return existing
        }
        let song = SongEntry(filePath: filePath, title: title, artist: artist, bpm: bpm, duration: duration)
        library.songs.append(song)
        save()
        return song
    }

    func savePracticeState(songId: UUID, speed: Float, pitch: Float, position: Float, loopStart: Float?, loopEnd: Float?) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].lastSpeed = speed
        library.songs[index].lastPitch = pitch
        library.songs[index].lastPosition = position
        library.songs[index].lastLoopStart = loopStart
        library.songs[index].lastLoopEnd = loopEnd
        library.songs[index].lastOpenedAt = Date()
        save()
    }

    func incrementPracticeCount(songId: UUID) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].practiceCount += 1
        library.songs[index].lastOpenedAt = Date()
        save()
    }

    func addPracticeTime(songId: UUID, seconds: Double) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].totalPracticeTime += seconds
    }

    func renameSong(songId: UUID, title: String) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].title = title
        save()
    }

    func deleteSong(songId: UUID) {
        library.songs.removeAll(where: { $0.id == songId })
        // Clean from all setlists and playlists
        for i in library.setlists.indices {
            library.setlists[i].songIds.removeAll(where: { $0 == songId })
        }
        for i in library.playlists.indices {
            library.playlists[i].songIds.removeAll(where: { $0 == songId })
        }
        save()
    }

    func relocateSong(songId: UUID, newPath: String) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].filePath = newPath
        save()
    }

    // MARK: - Setlists

    @discardableResult
    func createSetlist(name: String, description: String? = nil) -> Setlist {
        let setlist = Setlist(name: name, description: description)
        library.setlists.append(setlist)
        save()
        return setlist
    }

    func renameSetlist(id: UUID, name: String) {
        guard let index = library.setlists.firstIndex(where: { $0.id == id }) else { return }
        library.setlists[index].name = name
        library.setlists[index].updatedAt = Date()
        save()
    }

    func deleteSetlist(id: UUID) {
        library.setlists.removeAll(where: { $0.id == id })
        if activeSetlistId == id { activeSetlistId = nil }
        save()
    }

    func addSongToSetlist(songId: UUID, setlistId: UUID) {
        guard let index = library.setlists.firstIndex(where: { $0.id == setlistId }) else { return }
        if !library.setlists[index].songIds.contains(songId) {
            library.setlists[index].songIds.append(songId)
            library.setlists[index].updatedAt = Date()
            save()
        }
    }

    func removeSongFromSetlist(songId: UUID, setlistId: UUID) {
        guard let index = library.setlists.firstIndex(where: { $0.id == setlistId }) else { return }
        library.setlists[index].songIds.removeAll(where: { $0 == songId })
        library.setlists[index].updatedAt = Date()
        save()
    }

    func reorderSetlist(setlistId: UUID, songIds: [UUID]) {
        guard let index = library.setlists.firstIndex(where: { $0.id == setlistId }) else { return }
        library.setlists[index].songIds = songIds
        library.setlists[index].updatedAt = Date()
        save()
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(name: String, description: String? = nil) -> Playlist {
        let playlist = Playlist(name: name, description: description)
        library.playlists.append(playlist)
        save()
        return playlist
    }

    func renamePlaylist(id: UUID, name: String) {
        guard let index = library.playlists.firstIndex(where: { $0.id == id }) else { return }
        library.playlists[index].name = name
        library.playlists[index].updatedAt = Date()
        save()
    }

    func deletePlaylist(id: UUID) {
        library.playlists.removeAll(where: { $0.id == id })
        save()
    }

    func addSongToPlaylist(songId: UUID, playlistId: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if !library.playlists[index].songIds.contains(songId) {
            library.playlists[index].songIds.append(songId)
            library.playlists[index].updatedAt = Date()
            save()
        }
    }

    func removeSongFromPlaylist(songId: UUID, playlistId: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        library.playlists[index].songIds.removeAll(where: { $0 == songId })
        library.playlists[index].updatedAt = Date()
        save()
    }

    func reorderPlaylist(playlistId: UUID, songIds: [UUID]) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        library.playlists[index].songIds = songIds
        library.playlists[index].updatedAt = Date()
        save()
    }

    // MARK: - Bulk operations

    func reorderSetlists(_ orderedIds: [UUID]) {
        let byId = Dictionary(uniqueKeysWithValues: library.setlists.map { ($0.id, $0) })
        library.setlists = orderedIds.compactMap { byId[$0] }
        save()
    }

    func reorderPlaylists(_ orderedIds: [UUID]) {
        let byId = Dictionary(uniqueKeysWithValues: library.playlists.map { ($0.id, $0) })
        library.playlists = orderedIds.compactMap { byId[$0] }
        save()
    }

    func deleteSongsFromSetlist(setlistId: UUID, songIds: [UUID]) {
        guard let index = library.setlists.firstIndex(where: { $0.id == setlistId }) else { return }
        let toRemove = Set(songIds)
        library.setlists[index].songIds.removeAll { toRemove.contains($0) }
        library.setlists[index].updatedAt = Date()
        save()
    }

    func deleteSongsFromPlaylist(playlistId: UUID, songIds: [UUID]) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        let toRemove = Set(songIds)
        library.playlists[index].songIds.removeAll { toRemove.contains($0) }
        library.playlists[index].updatedAt = Date()
        save()
    }

    func deleteSetlists(ids: [UUID]) {
        let toRemove = Set(ids)
        library.setlists.removeAll { toRemove.contains($0.id) }
        if let active = activeSetlistId, toRemove.contains(active) { activeSetlistId = nil }
        save()
    }

    func deletePlaylists(ids: [UUID]) {
        let toRemove = Set(ids)
        library.playlists.removeAll { toRemove.contains($0.id) }
        save()
    }

    // MARK: - Folders

    @discardableResult
    func createSetlistFolder(name: String) -> LibraryFolder {
        let folder = LibraryFolder(name: name)
        library.setlistFolders.append(folder)
        save()
        return folder
    }

    @discardableResult
    func createPlaylistFolder(name: String) -> LibraryFolder {
        let folder = LibraryFolder(name: name)
        library.playlistFolders.append(folder)
        save()
        return folder
    }

    func renameSetlistFolder(id: UUID, name: String) {
        guard let index = library.setlistFolders.firstIndex(where: { $0.id == id }) else { return }
        library.setlistFolders[index].name = name
        save()
    }

    func renamePlaylistFolder(id: UUID, name: String) {
        guard let index = library.playlistFolders.firstIndex(where: { $0.id == id }) else { return }
        library.playlistFolders[index].name = name
        save()
    }

    /// Removes the folder; any setlists currently inside it move back to root
    /// (`folderId = nil`).
    func deleteSetlistFolder(id: UUID) {
        for i in library.setlists.indices where library.setlists[i].folderId == id {
            library.setlists[i].folderId = nil
        }
        library.setlistFolders.removeAll { $0.id == id }
        save()
    }

    func deletePlaylistFolder(id: UUID) {
        for i in library.playlists.indices where library.playlists[i].folderId == id {
            library.playlists[i].folderId = nil
        }
        library.playlistFolders.removeAll { $0.id == id }
        save()
    }

    func moveSetlist(id: UUID, toFolder folderId: UUID?) {
        guard let index = library.setlists.firstIndex(where: { $0.id == id }) else { return }
        library.setlists[index].folderId = folderId
        library.setlists[index].updatedAt = Date()
        save()
    }

    func movePlaylist(id: UUID, toFolder folderId: UUID?) {
        guard let index = library.playlists.firstIndex(where: { $0.id == id }) else { return }
        library.playlists[index].folderId = folderId
        library.playlists[index].updatedAt = Date()
        save()
    }

    // MARK: - Setlist Playback

    func nextSetlistSong() -> SongEntry? {
        guard let setlistId = activeSetlistId,
              let setlist = library.setlists.first(where: { $0.id == setlistId }) else { return nil }
        let nextIndex = activeSetlistIndex + 1
        guard nextIndex < setlist.songIds.count else { return nil }
        activeSetlistIndex = nextIndex
        let songId = setlist.songIds[nextIndex]
        return library.song(byId: songId)
    }

    func setActiveSetlist(_ setlistId: UUID, startingAt index: Int = 0) {
        activeSetlistId = setlistId
        activeSetlistIndex = index
    }

    func clearActiveSetlist() {
        activeSetlistId = nil
        activeSetlistIndex = 0
    }

    // MARK: - Persistence

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(library)
            try data.write(to: filePath, options: .atomic)
        } catch {
            print("LibraryService: save failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Batch import

    /// Batch-adds many files. Reads embedded metadata per file (falling back to
    /// the filename when missing), defers a single `save()` to the end. Existing
    /// path duplicates are counted, not re-added.
    func addSongs(urls: [URL]) async -> LibraryImportResult {
        var result = LibraryImportResult()
        for url in urls {
            if Task.isCancelled { break }
            if library.songByPath(url.path) != nil {
                result.skippedDuplicate += 1
                continue
            }
            let (title, artist) = await Self.readMetadata(url: url)
            let fallback = url.deletingPathExtension().lastPathComponent
            let song = SongEntry(
                filePath: url.path,
                title: title.isEmpty ? fallback : title,
                artist: artist,
                bpm: 0,
                duration: 0
            )
            library.songs.append(song)
            result.added += 1
        }
        save()
        return result
    }

    private static func readMetadata(url: URL) async -> (title: String, artist: String) {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return ("", "") }
        let title = (try? await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle)
            .first?.load(.stringValue)) ?? nil
        let artist = (try? await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist)
            .first?.load(.stringValue)) ?? nil
        return (title ?? "", artist ?? "")
    }
}
