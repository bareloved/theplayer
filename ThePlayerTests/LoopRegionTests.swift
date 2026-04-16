import XCTest
@testable import ThePlayer

final class LoopRegionTests: XCTestCase {

    func testLoopRegionContainsTime() {
        let loop = LoopRegion(startTime: 10.0, endTime: 20.0)
        XCTAssertTrue(loop.contains(time: 15.0))
        XCTAssertTrue(loop.contains(time: 10.0))
        XCTAssertFalse(loop.contains(time: 20.0))
        XCTAssertFalse(loop.contains(time: 5.0))
    }

    func testLoopRegionDuration() {
        let loop = LoopRegion(startTime: 5.0, endTime: 15.0)
        XCTAssertEqual(loop.duration, 10.0, accuracy: 0.001)
    }

    func testSnapToNearestBeat() {
        let beats: [Float] = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
        let snapped = LoopRegion.snapToNearestBeat(time: 1.3, beats: beats)
        XCTAssertEqual(snapped, 1.5, accuracy: 0.001)
    }

    func testSnapToNearestBeatExactMatch() {
        let beats: [Float] = [0.0, 0.5, 1.0, 1.5, 2.0]
        let snapped = LoopRegion.snapToNearestBeat(time: 1.0, beats: beats)
        XCTAssertEqual(snapped, 1.0, accuracy: 0.001)
    }

    func testSnapToNearestBeatEmptyBeats() {
        let snapped = LoopRegion.snapToNearestBeat(time: 1.3, beats: [])
        XCTAssertEqual(snapped, 1.3, accuracy: 0.001)
    }

    func testFromSection() {
        let section = AudioSection(label: "Chorus", startTime: 15.0, endTime: 30.0, startBeat: 16, endBeat: 32, colorIndex: 1)
        let loop = LoopRegion.from(section: section)
        XCTAssertEqual(loop.startTime, 15.0, accuracy: 0.001)
        XCTAssertEqual(loop.endTime, 30.0, accuracy: 0.001)
    }
}
