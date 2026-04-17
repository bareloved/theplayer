import XCTest
@testable import ThePlayer

final class TimeSignatureTests: XCTestCase {
    func testFourFourHasBeatsPerBar4() {
        XCTAssertEqual(TimeSignature.fourFour.beatsPerBar, 4)
    }

    func testPresetsIncludeCommonSignatures() {
        let set = Set(TimeSignature.presets)
        XCTAssertTrue(set.contains(.fourFour))
        XCTAssertTrue(set.contains(.threeFour))
        XCTAssertTrue(set.contains(.sixEight))
        XCTAssertTrue(set.contains(.twelveEight))
        XCTAssertTrue(set.contains(.twoFour))
    }

    func testEncodeDecodeRoundTrip() throws {
        let ts = TimeSignature.sixEight
        let data = try JSONEncoder().encode(ts)
        let decoded = try JSONDecoder().decode(TimeSignature.self, from: data)
        XCTAssertEqual(decoded, ts)
    }

    func testDisplayString() {
        XCTAssertEqual(TimeSignature.fourFour.displayString, "4/4")
        XCTAssertEqual(TimeSignature.threeFour.displayString, "3/4")
        XCTAssertEqual(TimeSignature.sixEight.displayString, "6/8")
    }
}
