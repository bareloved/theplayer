import XCTest
@testable import ThePlayer

final class WaveformExtractorTests: XCTestCase {

    func testExtractPeaks() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "test-audio", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/test-audio.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Test audio file not available")
        }

        let peaks = try WaveformExtractor.extractPeaks(from: url, targetCount: 200)
        XCTAssertEqual(peaks.count, 200)
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1.0 })
    }

    func testExtractPeaksNonZero() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "test-audio", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/test-audio.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Test audio file not available")
        }

        let peaks = try WaveformExtractor.extractPeaks(from: url, targetCount: 100)
        let maxPeak = peaks.max() ?? 0
        XCTAssertGreaterThan(maxPeak, 0, "Peaks should contain non-zero values for audio with content")
    }

    func testDownsampleArray() {
        let input: [Float] = [0.1, 0.5, 0.8, 0.3, 0.9, 0.2]
        let result = WaveformExtractor.downsample(input, to: 3)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], 0.5, accuracy: 0.01)  // max of [0.1, 0.5]
        XCTAssertEqual(result[1], 0.8, accuracy: 0.01)  // max of [0.8, 0.3]
        XCTAssertEqual(result[2], 0.9, accuracy: 0.01)  // max of [0.9, 0.2]
    }
}
