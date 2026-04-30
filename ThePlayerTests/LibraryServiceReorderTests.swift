import XCTest
@testable import ThePlayer

final class LibraryServiceReorderTests: XCTestCase {
    var service: LibraryService!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = LibraryService(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: Setlist contents

    func testReorderSetlist() {
        let s1 = service.addSong(filePath: "/a.mp3", title: "A", artist: "", bpm: 0, duration: 0)
        let s2 = service.addSong(filePath: "/b.mp3", title: "B", artist: "", bpm: 0, duration: 0)
        let s3 = service.addSong(filePath: "/c.mp3", title: "C", artist: "", bpm: 0, duration: 0)
        let setlist = service.createSetlist(name: "Set")
        service.addSongToSetlist(songId: s1.id, setlistId: setlist.id)
        service.addSongToSetlist(songId: s2.id, setlistId: setlist.id)
        service.addSongToSetlist(songId: s3.id, setlistId: setlist.id)

        service.reorderSetlist(setlistId: setlist.id, songIds: [s3.id, s1.id, s2.id])
        let updated = service.library.setlists.first { $0.id == setlist.id }
        XCTAssertEqual(updated?.songIds, [s3.id, s1.id, s2.id])
    }

    // MARK: Playlist contents

    func testReorderPlaylist() {
        let s1 = service.addSong(filePath: "/a.mp3", title: "A", artist: "", bpm: 0, duration: 0)
        let s2 = service.addSong(filePath: "/b.mp3", title: "B", artist: "", bpm: 0, duration: 0)
        let playlist = service.createPlaylist(name: "P")
        service.addSongToPlaylist(songId: s1.id, playlistId: playlist.id)
        service.addSongToPlaylist(songId: s2.id, playlistId: playlist.id)

        service.reorderPlaylist(playlistId: playlist.id, songIds: [s2.id, s1.id])
        let updated = service.library.playlists.first { $0.id == playlist.id }
        XCTAssertEqual(updated?.songIds, [s2.id, s1.id])
    }

    // MARK: Sidebar order

    func testReorderSetlists() {
        let a = service.createSetlist(name: "A")
        let b = service.createSetlist(name: "B")
        let c = service.createSetlist(name: "C")

        service.reorderSetlists([c.id, a.id, b.id])
        XCTAssertEqual(service.library.setlists.map(\.id), [c.id, a.id, b.id])
    }

    func testReorderSetlistsIgnoresUnknownIds() {
        let a = service.createSetlist(name: "A")
        let b = service.createSetlist(name: "B")
        let bogus = UUID()
        service.reorderSetlists([bogus, b.id, a.id])
        // Unknown ids dropped; existing kept in the requested order.
        XCTAssertEqual(service.library.setlists.map(\.id), [b.id, a.id])
    }

    func testReorderPlaylists() {
        let a = service.createPlaylist(name: "A")
        let b = service.createPlaylist(name: "B")
        service.reorderPlaylists([b.id, a.id])
        XCTAssertEqual(service.library.playlists.map(\.id), [b.id, a.id])
    }
}
