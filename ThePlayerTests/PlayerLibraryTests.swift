import XCTest
@testable import ThePlayer

final class PlayerLibraryTests: XCTestCase {
    func testLibraryCodableRoundTrip() throws {
        var library = PlayerLibrary()
        let song = SongEntry(filePath: "/test.mp3", title: "Song", artist: "Artist", bpm: 90, duration: 200)
        library.songs.append(song)
        let setlist = Setlist(name: "Gig", songIds: [song.id])
        library.setlists.append(setlist)
        let playlist = Playlist(name: "Practice", songIds: [song.id])
        library.playlists.append(playlist)

        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(PlayerLibrary.self, from: data)
        XCTAssertEqual(decoded.songs.count, 1)
        XCTAssertEqual(decoded.setlists.count, 1)
        XCTAssertEqual(decoded.setlists[0].name, "Gig")
        XCTAssertEqual(decoded.playlists.count, 1)
    }

    func testSmartPlaylistRecent() {
        var library = PlayerLibrary()
        for i in 0..<25 {
            var song = SongEntry(filePath: "/song\(i).mp3", title: "Song \(i)", artist: "", bpm: 0, duration: 0)
            song.lastOpenedAt = Date().addingTimeInterval(Double(-i) * 3600)
            library.songs.append(song)
        }
        let recent = library.recentSongs(limit: 20)
        XCTAssertEqual(recent.count, 20)
        XCTAssertEqual(recent[0].title, "Song 0")
    }

    func testSmartPlaylistMostPracticed() {
        var library = PlayerLibrary()
        for i in 0..<15 {
            var song = SongEntry(filePath: "/song\(i).mp3", title: "Song \(i)", artist: "", bpm: 0, duration: 0)
            song.practiceCount = i
            library.songs.append(song)
        }
        let top = library.mostPracticed(limit: 10)
        XCTAssertEqual(top.count, 10)
        XCTAssertEqual(top[0].practiceCount, 14)
    }

    func testSmartPlaylistNeedsWork() {
        var library = PlayerLibrary()
        for i in 0..<5 {
            var song = SongEntry(filePath: "/song\(i).mp3", title: "Song \(i)", artist: "", bpm: 0, duration: 0)
            song.practiceCount = i
            library.songs.append(song)
        }
        let needsWork = library.needsWork(threshold: 3)
        XCTAssertEqual(needsWork.count, 3)
    }
}
