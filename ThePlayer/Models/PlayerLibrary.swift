import Foundation

struct PlayerLibrary: Codable {
    var songs: [SongEntry] = []
    var setlists: [Setlist] = []
    var playlists: [Playlist] = []

    func song(byId id: UUID) -> SongEntry? {
        songs.first(where: { $0.id == id })
    }

    func songIndex(byId id: UUID) -> Int? {
        songs.firstIndex(where: { $0.id == id })
    }

    func songByPath(_ path: String) -> SongEntry? {
        songs.first(where: { $0.filePath == path })
    }

    func recentSongs(limit: Int = 20) -> [SongEntry] {
        songs
            .filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    func mostPracticed(limit: Int = 10) -> [SongEntry] {
        songs
            .sorted { $0.practiceCount > $1.practiceCount }
            .prefix(limit)
            .map { $0 }
    }

    func needsWork(threshold: Int = 3) -> [SongEntry] {
        songs.filter { $0.practiceCount < threshold }
    }
}
