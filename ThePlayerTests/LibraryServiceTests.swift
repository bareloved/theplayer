import XCTest
@testable import ThePlayer

final class LibraryServiceTests: XCTestCase {
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

    func testAddSong() {
        let song = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        XCTAssertEqual(service.library.songs.count, 1)
        XCTAssertEqual(song.title, "Test")
    }

    func testAddSongDeduplicatesByPath() {
        let song1 = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        let song2 = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        XCTAssertEqual(service.library.songs.count, 1)
        XCTAssertEqual(song1.id, song2.id)
    }

    func testSavePracticeState() {
        let song = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        service.savePracticeState(songId: song.id, speed: 0.75, pitch: -2, position: 45, loopStart: 30, loopEnd: 60)
        let updated = service.library.song(byId: song.id)!
        XCTAssertEqual(updated.lastSpeed, 0.75)
        XCTAssertEqual(updated.lastPitch, -2)
        XCTAssertEqual(updated.lastLoopStart, 30)
    }

    func testCreateSetlist() {
        let setlist = service.createSetlist(name: "Gig")
        XCTAssertEqual(service.library.setlists.count, 1)
        XCTAssertEqual(setlist.name, "Gig")
    }

    func testAddSongToSetlist() {
        let song = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        var setlist = service.createSetlist(name: "Gig")
        service.addSongToSetlist(songId: song.id, setlistId: setlist.id)
        setlist = service.library.setlists[0]
        XCTAssertEqual(setlist.songIds.count, 1)
        XCTAssertEqual(setlist.songIds[0], song.id)
    }

    func testCreatePlaylist() {
        let playlist = service.createPlaylist(name: "Practice")
        XCTAssertEqual(service.library.playlists.count, 1)
        XCTAssertEqual(playlist.name, "Practice")
    }

    func testPersistenceRoundTrip() throws {
        let _ = service.addSong(filePath: "/test.mp3", title: "Persist", artist: "A", bpm: 90, duration: 200)
        let _ = service.createSetlist(name: "Gig")
        service.save()

        let service2 = LibraryService(directory: tempDir)
        XCTAssertEqual(service2.library.songs.count, 1)
        XCTAssertEqual(service2.library.songs[0].title, "Persist")
        XCTAssertEqual(service2.library.setlists.count, 1)
    }

    func testCorruptFileRecovery() throws {
        let badData = "not json".data(using: .utf8)!
        try badData.write(to: tempDir.appendingPathComponent("library.json"))

        let recovered = LibraryService(directory: tempDir)
        XCTAssertEqual(recovered.library.songs.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("library.json.backup").path))
    }
}
