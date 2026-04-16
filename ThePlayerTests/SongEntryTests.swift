import XCTest
@testable import ThePlayer

final class SongEntryTests: XCTestCase {
    func testSongEntryCodableRoundTrip() throws {
        let song = SongEntry(filePath: "/Users/test/song.mp3", title: "Test Song", artist: "Test Artist", bpm: 120, duration: 180)
        let data = try JSONEncoder().encode(song)
        let decoded = try JSONDecoder().decode(SongEntry.self, from: data)
        XCTAssertEqual(decoded.title, "Test Song")
        XCTAssertEqual(decoded.bpm, 120)
        XCTAssertEqual(decoded.lastSpeed, 1.0)
        XCTAssertNil(decoded.lastLoopStart)
    }

    func testSongEntryFileExists() {
        let song = SongEntry(filePath: "/nonexistent/file.mp3", title: "X", artist: "", bpm: 0, duration: 0)
        XCTAssertFalse(song.fileExists)
    }

    func testSongEntryPracticeStateUpdate() {
        var song = SongEntry(filePath: "/test.mp3", title: "X", artist: "", bpm: 0, duration: 0)
        song.lastSpeed = 0.75
        song.lastPitch = -2
        song.lastPosition = 45.3
        song.lastLoopStart = 30.0
        song.lastLoopEnd = 60.0
        song.practiceCount = 5
        XCTAssertEqual(song.lastSpeed, 0.75)
        XCTAssertEqual(song.lastLoopStart, 30.0)
        XCTAssertEqual(song.practiceCount, 5)
    }
}
