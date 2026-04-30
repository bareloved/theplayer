import XCTest
import UniformTypeIdentifiers
@testable import ThePlayer

final class FolderImporterTests: XCTestCase {
    var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func touch(_ relative: String) {
        let url = root.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    func testEnumeratesAudioInNestedFolders() async {
        touch("a.mp3")
        touch("subdir/b.wav")
        touch("subdir/deeper/c.m4a")
        touch("subdir/notes.txt")

        var found: [String] = []
        for await url in FolderImporter.enumerateAudioFiles(at: root) {
            found.append(url.lastPathComponent)
        }
        XCTAssertEqual(Set(found), Set(["a.mp3", "b.wav", "c.m4a"]))
    }

    func testSkipsHiddenFiles() async {
        touch("song.mp3")
        touch(".DS_Store")
        touch(".hidden.mp3")

        var found: [String] = []
        for await url in FolderImporter.enumerateAudioFiles(at: root) {
            found.append(url.lastPathComponent)
        }
        XCTAssertEqual(found, ["song.mp3"])
    }

    func testIgnoresNonAudioExtensions() async {
        touch("readme.md")
        touch("cover.jpg")
        touch("track.mp3")

        var found: [String] = []
        for await url in FolderImporter.enumerateAudioFiles(at: root) {
            found.append(url.lastPathComponent)
        }
        XCTAssertEqual(found, ["track.mp3"])
    }
}
