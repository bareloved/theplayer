import XCTest
@testable import ThePlayer

final class LibraryServiceBulkDeleteTests: XCTestCase {
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

    func testDeleteSongsFromSetlist() {
        let s1 = service.addSong(filePath: "/a.mp3", title: "A", artist: "", bpm: 0, duration: 0)
        let s2 = service.addSong(filePath: "/b.mp3", title: "B", artist: "", bpm: 0, duration: 0)
        let s3 = service.addSong(filePath: "/c.mp3", title: "C", artist: "", bpm: 0, duration: 0)
        let set = service.createSetlist(name: "S")
        for s in [s1, s2, s3] { service.addSongToSetlist(songId: s.id, setlistId: set.id) }

        service.deleteSongsFromSetlist(setlistId: set.id, songIds: [s1.id, s3.id])
        let updated = service.library.setlists.first { $0.id == set.id }
        XCTAssertEqual(updated?.songIds, [s2.id])
        // Songs themselves still in library.
        XCTAssertEqual(service.library.songs.count, 3)
    }

    func testDeleteSongsFromPlaylist() {
        let s1 = service.addSong(filePath: "/a.mp3", title: "A", artist: "", bpm: 0, duration: 0)
        let s2 = service.addSong(filePath: "/b.mp3", title: "B", artist: "", bpm: 0, duration: 0)
        let p = service.createPlaylist(name: "P")
        service.addSongToPlaylist(songId: s1.id, playlistId: p.id)
        service.addSongToPlaylist(songId: s2.id, playlistId: p.id)

        service.deleteSongsFromPlaylist(playlistId: p.id, songIds: [s1.id])
        let updated = service.library.playlists.first { $0.id == p.id }
        XCTAssertEqual(updated?.songIds, [s2.id])
    }

    func testDeleteSetlists() {
        let a = service.createSetlist(name: "A")
        let b = service.createSetlist(name: "B")
        let c = service.createSetlist(name: "C")

        service.deleteSetlists(ids: [a.id, c.id])
        XCTAssertEqual(service.library.setlists.map(\.id), [b.id])
    }

    func testDeletePlaylists() {
        let a = service.createPlaylist(name: "A")
        let b = service.createPlaylist(name: "B")
        service.deletePlaylists(ids: [a.id])
        XCTAssertEqual(service.library.playlists.map(\.id), [b.id])
    }
}
