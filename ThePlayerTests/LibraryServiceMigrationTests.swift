import XCTest
@testable import ThePlayer

final class LibraryServiceMigrationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Pre-migration JSON shape: top-level only has `songs`, `setlists`, `playlists`.
    /// Setlist/Playlist objects also have no `folderId`. The new build must load
    /// this without throwing.
    func testLoadsPreFolderJSON() throws {
        let legacy = """
        {
          "songs": [],
          "setlists": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Old Setlist",
              "songIds": [],
              "createdAt": "2025-01-01T00:00:00Z",
              "updatedAt": "2025-01-01T00:00:00Z"
            }
          ],
          "playlists": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Old Playlist",
              "songIds": [],
              "createdAt": "2025-01-01T00:00:00Z",
              "updatedAt": "2025-01-01T00:00:00Z"
            }
          ]
        }
        """
        let path = tempDir.appendingPathComponent("library.json")
        try legacy.data(using: .utf8)!.write(to: path)

        let service = LibraryService(directory: tempDir)
        XCTAssertEqual(service.library.setlists.count, 1)
        XCTAssertEqual(service.library.setlists.first?.name, "Old Setlist")
        XCTAssertNil(service.library.setlists.first?.folderId)
        XCTAssertEqual(service.library.playlists.count, 1)
        XCTAssertNil(service.library.playlists.first?.folderId)
        XCTAssertEqual(service.library.setlistFolders, [])
        XCTAssertEqual(service.library.playlistFolders, [])
    }
}
