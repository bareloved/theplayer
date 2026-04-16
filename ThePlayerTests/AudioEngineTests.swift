import XCTest
@testable import ThePlayer

final class AudioEngineTests: XCTestCase {

    func testInitialState() {
        let engine = AudioEngine()
        XCTAssertEqual(engine.state, .empty)
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertEqual(engine.duration, 0)
        XCTAssertEqual(engine.speed, 1.0)
        XCTAssertEqual(engine.pitch, 0)
        XCTAssertFalse(engine.isPlaying)
    }

    func testLoadFile() throws {
        let engine = AudioEngine()
        let url = Bundle(for: type(of: self)).url(forResource: "test-audio", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/test-audio.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Test audio file not available")
        }
        try engine.loadFile(url: url)
        XCTAssertEqual(engine.state, .loaded)
        XCTAssertGreaterThan(engine.duration, 0)
    }

    func testSpeedClamp() {
        let engine = AudioEngine()
        engine.speed = 0.1 // below minimum
        XCTAssertEqual(engine.speed, 0.25, accuracy: 0.01)
        engine.speed = 3.0 // above maximum
        XCTAssertEqual(engine.speed, 2.0, accuracy: 0.01)
    }

    func testPitchClamp() {
        let engine = AudioEngine()
        engine.pitch = -15 // below minimum
        XCTAssertEqual(engine.pitch, -12, accuracy: 0.01)
        engine.pitch = 15 // above maximum
        XCTAssertEqual(engine.pitch, 12, accuracy: 0.01)
    }
}
