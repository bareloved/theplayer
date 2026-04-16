import XCTest
@testable import ThePlayer

final class AnalysisServiceMergeTests: XCTestCase {
    var tempDir: URL!
    var cache: AnalysisCache!
    var userEdits: UserEditsStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cache = AnalysisCache(directory: tempDir)
        userEdits = UserEditsStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testMergeOverridesSectionsWhenSidecarPresent() throws {
        let analyzed = TrackAnalysis(
            bpm: 120,
            beats: [0, 0.5, 1.0],
            sections: [AudioSection(label: "Auto", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 0)],
            waveformPeaks: [0.1]
        )
        let edited = [AudioSection(label: "Manual", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 2)]
        try cache.store(analyzed, forKey: "key1")
        try userEdits.store(UserEdits(sections: edited), forKey: "key1")

        let merged = AnalysisService.mergeCachedAnalysis(analyzed, userEdits: try userEdits.retrieve(forKey: "key1"))
        XCTAssertEqual(merged.sections.first?.label, "Manual")
        XCTAssertEqual(merged.bpm, 120)
    }

    func testMergePassesThroughWhenNoSidecar() throws {
        let analyzed = TrackAnalysis(bpm: 120, beats: [], sections: [], waveformPeaks: [])
        let merged = AnalysisService.mergeCachedAnalysis(analyzed, userEdits: nil)
        XCTAssertEqual(merged, analyzed)
    }
}
