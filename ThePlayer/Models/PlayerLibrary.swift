import Foundation

struct PlayerLibrary: Codable {
    var songs: [SongEntry] = []
    var setlists: [Setlist] = []
    var playlists: [Playlist] = []
    var setlistFolders: [LibraryFolder] = []
    var playlistFolders: [LibraryFolder] = []

    init(
        songs: [SongEntry] = [],
        setlists: [Setlist] = [],
        playlists: [Playlist] = [],
        setlistFolders: [LibraryFolder] = [],
        playlistFolders: [LibraryFolder] = []
    ) {
        self.songs = songs
        self.setlists = setlists
        self.playlists = playlists
        self.setlistFolders = setlistFolders
        self.playlistFolders = playlistFolders
    }

    private enum CodingKeys: String, CodingKey {
        case songs, setlists, playlists, setlistFolders, playlistFolders
    }

    /// Custom decoder so libraries written before folder support load cleanly:
    /// missing `setlistFolders`/`playlistFolders` keys default to empty arrays
    /// instead of throwing `keyNotFound`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.songs = try c.decodeIfPresent([SongEntry].self, forKey: .songs) ?? []
        self.setlists = try c.decodeIfPresent([Setlist].self, forKey: .setlists) ?? []
        self.playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        self.setlistFolders = try c.decodeIfPresent([LibraryFolder].self, forKey: .setlistFolders) ?? []
        self.playlistFolders = try c.decodeIfPresent([LibraryFolder].self, forKey: .playlistFolders) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(songs, forKey: .songs)
        try c.encode(setlists, forKey: .setlists)
        try c.encode(playlists, forKey: .playlists)
        try c.encode(setlistFolders, forKey: .setlistFolders)
        try c.encode(playlistFolders, forKey: .playlistFolders)
    }

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
