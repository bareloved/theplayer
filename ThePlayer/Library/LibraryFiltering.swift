import Foundation

enum LibrarySortMode: String, CaseIterable, Codable {
    case recent
    case alphabetical
    case recentlyAdded
}

enum LibraryFiltering {
    /// Case-insensitive substring match on `title` and the filename portion of `filePath`
    /// (no directory path, no extension). Empty/whitespace query returns all.
    static func filter(songs: [SongEntry], query: String) -> [SongEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return songs }
        return songs.filter { song in
            if song.title.lowercased().contains(q) { return true }
            let filename = (song.filePath as NSString).lastPathComponent
            let stem = (filename as NSString).deletingPathExtension
            return stem.lowercased().contains(q)
        }
    }

    static func sort(songs: [SongEntry], by mode: LibrarySortMode) -> [SongEntry] {
        switch mode {
        case .alphabetical:
            return songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recentlyAdded:
            return songs.sorted { $0.addedAt > $1.addedAt }
        case .recent:
            return songs.sorted { a, b in
                switch (a.lastOpenedAt, b.lastOpenedAt) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return a.addedAt > b.addedAt
                }
            }
        }
    }
}
