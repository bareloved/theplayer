import XCTest
@testable import ThePlayer

final class LibraryServiceImportTests: XCTestCase {
    var service: LibraryService!
    var tempDir: URL!
    var audioDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        audioDir = tempDir.appendingPathComponent("audio")
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        service = LibraryService(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFile(named: String) throws -> URL {
        let url = audioDir.appendingPathComponent(named)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    func testAddSongsAddsNewFilesAndCountsAdded() async throws {
        let urls = [
            try makeFile(named: "a.m4a"),
            try makeFile(named: "b.m4a"),
            try makeFile(named: "c.m4a")
        ]
        let result = await service.addSongs(urls: urls)
        XCTAssertEqual(result.added, 3)
        XCTAssertEqual(result.skippedDuplicate, 0)
        XCTAssertEqual(service.library.songs.count, 3)
    }

    func testAddSongsSkipsDuplicatesByPath() async throws {
        let url = try makeFile(named: "dup.m4a")
        _ = await service.addSongs(urls: [url])
        let result = await service.addSongs(urls: [url])
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.skippedDuplicate, 1)
        XCTAssertEqual(service.library.songs.count, 1)
    }

    func testAddSongsUsesFilenameWhenMetadataMissing() async throws {
        let url = try makeFile(named: "Mystery Song.m4a")
        _ = await service.addSongs(urls: [url])
        XCTAssertEqual(service.library.songs.first?.title, "Mystery Song")
    }

    func testAddSongsSavesOnceAtEnd() async throws {
        let urls = [
            try makeFile(named: "1.m4a"),
            try makeFile(named: "2.m4a")
        ]
        _ = await service.addSongs(urls: urls)
        let saved = tempDir.appendingPathComponent("library.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        let data = try Data(contentsOf: saved)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lib = try decoder.decode(PlayerLibrary.self, from: data)
        XCTAssertEqual(lib.songs.count, 2)
    }
}
