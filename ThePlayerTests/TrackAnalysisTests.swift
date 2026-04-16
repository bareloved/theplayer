import XCTest
@testable import ThePlayer

final class TrackAnalysisTests: XCTestCase {

    func testTrackAnalysisCodableRoundTrip() throws {
        let sections = [
            AudioSection(label: "Verse", startTime: 0.0, endTime: 15.5, startBeat: 0, endBeat: 16, colorIndex: 0),
            AudioSection(label: "Chorus", startTime: 15.5, endTime: 30.0, startBeat: 16, endBeat: 32, colorIndex: 1)
        ]
        let analysis = TrackAnalysis(
            bpm: 120.0,
            beats: [0.0, 0.5, 1.0, 1.5, 2.0],
            sections: sections,
            waveformPeaks: [0.1, 0.5, 0.8, 0.3]
        )

        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(TrackAnalysis.self, from: data)

        XCTAssertEqual(decoded.bpm, 120.0)
        XCTAssertEqual(decoded.beats.count, 5)
        XCTAssertEqual(decoded.sections.count, 2)
        XCTAssertEqual(decoded.sections[0].label, "Verse")
        XCTAssertEqual(decoded.sections[1].endTime, 30.0, accuracy: 0.001)
        XCTAssertEqual(decoded.waveformPeaks.count, 4)
    }

    func testAudioSectionDuration() {
        let section = AudioSection(label: "Intro", startTime: 5.0, endTime: 20.0, startBeat: 0, endBeat: 16, colorIndex: 0)
        XCTAssertEqual(section.duration, 15.0, accuracy: 0.001)
    }

    func testAudioSectionBarCount() {
        let section = AudioSection(label: "Verse", startTime: 0.0, endTime: 30.0, startBeat: 0, endBeat: 32, colorIndex: 0)
        XCTAssertEqual(section.barCount, 8) // 32 beats / 4 beats per bar
    }

    func testAudioSectionColor() {
        let section0 = AudioSection(label: "A", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 0)
        let section1 = AudioSection(label: "B", startTime: 1, endTime: 2, startBeat: 4, endBeat: 8, colorIndex: 1)
        XCTAssertNotEqual(section0.color, section1.color)
    }
}
