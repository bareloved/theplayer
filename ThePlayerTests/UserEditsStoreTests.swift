import XCTest
@testable import ThePlayer

final class UserEditsStoreTests: XCTestCase {
    var store: UserEditsStore!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = UserEditsStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeEdits() -> UserEdits {
        UserEdits(sections: [
            AudioSection(label: "Verse", startTime: 0, endTime: 10, startBeat: 0, endBeat: 16, colorIndex: 1)
        ])
    }

    func testStoreAndRetrieveRoundTrip() throws {
        let edits = makeEdits()
        try store.store(edits, forKey: "abc")
        let loaded = try store.retrieve(forKey: "abc")
        XCTAssertEqual(loaded?.sections.first?.label, "Verse")
        XCTAssertEqual(loaded?.schemaVersion, 1)
    }

    func testRetrieveNonexistentReturnsNil() throws {
        XCTAssertNil(try store.retrieve(forKey: "nope"))
    }

    func testExistsReflectsState() throws {
        XCTAssertFalse(store.exists(forKey: "abc"))
        try store.store(makeEdits(), forKey: "abc")
        XCTAssertTrue(store.exists(forKey: "abc"))
    }

    func testDeleteRemovesFile() throws {
        try store.store(makeEdits(), forKey: "abc")
        try store.delete(forKey: "abc")
        XCTAssertFalse(store.exists(forKey: "abc"))
        XCTAssertNil(try store.retrieve(forKey: "abc"))
    }

    func testRetrieveUnknownSchemaVersionReturnsNil() throws {
        let url = tempDir.appendingPathComponent("abc.user.json")
        let json = """
        {"sections":[],"modifiedAt":700000000,"schemaVersion":9999}
        """
        try json.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(try store.retrieve(forKey: "abc"))
    }
}
