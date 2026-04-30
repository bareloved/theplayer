import XCTest
@testable import ThePlayer

final class LibraryFilteringTests: XCTestCase {
    private func make(_ title: String, path: String, addedAt: Date = Date(), opened: Date? = nil) -> SongEntry {
        var s = SongEntry(filePath: path, title: title, artist: "", bpm: 0, duration: 0)
        s.addedAt = addedAt
        s.lastOpenedAt = opened
        return s
    }

    func testFilterEmptyQueryReturnsAll() {
        let songs = [make("A", path: "/a.mp3"), make("B", path: "/b.mp3")]
        XCTAssertEqual(LibraryFiltering.filter(songs: songs, query: "").count, 2)
        XCTAssertEqual(LibraryFiltering.filter(songs: songs, query: "   ").count, 2)
    }

    func testFilterMatchesTitleCaseInsensitive() {
        let songs = [make("Get Lucky", path: "/x.mp3"), make("Wonderwall", path: "/y.mp3")]
        XCTAssertEqual(LibraryFiltering.filter(songs: songs, query: "lucky").map(\.title), ["Get Lucky"])
        XCTAssertEqual(LibraryFiltering.filter(songs: songs, query: "WONDER").map(\.title), ["Wonderwall"])
    }

    func testFilterMatchesFilenameWhenTitleDiffers() {
        let songs = [make("Get Lucky", path: "/Music/peaches_master.mp3")]
        XCTAssertEqual(LibraryFiltering.filter(songs: songs, query: "peach").count, 1)
    }

    func testFilterIgnoresPathDirectories() {
        let songs = [make("Foo", path: "/Users/me/Music/foo.mp3")]
        XCTAssertEqual(LibraryFiltering.filter(songs: songs, query: "users").count, 0)
        XCTAssertEqual(LibraryFiltering.filter(songs: songs, query: "music").count, 0)
    }

    func testSortAlphabeticalLocaleAware() {
        let songs = [make("banana", path: "/b"), make("Apple", path: "/a"), make("Élise", path: "/e")]
        let sorted = LibraryFiltering.sort(songs: songs, by: .alphabetical).map(\.title)
        XCTAssertEqual(sorted, ["Apple", "banana", "Élise"])
    }

    func testSortRecentlyAddedDesc() {
        let now = Date()
        let songs = [
            make("old", path: "/o", addedAt: now.addingTimeInterval(-1000)),
            make("new", path: "/n", addedAt: now)
        ]
        XCTAssertEqual(LibraryFiltering.sort(songs: songs, by: .recentlyAdded).map(\.title), ["new", "old"])
    }

    func testSortRecentNilsFallToBottomByAddedAtDesc() {
        let now = Date()
        let songs = [
            make("opened-old", path: "/a", addedAt: now.addingTimeInterval(-100), opened: now.addingTimeInterval(-50)),
            make("never-opened-newer", path: "/b", addedAt: now, opened: nil),
            make("never-opened-older", path: "/c", addedAt: now.addingTimeInterval(-200), opened: nil),
            make("opened-recent", path: "/d", addedAt: now.addingTimeInterval(-300), opened: now)
        ]
        let sorted = LibraryFiltering.sort(songs: songs, by: .recent).map(\.title)
        XCTAssertEqual(sorted, ["opened-recent", "opened-old", "never-opened-newer", "never-opened-older"])
    }
}
