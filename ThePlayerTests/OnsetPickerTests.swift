import XCTest
@testable import ThePlayer

final class OnsetPickerTests: XCTestCase {

    func testEmptyOnsetsReturnsNil() {
        XCTAssertNil(OnsetPicker.nearestOnset(to: 1.0, in: [], pxPerSec: 100, maxPx: 30))
    }

    func testExactMatchReturnsSelf() {
        let result = OnsetPicker.nearestOnset(to: 1.0, in: [0.5, 1.0, 1.5], pxPerSec: 100, maxPx: 30)
        XCTAssertEqual(result, 1.0)
    }

    func testNearestIsChosen() {
        // 0.9 is closer to 1.0 than 0.5.
        let result = OnsetPicker.nearestOnset(to: 0.9, in: [0.5, 1.0, 1.5], pxPerSec: 100, maxPx: 30)
        XCTAssertEqual(result, 1.0)
    }

    func testEquidistantTieReturnsEarlierOnset() {
        // click at 1.0, onsets at 0.8 and 1.2 — both 0.2s away. Earlier wins.
        let result = OnsetPicker.nearestOnset(to: 1.0, in: [0.8, 1.2], pxPerSec: 100, maxPx: 100)
        XCTAssertEqual(result, 0.8)
    }

    func testOutOfRangeReturnsNil() {
        // nearest onset is 0.5s away; at 100 px/sec that's 50px > maxPx=30.
        let result = OnsetPicker.nearestOnset(to: 1.5, in: [1.0], pxPerSec: 100, maxPx: 30)
        XCTAssertNil(result)
    }

    func testZoomChangesInRangeness() {
        // Same audio gap (0.5s); fails at 100 px/s but succeeds at 200 px/s when maxPx=120.
        XCTAssertNil(OnsetPicker.nearestOnset(to: 1.5, in: [1.0], pxPerSec: 100, maxPx: 30))
        XCTAssertEqual(OnsetPicker.nearestOnset(to: 1.5, in: [1.0], pxPerSec: 200, maxPx: 120), 1.0)
    }

    func testClickBeforeFirstOnset() {
        let result = OnsetPicker.nearestOnset(to: 0.0, in: [0.1, 1.0, 2.0], pxPerSec: 1000, maxPx: 500)
        XCTAssertEqual(result, 0.1)
    }

    func testClickAfterLastOnset() {
        let result = OnsetPicker.nearestOnset(to: 5.0, in: [0.1, 1.0, 2.0], pxPerSec: 1000, maxPx: 5000)
        XCTAssertEqual(result, 2.0)
    }
}
