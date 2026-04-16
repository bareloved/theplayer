import XCTest
@testable import ThePlayer

final class AnalysisCacheTests: XCTestCase {

    var cache: AnalysisCache!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cache = AnalysisCache(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testStoreAndRetrieve() throws {
        let analysis = TrackAnalysis(
            bpm: 120,
            beats: [0.0, 0.5, 1.0],
            sections: [],
            waveformPeaks: [0.1, 0.2]
        )
        let key = "abc123"

        try cache.store(analysis, forKey: key)
        let retrieved = try cache.retrieve(forKey: key)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.bpm, 120)
        XCTAssertEqual(retrieved?.beats.count, 3)
    }

    func testRetrieveNonexistent() throws {
        let retrieved = try cache.retrieve(forKey: "doesnotexist")
        XCTAssertNil(retrieved)
    }

    func testFileHash() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "test-audio", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/test-audio.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Test audio file not available")
        }

        let hash1 = try AnalysisCache.fileHash(for: url)
        let hash2 = try AnalysisCache.fileHash(for: url)
        XCTAssertEqual(hash1, hash2)
        XCTAssertFalse(hash1.isEmpty)
    }
}
