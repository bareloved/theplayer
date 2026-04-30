// ThePlayerTests/JumpMathTests.swift
import XCTest
@testable import ThePlayer

final class JumpMathTests: XCTestCase {

    // MARK: - nextSecondTime

    func testNextSecondForward() {
        XCTAssertEqual(JumpMath.nextSecondTime(from: 10, direction: .forward, seconds: 5, duration: 100), 15, accuracy: 0.0001)
    }

    func testNextSecondBackward() {
        XCTAssertEqual(JumpMath.nextSecondTime(from: 10, direction: .backward, seconds: 5, duration: 100), 5, accuracy: 0.0001)
    }

    func testNextSecondClampStart() {
        XCTAssertEqual(JumpMath.nextSecondTime(from: 3, direction: .backward, seconds: 5, duration: 100), 0, accuracy: 0.0001)
    }

    func testNextSecondClampEnd() {
        XCTAssertEqual(JumpMath.nextSecondTime(from: 98, direction: .forward, seconds: 5, duration: 100), 100, accuracy: 0.0001)
    }

    func testNextSecondAllShortcutValues() {
        let t: Float = 50
        let dur: Float = 100
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 1, duration: dur), 51, accuracy: 0.0001)
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 2, duration: dur), 52, accuracy: 0.0001)
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 5, duration: dur), 55, accuracy: 0.0001)
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 15, duration: dur), 65, accuracy: 0.0001)
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 30, duration: dur), 80, accuracy: 0.0001)
    }

    // MARK: - nextBarTime
    // bpm=240, beatsPerBar=4, firstBeat=0  →  barWidth = 60/240 * 4 = 1.0 s.
    // Bar lines at 0, 1, 2, 3, ...

    private let bpmFixture: Float = 240
    private let bpbFixture: Int = 4

    func testBarForwardFromOnGridFourBars() throws {
        let result = try XCTUnwrap(JumpMath.nextBarTime(from: 3.0, direction: .forward, bars: 4,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100))
        XCTAssertEqual(result, 7.0, accuracy: 0.0001)
    }

    func testBarForwardFromMidBarFourBars() throws {
        let result = try XCTUnwrap(JumpMath.nextBarTime(from: 3.4, direction: .forward, bars: 4,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100))
        XCTAssertEqual(result, 7.0, accuracy: 0.0001)
    }

    func testBarBackwardFromOnGridFourBarsClamps() throws {
        // 3.0 - 4 bars = -1.0 → clamped to 0.
        let result = try XCTUnwrap(JumpMath.nextBarTime(from: 3.0, direction: .backward, bars: 4,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100))
        XCTAssertEqual(result, 0.0, accuracy: 0.0001)
    }

    func testBarBackwardFromMidBarFourBars() throws {
        let result = try XCTUnwrap(JumpMath.nextBarTime(from: 3.4, direction: .backward, bars: 4,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100))
        XCTAssertEqual(result, 0.0, accuracy: 0.0001)
    }

    func testBarForwardOneBarFromOnGridMoves() throws {
        // A press always moves you, even when on-grid.
        let result = try XCTUnwrap(JumpMath.nextBarTime(from: 3.0, direction: .forward, bars: 1,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100))
        XCTAssertEqual(result, 4.0, accuracy: 0.0001)
    }

    func testBarBackwardOneBarFromOnGridMoves() throws {
        let result = try XCTUnwrap(JumpMath.nextBarTime(from: 3.0, direction: .backward, bars: 1,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100))
        XCTAssertEqual(result, 2.0, accuracy: 0.0001)
    }

    func testBarReturnsNilWhenBpmInvalid() {
        XCTAssertNil(
            JumpMath.nextBarTime(from: 3.0, direction: .forward, bars: 1,
                                 bpm: 0, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100)
        )
    }

    func testBarReturnsNilWhenBeatsPerBarInvalid() {
        XCTAssertNil(
            JumpMath.nextBarTime(from: 3.0, direction: .forward, bars: 1,
                                 bpm: bpmFixture, beatsPerBar: 0,
                                 firstBeatTime: 0, duration: 100)
        )
    }

    func testBarReturnsNilWhenBarsInvalid() {
        XCTAssertNil(
            JumpMath.nextBarTime(from: 3.0, direction: .forward, bars: 0,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100)
        )
    }

    func testBarClampsAtEndOfDuration() throws {
        let result = try XCTUnwrap(JumpMath.nextBarTime(from: 95.0, direction: .forward, bars: 16,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0, duration: 100))
        XCTAssertEqual(result, 100.0, accuracy: 0.0001)
    }

    func testBarAllShortcutValuesFromMidBar() throws {
        // From 10.4: forward bars=1 → 11, =2 → 12, =4 → 14, =8 → 18, =16 → 26.
        let cases: [(Int, Float)] = [(1, 11), (2, 12), (4, 14), (8, 18), (16, 26)]
        for (bars, expected) in cases {
            let result = try XCTUnwrap(JumpMath.nextBarTime(from: 10.4, direction: .forward, bars: bars,
                                         bpm: bpmFixture, beatsPerBar: bpbFixture,
                                         firstBeatTime: 0, duration: 100),
                                       "bars=\(bars)")
            XCTAssertEqual(result, expected, accuracy: 0.0001, "bars=\(bars)")
        }
    }

    func testBarRespectsNonZeroFirstBeat() throws {
        // firstBeat=0.25, bars at 0.25, 1.25, 2.25, 3.25...
        // From 1.5 forward bars=1 → 2.25.
        let result = try XCTUnwrap(JumpMath.nextBarTime(from: 1.5, direction: .forward, bars: 1,
                                 bpm: bpmFixture, beatsPerBar: bpbFixture,
                                 firstBeatTime: 0.25, duration: 100))
        XCTAssertEqual(result, 2.25, accuracy: 0.0001)
    }

    // MARK: - barSnapPositions

    func testBarSnapPositionsFromOrigin() {
        // bpm=240, bpb=4 → barWidth=1. Origin=0, duration=5 → [0,1,2,3,4].
        let positions = JumpMath.barSnapPositions(beats: [0], bpm: 240, duration: 5,
                                                  beatsPerBar: 4, firstBeatTime: 0)
        XCTAssertEqual(positions.count, 5)
        XCTAssertEqual(positions[0], 0, accuracy: 0.0001)
        XCTAssertEqual(positions[1], 1, accuracy: 0.0001)
        XCTAssertEqual(positions[4], 4, accuracy: 0.0001)
    }

    func testBarSnapPositionsExtendsBackwardFromFirstBeat() {
        // firstBeat=2, barWidth=1, duration=5 → [0,1,2,3,4].
        let positions = JumpMath.barSnapPositions(beats: [], bpm: 240, duration: 5,
                                                  beatsPerBar: 4, firstBeatTime: 2)
        XCTAssertEqual(positions.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(positions.last ?? -1, 4, accuracy: 0.0001)
    }

    func testBarSnapPositionsEmptyWhenInputsInvalid() {
        XCTAssertTrue(JumpMath.barSnapPositions(beats: [], bpm: 0, duration: 100,
                                                beatsPerBar: 4, firstBeatTime: 0).isEmpty)
        XCTAssertTrue(JumpMath.barSnapPositions(beats: [], bpm: 240, duration: 100,
                                                beatsPerBar: 0, firstBeatTime: 0).isEmpty)
        XCTAssertTrue(JumpMath.barSnapPositions(beats: [], bpm: 240, duration: 0,
                                                beatsPerBar: 4, firstBeatTime: 0).isEmpty)
    }

    func testBarSnapPositionsFallsBackToBeatsFirstWhenNoFirstBeat() {
        // No firstBeatTime; first element of `beats` is the origin.
        let positions = JumpMath.barSnapPositions(beats: [0.5], bpm: 240, duration: 3,
                                                  beatsPerBar: 4, firstBeatTime: nil)
        XCTAssertEqual(positions.first ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(positions[1], 1.5, accuracy: 0.0001)
        XCTAssertEqual(positions.last ?? -1, 2.5, accuracy: 0.0001)
    }
}
