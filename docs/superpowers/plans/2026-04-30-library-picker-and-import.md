# Library Picker & Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Wave 1 of the library track — a Spotlight-style ⌘L picker that searches/sorts the whole library, plus multi-file and recursive folder import.

**Architecture:** Pure search/sort module (`LibraryFiltering`) drives an overlay view (`LibraryPicker`). A separate `FolderImporter` actor walks directories and yields audio URLs to a new batch entry on `LibraryService` (`addSongs(urls:)`). No data-model changes — `SongEntry`, `PlayerLibrary` stay as-is. Title-only rows. Spec: `docs/superpowers/specs/2026-04-30-library-picker-and-import-design.md`.

**Tech Stack:** SwiftUI, AVFoundation, XCTest. macOS 14+. XcodeGen for project regeneration after adding new source files.

---

## File Structure

**Create (in `ThePlayer/`):**
- `Library/LibraryFiltering.swift` — pure functions: `filter(songs:query:)`, `sort(songs:by:)`. Plus `enum LibrarySortMode`.
- `Library/FolderImporter.swift` — `enum FolderImporter` namespace with `static func enumerateAudioFiles(at:)` returning `AsyncStream<URL>`.
- `Views/LibraryPicker.swift` — the SwiftUI overlay view.

**Create (in `ThePlayerTests/`):**
- `LibraryFilteringTests.swift`
- `FolderImporterTests.swift`
- `LibraryServiceImportTests.swift`

**Modify:**
- `ThePlayer/Services/LibraryService.swift` — add `ImportResult` struct + `addSongs(urls:)`.
- `ThePlayer/Views/ContentView.swift` — present picker as `.sheet`, wire ⌘L, add folder-drop.
- `ThePlayer/ThePlayerApp.swift` — add `Commands { }` block: "Open from Library… ⌘L" and "Add Songs… ⇧⌘O".
- `project.yml` — only if a new top-level subdirectory is added; `Library/` is new, so confirm `xcodegen generate` picks it up via the existing source globs (it will — sources are globbed under `ThePlayer/`).

---

## Task 1: Pure search/sort module

**Files:**
- Create: `ThePlayer/Library/LibraryFiltering.swift`
- Test: `ThePlayerTests/LibraryFilteringTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// ThePlayerTests/LibraryFilteringTests.swift
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
        // Get-Lucky-is-actually-Peaches scenario
        let songs = [make("Get Lucky", path: "/Music/peaches_master.mp3")]
        XCTAssertEqual(LibraryFiltering.filter(songs: songs, query: "peach").count, 1)
    }

    func testFilterIgnoresPathDirectories() {
        // "Music" is in the directory portion; should NOT match.
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/LibraryFilteringTests
```
Expected: FAIL — "Cannot find 'LibraryFiltering' in scope".

- [ ] **Step 3: Create the module**

```swift
// ThePlayer/Library/LibraryFiltering.swift
import Foundation

enum LibrarySortMode: String, CaseIterable, Codable {
    case recent
    case alphabetical
    case recentlyAdded
}

enum LibraryFiltering {
    /// Case-insensitive substring match on `title` and the filename portion of `filePath`
    /// (no directory path, no extension). Empty/whitespace query returns all.
    static func filter(songs: [SongEntry], query: String) -> [SongEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return songs }
        return songs.filter { song in
            if song.title.lowercased().contains(q) { return true }
            let filename = (song.filePath as NSString).lastPathComponent
            let stem = (filename as NSString).deletingPathExtension
            return stem.lowercased().contains(q)
        }
    }

    static func sort(songs: [SongEntry], by mode: LibrarySortMode) -> [SongEntry] {
        switch mode {
        case .alphabetical:
            return songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recentlyAdded:
            return songs.sorted { $0.addedAt > $1.addedAt }
        case .recent:
            return songs.sorted { a, b in
                switch (a.lastOpenedAt, b.lastOpenedAt) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true   // a has been opened, b hasn't → a first
                case (nil, _?):    return false
                case (nil, nil):   return a.addedAt > b.addedAt
                }
            }
        }
    }
}
```

- [ ] **Step 4: Regenerate Xcode project (new directory introduced)**

Run: `xcodegen generate`
Expected: "Created project at ThePlayer.xcodeproj".

- [ ] **Step 5: Run tests to verify they pass**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/LibraryFilteringTests
```
Expected: PASS — 6 tests pass.

- [ ] **Step 6: Commit**

```
git add ThePlayer/Library/LibraryFiltering.swift ThePlayerTests/LibraryFilteringTests.swift ThePlayer.xcodeproj
git commit -m "feat(library): add pure search/sort module for library picker"
```

---

## Task 2: Folder importer

**Files:**
- Create: `ThePlayer/Library/FolderImporter.swift`
- Test: `ThePlayerTests/FolderImporterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// ThePlayerTests/FolderImporterTests.swift
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
```

- [ ] **Step 2: Run tests — expect FAIL**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/FolderImporterTests
```
Expected: FAIL — "Cannot find 'FolderImporter' in scope".

- [ ] **Step 3: Create the importer**

```swift
// ThePlayer/Library/FolderImporter.swift
import Foundation
import UniformTypeIdentifiers

enum FolderImporter {
    /// Recursively enumerates audio files under `root`, skipping hidden files and
    /// package contents. Yields each audio URL on a background task.
    static func enumerateAudioFiles(at root: URL) -> AsyncStream<URL> {
        AsyncStream { continuation in
            Task.detached {
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .typeIdentifierKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continuation.finish()
                    return
                }
                for case let url as URL in enumerator {
                    if Task.isCancelled { break }
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .typeIdentifierKey])
                    guard values?.isRegularFile == true else { continue }
                    if let typeId = values?.typeIdentifier,
                       let utType = UTType(typeId),
                       utType.conforms(to: .audio) {
                        continuation.yield(url)
                    }
                }
                continuation.finish()
            }
        }
    }
}
```

- [ ] **Step 4: Regenerate Xcode project**

Run: `xcodegen generate`

- [ ] **Step 5: Run tests — expect PASS**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/FolderImporterTests
```
Expected: PASS — 3 tests.

- [ ] **Step 6: Commit**

```
git add ThePlayer/Library/FolderImporter.swift ThePlayerTests/FolderImporterTests.swift ThePlayer.xcodeproj
git commit -m "feat(library): add recursive audio folder enumerator"
```

---

## Task 3: Batch import on LibraryService

**Files:**
- Modify: `ThePlayer/Services/LibraryService.swift`
- Test: `ThePlayerTests/LibraryServiceImportTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// ThePlayerTests/LibraryServiceImportTests.swift
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

    /// Creates a real m4a file by encoding 0.1s of silence — enough for AVAsset to load.
    /// Returns the URL.
    private func makeSilentM4A(named: String) throws -> URL {
        let url = audioDir.appendingPathComponent(named)
        // Empty file is sufficient; addSongs falls back to filename when metadata read fails.
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    func testAddSongsAddsNewFilesAndCountsAdded() async throws {
        let urls = [
            try makeSilentM4A(named: "a.m4a"),
            try makeSilentM4A(named: "b.m4a"),
            try makeSilentM4A(named: "c.m4a")
        ]
        let result = await service.addSongs(urls: urls)
        XCTAssertEqual(result.added, 3)
        XCTAssertEqual(result.skippedDuplicate, 0)
        XCTAssertEqual(service.library.songs.count, 3)
    }

    func testAddSongsSkipsDuplicatesByPath() async throws {
        let url = try makeSilentM4A(named: "dup.m4a")
        _ = await service.addSongs(urls: [url])
        let result = await service.addSongs(urls: [url])
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.skippedDuplicate, 1)
        XCTAssertEqual(service.library.songs.count, 1)
    }

    func testAddSongsUsesFilenameWhenMetadataMissing() async throws {
        let url = try makeSilentM4A(named: "Mystery Song.m4a")
        _ = await service.addSongs(urls: [url])
        XCTAssertEqual(service.library.songs.first?.title, "Mystery Song")
    }

    func testAddSongsSavesOnceAtEnd() async throws {
        // Verify library.json exists and contains all songs after a single batch.
        let urls = [
            try makeSilentM4A(named: "1.m4a"),
            try makeSilentM4A(named: "2.m4a")
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
```

- [ ] **Step 2: Run tests — expect FAIL**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/LibraryServiceImportTests
```
Expected: FAIL — "Value of type 'LibraryService' has no member 'addSongs'".

- [ ] **Step 3: Add `ImportResult` and `addSongs` to LibraryService**

In `ThePlayer/Services/LibraryService.swift`, just below the `// MARK: - Songs` section's `addSong` method, add:

```swift
struct LibraryImportResult: Equatable {
    var added: Int = 0
    var skippedDuplicate: Int = 0
    var failed: Int = 0
}

extension LibraryService {
    /// Batch-adds many files. Reads embedded metadata per file (falling back to
    /// the filename when missing), defers a single `save()` to the end. Existing
    /// path duplicates are counted, not re-added.
    func addSongs(urls: [URL]) async -> LibraryImportResult {
        var result = LibraryImportResult()
        for url in urls {
            if Task.isCancelled { break }
            if library.songByPath(url.path) != nil {
                result.skippedDuplicate += 1
                continue
            }
            let (title, artist) = await Self.readMetadata(url: url)
            let fallback = url.deletingPathExtension().lastPathComponent
            let song = SongEntry(
                filePath: url.path,
                title: title.isEmpty ? fallback : title,
                artist: artist,
                bpm: 0,
                duration: 0
            )
            library.songs.append(song)
            result.added += 1
        }
        save()
        return result
    }

    private static func readMetadata(url: URL) async -> (title: String, artist: String) {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return ("", "") }
        let title = (try? await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle)
            .first?.load(.stringValue)) ?? nil
        let artist = (try? await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist)
            .first?.load(.stringValue)) ?? nil
        return (title ?? "", artist ?? "")
    }
}
```

Also add `import AVFoundation` near the top of the file if not already present.

- [ ] **Step 4: Run tests — expect PASS**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/LibraryServiceImportTests
```
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```
git add ThePlayer/Services/LibraryService.swift ThePlayerTests/LibraryServiceImportTests.swift
git commit -m "feat(library): add batch addSongs(urls:) with single save"
```

---

## Task 4: LibraryPicker view

**Files:**
- Create: `ThePlayer/Views/LibraryPicker.swift`

This task is a SwiftUI view; it has no unit tests (matches existing project pattern — views aren't unit-tested). Verification is a build + manual smoke.

- [ ] **Step 1: Create the view**

```swift
// ThePlayer/Views/LibraryPicker.swift
import SwiftUI

struct LibraryPicker: View {
    @Bindable var libraryService: LibraryService
    let currentSongPath: String?
    let onOpen: (SongEntry) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""
    @AppStorage("libraryPickerSort") private var sortRaw: String = LibrarySortMode.recent.rawValue
    @State private var highlightedId: UUID?
    @State private var pendingDelete: SongEntry?
    @State private var renamingId: UUID?
    @State private var renameText: String = ""
    @FocusState private var searchFocused: Bool

    private var sort: LibrarySortMode {
        LibrarySortMode(rawValue: sortRaw) ?? .recent
    }

    private var visibleSongs: [SongEntry] {
        let sorted = LibraryFiltering.sort(songs: libraryService.library.songs, by: sort)
        return LibraryFiltering.filter(songs: sorted, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .onAppear { searchFocused = true; ensureHighlight() }
        .onChange(of: visibleSongs.map(\.id)) { _, _ in ensureHighlight() }
        .confirmationDialog(
            "Remove \(pendingDelete?.title ?? "") from library?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let song = pendingDelete { libraryService.deleteSong(songId: song.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The audio file on disk is not deleted.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search library", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { openHighlighted() }
            Picker("Sort", selection: $sortRaw) {
                Text("Recent").tag(LibrarySortMode.recent.rawValue)
                Text("Alphabetical").tag(LibrarySortMode.alphabetical.rawValue)
                Text("Recently added").tag(LibrarySortMode.recentlyAdded.rawValue)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(12)
        .background(KeyEventCatcher(
            onUp: { moveHighlight(by: -1) },
            onDown: { moveHighlight(by: 1) },
            onDelete: { askDeleteHighlighted() },
            onEscape: { onDismiss() }
        ))
    }

    private var list: some View {
        Group {
            if libraryService.library.songs.isEmpty {
                emptyState("No songs yet. Drop a folder anywhere on the window, or use File ▸ Add Songs…")
            } else if visibleSongs.isEmpty {
                emptyState("No songs match \"\(query)\".")
            } else {
                ScrollViewReader { proxy in
                    List(selection: $highlightedId) {
                        ForEach(visibleSongs) { song in
                            row(song)
                                .id(song.id)
                                .tag(song.id)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: highlightedId) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func row(_ song: SongEntry) -> some View {
        HStack {
            if renamingId == song.id {
                TextField("Title", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { libraryService.renameSong(songId: song.id, title: trimmed) }
                        renamingId = nil
                    }
                    .onExitCommand { renamingId = nil }
            } else {
                Text(song.title)
                    .foregroundStyle(song.fileExists ? .primary : .secondary)
                Spacer()
                if song.filePath == currentSongPath {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(song) }
        .onTapGesture { highlightedId = song.id }
        .contextMenu {
            Menu("Add to Setlist") {
                if libraryService.library.setlists.isEmpty {
                    Text("No setlists yet").foregroundStyle(.secondary)
                } else {
                    ForEach(libraryService.library.setlists) { setlist in
                        Button(setlist.name) {
                            libraryService.addSongToSetlist(songId: song.id, setlistId: setlist.id)
                        }
                    }
                }
            }
            Button("Rename…") {
                renameText = song.title
                renamingId = song.id
            }
            Divider()
            Button("Delete from Library", role: .destructive) { pendingDelete = song }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(visibleSongs.count) of \(libraryService.library.songs.count)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("↵ open · ⎋ close · ⌫ delete").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureHighlight() {
        if highlightedId == nil || !visibleSongs.contains(where: { $0.id == highlightedId }) {
            highlightedId = visibleSongs.first?.id
        }
    }

    private func moveHighlight(by delta: Int) {
        guard !visibleSongs.isEmpty else { return }
        let idx = visibleSongs.firstIndex(where: { $0.id == highlightedId }) ?? -1
        let next = max(0, min(visibleSongs.count - 1, idx + delta))
        highlightedId = visibleSongs[next].id
    }

    private func openHighlighted() {
        if let id = highlightedId, let song = visibleSongs.first(where: { $0.id == id }) {
            onOpen(song)
        }
    }

    private func askDeleteHighlighted() {
        if let id = highlightedId, let song = visibleSongs.first(where: { $0.id == id }) {
            pendingDelete = song
        }
    }
}

/// Minimal NSView bridge to capture ↑/↓/⌫/⎋ when the search field is focused.
private struct KeyEventCatcher: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    var onDelete: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(self) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class CatcherView: NSView {
        let bindings: KeyEventCatcher
        init(_ bindings: KeyEventCatcher) {
            self.bindings = bindings
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override var acceptsFirstResponder: Bool { false }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window === event.window else { return event }
                switch event.keyCode {
                case 126: self.bindings.onUp(); return nil       // up arrow
                case 125: self.bindings.onDown(); return nil     // down arrow
                case 51, 117: self.bindings.onDelete(); return nil // delete / forward delete
                case 53: self.bindings.onEscape(); return nil    // escape
                default: return event
                }
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate Xcode project**

Run: `xcodegen generate`

- [ ] **Step 3: Build to verify it compiles**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```
git add ThePlayer/Views/LibraryPicker.swift ThePlayer.xcodeproj
git commit -m "feat(library): add LibraryPicker overlay view"
```

---

## Task 5: Wire ⌘L into ContentView and File menu

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`
- Modify: `ThePlayer/ThePlayerApp.swift`

- [ ] **Step 1: Add picker state and presentation in ContentView**

In `ThePlayer/Views/ContentView.swift`, add `@State private var isPickerOpen = false` near the other `@State` declarations at the top of the view.

Then attach a `.sheet` to the existing root view. Find the outermost `NavigationSplitView { ... }` (or whatever the top-level layout is) and chain a sheet at the end:

```swift
.sheet(isPresented: $isPickerOpen) {
    LibraryPicker(
        libraryService: libraryService,
        currentSongPath: audioEngine.fileURL?.path,
        onOpen: { song in
            isPickerOpen = false
            loadSongFromLibrary(song)
        },
        onDismiss: { isPickerOpen = false }
    )
}
```

Also expose a way for the app-level command to flip this state. Add a `Notification.Name`:

```swift
extension Notification.Name {
    static let openLibraryPicker = Notification.Name("openLibraryPicker")
    static let openAddSongsPanel = Notification.Name("openAddSongsPanel")
}
```

In `ContentView.body`, attach:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openLibraryPicker)) { _ in
    isPickerOpen = true
}
.onReceive(NotificationCenter.default.publisher(for: .openAddSongsPanel)) { _ in
    presentAddSongsPanel()
}
```

And add this method on `ContentView`:

```swift
private func presentAddSongsPanel() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.audio]
    panel.prompt = "Add"
    if panel.runModal() == .OK {
        let urls = panel.urls
        Task { await importPaths(urls) }
    }
}

private func importPaths(_ urls: [URL]) async {
    var expanded: [URL] = []
    for url in urls {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            for await audio in FolderImporter.enumerateAudioFiles(at: url) {
                expanded.append(audio)
            }
        } else {
            expanded.append(url)
        }
    }
    _ = await libraryService.addSongs(urls: expanded)
}
```

Add `import UniformTypeIdentifiers` and `import AppKit` if missing.

- [ ] **Step 2: Add commands to the app**

In `ThePlayer/ThePlayerApp.swift`, attach `.commands` to the existing `WindowGroup`:

```swift
.commands {
    CommandGroup(after: .newItem) {
        Button("Open from Library…") {
            NotificationCenter.default.post(name: .openLibraryPicker, object: nil)
        }
        .keyboardShortcut("l", modifiers: .command)

        Button("Add Songs…") {
            NotificationCenter.default.post(name: .openAddSongsPanel, object: nil)
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}
```

- [ ] **Step 3: Build**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke**

Open the app. Verify:
- ⌘L opens the picker; ⎋ closes it.
- Typing filters; arrow keys move highlight; Enter loads the song; ⌫ asks to remove.
- Right-click a row → Add to Setlist / Rename / Delete behave as designed.
- File ▸ Add Songs… (⇧⌘O) opens an `NSOpenPanel`; selecting multiple files imports them; selecting a folder recurses.

- [ ] **Step 5: Commit**

```
git add ThePlayer/Views/ContentView.swift ThePlayer/ThePlayerApp.swift
git commit -m "feat(library): wire ⌘L picker and File menu import commands"
```

---

## Task 6: Folder drop on the window

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Extend the existing onDrop handler**

Find the existing `onDrop(of: [.fileURL], ...)` modifier on the root view. Replace it with a handler that handles both files and folders:

```swift
.onDrop(of: [.fileURL], isTargeted: nil) { providers in
    Task { @MainActor in
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadURL(from: provider) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return }
        // If a single file is dropped, preserve today's "open it" behaviour.
        if urls.count == 1, !isDirectory(urls[0]) {
            openFile(url: urls[0])
            return
        }
        await importPaths(urls)
    }
    return true
}
```

Add the helpers (next to `importPaths`):

```swift
private func loadURL(from provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { cont in
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                cont.resume(returning: url)
            } else {
                cont.resume(returning: nil)
            }
        }
    }
}

private func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
    return isDir.boolValue
}
```

- [ ] **Step 2: Build**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke**

- Drop a single audio file onto the window → it loads and is added to the library (same as today).
- Drop a folder onto the window → all audio inside (recursively) is imported. Open ⌘L to confirm.
- Drop a folder onto an open ⌘L picker → same import path triggers; count grows.

- [ ] **Step 4: Commit**

```
git add ThePlayer/Views/ContentView.swift
git commit -m "feat(library): import folders dropped on window recursively"
```

---

## Task 7: Final verification

- [ ] **Step 1: Run the entire test suite**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test
```
Expected: all tests pass.

- [ ] **Step 2: Manual end-to-end check**

1. Launch the app on an empty library (rename `~/Library/Application Support/The Player/library.json` aside if needed, or use a clean DerivedData).
2. Press ⌘L → picker shows empty-state copy.
3. File ▸ Add Songs… → pick a folder of mp3s. Wait for import.
4. ⌘L → all songs visible, sorted by Recent (today none have been opened, so they fall through to addedAt order).
5. Type 3 letters from a song's filename or title — list filters live.
6. Switch sort to Alphabetical via the picker dropdown — order updates.
7. Highlight a row, press Enter → song loads, picker closes.
8. ⌘L again, right-click a row → rename, then delete.
9. Quit and relaunch → sort selection persists; library persists; no crashes.

- [ ] **Step 3: No commit needed**

If anything failed, return to the offending task. Otherwise the wave is done.

---

## Self-review notes

- Spec coverage: search ✓ (Task 1), sort ✓ (Task 1), substring on title+filename ✓ (Task 1), recursive folder import ✓ (Task 2), batch addSongs ✓ (Task 3), single save() at end ✓ (Task 3 test), ⌘L picker ✓ (Task 4-5), File menu ✓ (Task 5), folder drop on window ✓ (Task 6), row actions ✓ (Task 4), Delete confirm ✓ (Task 4), title-only rows ✓ (Task 4 row body).
- Open question from spec (sheet vs overlay): plan picks `.sheet`, matching the spec recommendation.
- One deferred item: progress toast during long imports. Wave 1 imports are fast enough that we ship without a progress UI; a follow-up can add it if a user complains.
