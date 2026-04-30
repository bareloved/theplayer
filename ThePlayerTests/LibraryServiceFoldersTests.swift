import XCTest
@testable import ThePlayer

final class LibraryServiceFoldersTests: XCTestCase {
    var service: LibraryService!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = LibraryService(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCreateAndRenameSetlistFolder() {
        let folder = service.createSetlistFolder(name: "Live")
        XCTAssertEqual(service.library.setlistFolders.count, 1)
        service.renameSetlistFolder(id: folder.id, name: "Live shows")
        XCTAssertEqual(service.library.setlistFolders.first?.name, "Live shows")
    }

    func testMoveAndDeleteSetlistFolder() {
        let folder = service.createSetlistFolder(name: "Live")
        let s = service.createSetlist(name: "Set A")
        service.moveSetlist(id: s.id, toFolder: folder.id)
        XCTAssertEqual(service.library.setlists.first?.folderId, folder.id)

        service.deleteSetlistFolder(id: folder.id)
        XCTAssertEqual(service.library.setlistFolders.count, 0)
        // Setlist itself is preserved at root
        XCTAssertEqual(service.library.setlists.count, 1)
        XCTAssertNil(service.library.setlists.first?.folderId)
    }

    func testCreatePlaylistFolderAndMove() {
        let folder = service.createPlaylistFolder(name: "Practice")
        let p = service.createPlaylist(name: "Daily")
        service.movePlaylist(id: p.id, toFolder: folder.id)
        XCTAssertEqual(service.library.playlists.first?.folderId, folder.id)

        // Move back to root
        service.movePlaylist(id: p.id, toFolder: nil)
        XCTAssertNil(service.library.playlists.first?.folderId)
    }

    func testFoldersPersistAcrossLoad() {
        _ = service.createSetlistFolder(name: "Live")
        _ = service.createPlaylistFolder(name: "Practice")

        let reloaded = LibraryService(directory: tempDir)
        XCTAssertEqual(reloaded.library.setlistFolders.count, 1)
        XCTAssertEqual(reloaded.library.playlistFolders.count, 1)
        XCTAssertEqual(reloaded.library.setlistFolders.first?.name, "Live")
        XCTAssertEqual(reloaded.library.playlistFolders.first?.name, "Practice")
    }
}
