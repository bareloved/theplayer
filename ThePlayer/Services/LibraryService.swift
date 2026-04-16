import Foundation
import Observation

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

    func relocateSong(songId: UUID, newPath: String) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].filePath = newPath
        save()
    }

    // MARK: - Setlists

    @discardableResult
    func createSetlist(name: String) -> Setlist {
        let setlist = Setlist(name: name)
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
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
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
}
