# Library, Setlists & Playlists — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a song library with practice history, setlists, playlists, and smart playlists to The Player, with auto-save of practice state and a three-column collapsible layout.

**Architecture:** New `Library` model (Codable) persisted as single JSON file. `LibraryService` (@Observable) manages CRUD, auto-save, and smart playlist computation. UI shifts from two-column NavigationSplitView to HStack with two collapsible sidebars flanking the center player. Left sidebar shows library/setlists/playlists, right sidebar shows song sections (existing SidebarView moves here).

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+, JSONEncoder/Decoder for persistence

---

## File Structure

```
ThePlayer/
├── Models/
│   ├── SongEntry.swift          # Song with practice state — Codable
│   ├── Setlist.swift             # Ordered song list — Codable
│   ├── Playlist.swift            # Unordered song collection — Codable
│   └── PlayerLibrary.swift       # Top-level container: songs, setlists, playlists
├── Services/
│   └── LibraryService.swift      # @Observable — CRUD, persistence, smart playlists, auto-save
├── Views/
│   ├── ContentView.swift         # MODIFY — three-column layout with collapsible sidebars
│   ├── LibrarySidebar.swift      # NEW — left sidebar: recent, setlists, playlists, smart
│   ├── SidebarView.swift         # MODIFY — becomes right sidebar (song sections)
│   ├── TransportBar.swift        # MODIFY — add "Next →" button for setlist mode
│   └── ThePlayerApp.swift        # MODIFY — create LibraryService, pass to ContentView
├── ThePlayerTests/
│   ├── SongEntryTests.swift
│   ├── LibraryServiceTests.swift
│   └── PlayerLibraryTests.swift
```

---

### Task 1: Data Models — SongEntry, Setlist, Playlist, PlayerLibrary

**Files:**
- Create: `ThePlayer/Models/SongEntry.swift`
- Create: `ThePlayer/Models/Setlist.swift`
- Create: `ThePlayer/Models/Playlist.swift`
- Create: `ThePlayer/Models/PlayerLibrary.swift`
- Create: `ThePlayerTests/SongEntryTests.swift`
- Create: `ThePlayerTests/PlayerLibraryTests.swift`

- [ ] **Step 1: Write SongEntry and PlayerLibrary tests**

Create `ThePlayerTests/SongEntryTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class SongEntryTests: XCTestCase {

    func testSongEntryCodableRoundTrip() throws {
        let song = SongEntry(
            filePath: "/Users/test/song.mp3",
            title: "Test Song",
            artist: "Test Artist",
            bpm: 120,
            duration: 180
        )
        let data = try JSONEncoder().encode(song)
        let decoded = try JSONDecoder().decode(SongEntry.self, from: data)
        XCTAssertEqual(decoded.title, "Test Song")
        XCTAssertEqual(decoded.bpm, 120)
        XCTAssertEqual(decoded.lastSpeed, 1.0)
        XCTAssertNil(decoded.lastLoopStart)
    }

    func testSongEntryFileExists() {
        let song = SongEntry(filePath: "/nonexistent/file.mp3", title: "X", artist: "", bpm: 0, duration: 0)
        XCTAssertFalse(song.fileExists)
    }

    func testSongEntryPracticeStateUpdate() {
        var song = SongEntry(filePath: "/test.mp3", title: "X", artist: "", bpm: 0, duration: 0)
        song.lastSpeed = 0.75
        song.lastPitch = -2
        song.lastPosition = 45.3
        song.lastLoopStart = 30.0
        song.lastLoopEnd = 60.0
        song.practiceCount = 5
        XCTAssertEqual(song.lastSpeed, 0.75)
        XCTAssertEqual(song.lastLoopStart, 30.0)
        XCTAssertEqual(song.practiceCount, 5)
    }
}
```

Create `ThePlayerTests/PlayerLibraryTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class PlayerLibraryTests: XCTestCase {

    func testLibraryCodableRoundTrip() throws {
        var library = PlayerLibrary()
        let song = SongEntry(filePath: "/test.mp3", title: "Song", artist: "Artist", bpm: 90, duration: 200)
        library.songs.append(song)

        let setlist = Setlist(name: "Gig", songIds: [song.id])
        library.setlists.append(setlist)

        let playlist = Playlist(name: "Practice", songIds: [song.id])
        library.playlists.append(playlist)

        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(PlayerLibrary.self, from: data)

        XCTAssertEqual(decoded.songs.count, 1)
        XCTAssertEqual(decoded.setlists.count, 1)
        XCTAssertEqual(decoded.setlists[0].name, "Gig")
        XCTAssertEqual(decoded.playlists.count, 1)
    }

    func testSmartPlaylistRecent() {
        var library = PlayerLibrary()
        for i in 0..<25 {
            var song = SongEntry(filePath: "/song\(i).mp3", title: "Song \(i)", artist: "", bpm: 0, duration: 0)
            song.lastOpenedAt = Date().addingTimeInterval(Double(-i) * 3600)
            library.songs.append(song)
        }
        let recent = library.recentSongs(limit: 20)
        XCTAssertEqual(recent.count, 20)
        XCTAssertEqual(recent[0].title, "Song 0") // most recent first
    }

    func testSmartPlaylistMostPracticed() {
        var library = PlayerLibrary()
        for i in 0..<15 {
            var song = SongEntry(filePath: "/song\(i).mp3", title: "Song \(i)", artist: "", bpm: 0, duration: 0)
            song.practiceCount = i
            library.songs.append(song)
        }
        let top = library.mostPracticed(limit: 10)
        XCTAssertEqual(top.count, 10)
        XCTAssertEqual(top[0].practiceCount, 14) // highest first
    }

    func testSmartPlaylistNeedsWork() {
        var library = PlayerLibrary()
        for i in 0..<5 {
            var song = SongEntry(filePath: "/song\(i).mp3", title: "Song \(i)", artist: "", bpm: 0, duration: 0)
            song.practiceCount = i
            library.songs.append(song)
        }
        let needsWork = library.needsWork(threshold: 3)
        XCTAssertEqual(needsWork.count, 3) // songs with practiceCount 0, 1, 2
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(error|FAIL)"`
Expected: Compilation errors — models don't exist

- [ ] **Step 3: Implement SongEntry**

Create `ThePlayer/Models/SongEntry.swift`:

```swift
import Foundation

struct SongEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var filePath: String
    var title: String
    var artist: String
    var bpm: Float
    var duration: Float
    var analysisCacheKey: String?

    // Practice state
    var lastSpeed: Float = 1.0
    var lastPitch: Float = 0
    var lastPosition: Float = 0
    var lastLoopStart: Float?
    var lastLoopEnd: Float?

    // Timestamps
    var lastOpenedAt: Date?
    var addedAt: Date

    // Stats
    var practiceCount: Int = 0
    var totalPracticeTime: Double = 0

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    init(filePath: String, title: String, artist: String, bpm: Float, duration: Float) {
        self.id = UUID()
        self.filePath = filePath
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.duration = duration
        self.addedAt = Date()
    }
}
```

- [ ] **Step 4: Implement Setlist**

Create `ThePlayer/Models/Setlist.swift`:

```swift
import Foundation

struct Setlist: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var songIds: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(name: String, songIds: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.songIds = songIds
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
```

- [ ] **Step 5: Implement Playlist**

Create `ThePlayer/Models/Playlist.swift`:

```swift
import Foundation

struct Playlist: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var songIds: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(name: String, songIds: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.songIds = songIds
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
```

- [ ] **Step 6: Implement PlayerLibrary**

Create `ThePlayer/Models/PlayerLibrary.swift`:

```swift
import Foundation

struct PlayerLibrary: Codable {
    var songs: [SongEntry] = []
    var setlists: [Setlist] = []
    var playlists: [Playlist] = []

    func song(byId id: UUID) -> SongEntry? {
        songs.first(where: { $0.id == id })
    }

    func songIndex(byId id: UUID) -> Int? {
        songs.firstIndex(where: { $0.id == id })
    }

    func songByPath(_ path: String) -> SongEntry? {
        songs.first(where: { $0.filePath == path })
    }

    // Smart playlists
    func recentSongs(limit: Int = 20) -> [SongEntry] {
        songs
            .filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    func mostPracticed(limit: Int = 10) -> [SongEntry] {
        songs
            .sorted { $0.practiceCount > $1.practiceCount }
            .prefix(limit)
            .map { $0 }
    }

    func needsWork(threshold: Int = 3) -> [SongEntry] {
        songs.filter { $0.practiceCount < threshold }
    }
}
```

- [ ] **Step 7: Run xcodegen and tests**

```bash
xcodegen generate
xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Executed|FAIL)"
```
Expected: All new tests pass

- [ ] **Step 8: Commit**

```bash
git add ThePlayer/Models/SongEntry.swift ThePlayer/Models/Setlist.swift ThePlayer/Models/Playlist.swift ThePlayer/Models/PlayerLibrary.swift ThePlayerTests/SongEntryTests.swift ThePlayerTests/PlayerLibraryTests.swift
git commit -m "feat: add data models — SongEntry, Setlist, Playlist, PlayerLibrary"
```

---

### Task 2: LibraryService — Persistence, CRUD, Auto-save

**Files:**
- Create: `ThePlayer/Services/LibraryService.swift`
- Create: `ThePlayerTests/LibraryServiceTests.swift`

- [ ] **Step 1: Write LibraryService tests**

Create `ThePlayerTests/LibraryServiceTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class LibraryServiceTests: XCTestCase {

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

    func testAddSong() {
        let song = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        XCTAssertEqual(service.library.songs.count, 1)
        XCTAssertEqual(song.title, "Test")
    }

    func testAddSongDeduplicatesByPath() {
        let song1 = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        let song2 = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        XCTAssertEqual(service.library.songs.count, 1)
        XCTAssertEqual(song1.id, song2.id)
    }

    func testSavePracticeState() {
        let song = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        service.savePracticeState(songId: song.id, speed: 0.75, pitch: -2, position: 45, loopStart: 30, loopEnd: 60)
        let updated = service.library.song(byId: song.id)!
        XCTAssertEqual(updated.lastSpeed, 0.75)
        XCTAssertEqual(updated.lastPitch, -2)
        XCTAssertEqual(updated.lastLoopStart, 30)
    }

    func testCreateSetlist() {
        let setlist = service.createSetlist(name: "Gig")
        XCTAssertEqual(service.library.setlists.count, 1)
        XCTAssertEqual(setlist.name, "Gig")
    }

    func testAddSongToSetlist() {
        let song = service.addSong(filePath: "/test.mp3", title: "Test", artist: "A", bpm: 120, duration: 180)
        var setlist = service.createSetlist(name: "Gig")
        service.addSongToSetlist(songId: song.id, setlistId: setlist.id)
        setlist = service.library.setlists[0]
        XCTAssertEqual(setlist.songIds.count, 1)
        XCTAssertEqual(setlist.songIds[0], song.id)
    }

    func testCreatePlaylist() {
        let playlist = service.createPlaylist(name: "Practice")
        XCTAssertEqual(service.library.playlists.count, 1)
        XCTAssertEqual(playlist.name, "Practice")
    }

    func testPersistenceRoundTrip() throws {
        let song = service.addSong(filePath: "/test.mp3", title: "Persist", artist: "A", bpm: 90, duration: 200)
        let _ = service.createSetlist(name: "Gig")
        service.save()

        let service2 = LibraryService(directory: tempDir)
        XCTAssertEqual(service2.library.songs.count, 1)
        XCTAssertEqual(service2.library.songs[0].title, "Persist")
        XCTAssertEqual(service2.library.setlists.count, 1)
    }

    func testCorruptFileRecovery() throws {
        let badData = "not json".data(using: .utf8)!
        try badData.write(to: tempDir.appendingPathComponent("library.json"))

        let recovered = LibraryService(directory: tempDir)
        XCTAssertEqual(recovered.library.songs.count, 0)
        // Backup should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("library.json.backup").path))
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(error|FAIL)"`
Expected: Compilation errors — LibraryService doesn't exist

- [ ] **Step 3: Implement LibraryService**

Create `ThePlayer/Services/LibraryService.swift`:

```swift
import Foundation
import Observation

@Observable
final class LibraryService {
    private(set) var library: PlayerLibrary
    private let directory: URL
    private let filePath: URL

    // Setlist playback state
    var activeSetlistId: UUID?
    var activeSetlistIndex: Int = 0

    init(directory: URL? = nil) {
        let dir: URL
        if let directory {
            dir = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = appSupport.appendingPathComponent("The Player", isDirectory: true)
        }
        self.directory = dir
        self.filePath = dir.appendingPathComponent("library.json")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Load or recover
        if FileManager.default.fileExists(atPath: filePath.path) {
            do {
                let data = try Data(contentsOf: filePath)
                library = try JSONDecoder().decode(PlayerLibrary.self, from: data)
            } catch {
                // Corrupt — backup and start fresh
                let backup = dir.appendingPathComponent("library.json.backup")
                try? FileManager.default.copyItem(at: filePath, to: backup)
                library = PlayerLibrary()
            }
        } else {
            library = PlayerLibrary()
        }
    }

    // MARK: - Songs

    @discardableResult
    func addSong(filePath: String, title: String, artist: String, bpm: Float, duration: Float) -> SongEntry {
        if let existing = library.songByPath(filePath) {
            return existing
        }
        let song = SongEntry(filePath: filePath, title: title, artist: artist, bpm: bpm, duration: duration)
        library.songs.append(song)
        save()
        return song
    }

    func savePracticeState(songId: UUID, speed: Float, pitch: Float, position: Float, loopStart: Float?, loopEnd: Float?) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].lastSpeed = speed
        library.songs[index].lastPitch = pitch
        library.songs[index].lastPosition = position
        library.songs[index].lastLoopStart = loopStart
        library.songs[index].lastLoopEnd = loopEnd
        library.songs[index].lastOpenedAt = Date()
        save()
    }

    func incrementPracticeCount(songId: UUID) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].practiceCount += 1
        library.songs[index].lastOpenedAt = Date()
        save()
    }

    func addPracticeTime(songId: UUID, seconds: Double) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].totalPracticeTime += seconds
    }

    func relocateSong(songId: UUID, newPath: String) {
        guard let index = library.songIndex(byId: songId) else { return }
        library.songs[index].filePath = newPath
        save()
    }

    // MARK: - Setlists

    @discardableResult
    func createSetlist(name: String) -> Setlist {
        let setlist = Setlist(name: name)
        library.setlists.append(setlist)
        save()
        return setlist
    }

    func deleteSetlist(id: UUID) {
        library.setlists.removeAll(where: { $0.id == id })
        if activeSetlistId == id { activeSetlistId = nil }
        save()
    }

    func addSongToSetlist(songId: UUID, setlistId: UUID) {
        guard let index = library.setlists.firstIndex(where: { $0.id == setlistId }) else { return }
        if !library.setlists[index].songIds.contains(songId) {
            library.setlists[index].songIds.append(songId)
            library.setlists[index].updatedAt = Date()
            save()
        }
    }

    func removeSongFromSetlist(songId: UUID, setlistId: UUID) {
        guard let index = library.setlists.firstIndex(where: { $0.id == setlistId }) else { return }
        library.setlists[index].songIds.removeAll(where: { $0 == songId })
        library.setlists[index].updatedAt = Date()
        save()
    }

    func reorderSetlist(setlistId: UUID, songIds: [UUID]) {
        guard let index = library.setlists.firstIndex(where: { $0.id == setlistId }) else { return }
        library.setlists[index].songIds = songIds
        library.setlists[index].updatedAt = Date()
        save()
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        library.playlists.append(playlist)
        save()
        return playlist
    }

    func deletePlaylist(id: UUID) {
        library.playlists.removeAll(where: { $0.id == id })
        save()
    }

    func addSongToPlaylist(songId: UUID, playlistId: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if !library.playlists[index].songIds.contains(songId) {
            library.playlists[index].songIds.append(songId)
            library.playlists[index].updatedAt = Date()
            save()
        }
    }

    func removeSongFromPlaylist(songId: UUID, playlistId: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        library.playlists[index].songIds.removeAll(where: { $0 == songId })
        library.playlists[index].updatedAt = Date()
        save()
    }

    // MARK: - Setlist Playback

    func nextSetlistSong() -> SongEntry? {
        guard let setlistId = activeSetlistId,
              let setlist = library.setlists.first(where: { $0.id == setlistId }) else { return nil }
        let nextIndex = activeSetlistIndex + 1
        guard nextIndex < setlist.songIds.count else { return nil }
        activeSetlistIndex = nextIndex
        let songId = setlist.songIds[nextIndex]
        return library.song(byId: songId)
    }

    func setActiveSetlist(_ setlistId: UUID, startingAt index: Int = 0) {
        activeSetlistId = setlistId
        activeSetlistIndex = index
    }

    func clearActiveSetlist() {
        activeSetlistId = nil
        activeSetlistIndex = 0
    }

    // MARK: - Persistence

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(library)
            try data.write(to: filePath, options: .atomic)
        } catch {
            // Log silently, retry next save
            print("LibraryService: save failed — \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Create Services directory, run xcodegen, run tests**

```bash
mkdir -p ThePlayer/Services
# (move file into place)
xcodegen generate
xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Executed|FAIL)"
```
Expected: All LibraryService tests pass

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Services/LibraryService.swift ThePlayerTests/LibraryServiceTests.swift
git commit -m "feat: LibraryService — persistence, CRUD, setlist playback, auto-save"
```

---

### Task 3: Library Sidebar View

**Files:**
- Create: `ThePlayer/Views/LibrarySidebar.swift`

- [ ] **Step 1: Create LibrarySidebar**

Create `ThePlayer/Views/LibrarySidebar.swift`:

```swift
import SwiftUI

struct LibrarySidebar: View {
    @Bindable var libraryService: LibraryService
    let onSongSelect: (SongEntry) -> Void
    let onSetlistSongSelect: (SongEntry, UUID, Int) -> Void

    @State private var expandedSetlists: Set<UUID> = []
    @State private var expandedPlaylists: Set<UUID> = []
    @State private var expandedSmart: Set<String> = []
    @State private var showNewSetlistField = false
    @State private var showNewPlaylistField = false
    @State private var newSetlistName = ""
    @State private var newPlaylistName = ""

    var body: some View {
        List {
            // Recent
            Section("Recent") {
                let recent = libraryService.library.recentSongs(limit: 20)
                if recent.isEmpty {
                    Text("No songs yet")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                } else {
                    ForEach(recent) { song in
                        songRow(song)
                    }
                }
            }

            // Setlists
            Section("Setlists") {
                ForEach(libraryService.library.setlists) { setlist in
                    DisclosureGroup(isExpanded: bindingForSetlist(setlist.id)) {
                        let songs = setlist.songIds.compactMap { libraryService.library.song(byId: $0) }
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            setlistSongRow(song, setlistId: setlist.id, index: index)
                        }
                        if songs.isEmpty {
                            Text("No songs yet")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                    } label: {
                        Label("\(setlist.name) (\(setlist.songIds.count))", systemImage: "music.note.list")
                            .font(.subheadline)
                    }
                }

                if showNewSetlistField {
                    HStack {
                        TextField("Setlist name", text: $newSetlistName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .onSubmit {
                                if !newSetlistName.isEmpty {
                                    libraryService.createSetlist(name: newSetlistName)
                                    newSetlistName = ""
                                }
                                showNewSetlistField = false
                            }
                    }
                } else {
                    Button(action: { showNewSetlistField = true }) {
                        Label("New Setlist", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }

            // Playlists
            Section("Playlists") {
                ForEach(libraryService.library.playlists) { playlist in
                    DisclosureGroup(isExpanded: bindingForPlaylist(playlist.id)) {
                        let songs = playlist.songIds.compactMap { libraryService.library.song(byId: $0) }
                        ForEach(songs) { song in
                            songRow(song)
                        }
                        if songs.isEmpty {
                            Text("No songs yet")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                    } label: {
                        Label("\(playlist.name) (\(playlist.songIds.count))", systemImage: "list.bullet")
                            .font(.subheadline)
                    }
                }

                if showNewPlaylistField {
                    HStack {
                        TextField("Playlist name", text: $newPlaylistName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .onSubmit {
                                if !newPlaylistName.isEmpty {
                                    libraryService.createPlaylist(name: newPlaylistName)
                                    newPlaylistName = ""
                                }
                                showNewPlaylistField = false
                            }
                    }
                } else {
                    Button(action: { showNewPlaylistField = true }) {
                        Label("New Playlist", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }

            // Smart Playlists
            Section("Smart") {
                DisclosureGroup("Most Practiced", isExpanded: bindingForSmart("most")) {
                    ForEach(libraryService.library.mostPracticed(limit: 10)) { song in
                        songRow(song)
                    }
                }
                DisclosureGroup("Needs Work", isExpanded: bindingForSmart("needs")) {
                    ForEach(libraryService.library.needsWork(threshold: 3)) { song in
                        songRow(song)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func songRow(_ song: SongEntry) -> some View {
        Button(action: { onSongSelect(song) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(song.fileExists ? .primary : .secondary)
                    Text(song.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !song.fileExists {
                    Text("Missing")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !libraryService.library.setlists.isEmpty {
                Menu("Add to Setlist...") {
                    ForEach(libraryService.library.setlists) { setlist in
                        Button(setlist.name) {
                            libraryService.addSongToSetlist(songId: song.id, setlistId: setlist.id)
                        }
                    }
                }
            }
            if !libraryService.library.playlists.isEmpty {
                Menu("Add to Playlist...") {
                    ForEach(libraryService.library.playlists) { playlist in
                        Button(playlist.name) {
                            libraryService.addSongToPlaylist(songId: song.id, playlistId: playlist.id)
                        }
                    }
                }
            }
            if !song.fileExists {
                Button("Relocate...") {
                    relocateSong(song)
                }
            }
        }
    }

    private func setlistSongRow(_ song: SongEntry, setlistId: UUID, index: Int) -> some View {
        Button(action: { onSetlistSongSelect(song, setlistId, index) }) {
            HStack {
                Text("\(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(song.fileExists ? .primary : .secondary)
                    Text(song.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if libraryService.activeSetlistId == setlistId && libraryService.activeSetlistIndex == index {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func relocateSong(_ song: SongEntry) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav, .aiff, .mp3]
        panel.message = "Locate \(song.title)"
        if panel.runModal() == .OK, let url = panel.url {
            libraryService.relocateSong(songId: song.id, newPath: url.path)
        }
    }

    // MARK: - Expansion bindings

    private func bindingForSetlist(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedSetlists.contains(id) },
            set: { if $0 { expandedSetlists.insert(id) } else { expandedSetlists.remove(id) } }
        )
    }

    private func bindingForPlaylist(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedPlaylists.contains(id) },
            set: { if $0 { expandedPlaylists.insert(id) } else { expandedPlaylists.remove(id) } }
        )
    }

    private func bindingForSmart(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expandedSmart.contains(key) },
            set: { if $0 { expandedSmart.insert(key) } else { expandedSmart.remove(key) } }
        )
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/LibrarySidebar.swift
git commit -m "feat: library sidebar — recent, setlists, playlists, smart playlists"
```

---

### Task 4: Three-Column Layout — ContentView Rewrite

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`
- Modify: `ThePlayer/ThePlayerApp.swift`

- [ ] **Step 1: Update ThePlayerApp to create LibraryService**

In `ThePlayer/ThePlayerApp.swift`, add a new `@State` property and pass it to ContentView:

Add after `@State private var analysisService`:
```swift
    @State private var libraryService = LibraryService()
```

Update the ContentView call:
```swift
    ContentView(audioEngine: audioEngine, analysisService: analysisService, libraryService: libraryService)
```

- [ ] **Step 2: Rewrite ContentView for three-column layout**

In `ThePlayer/Views/ContentView.swift`:

Add `libraryService` parameter:
```swift
    @Bindable var libraryService: LibraryService
```

Add state for sidebar visibility:
```swift
    @State private var showLibrarySidebar = true
    @State private var showSectionsSidebar = true
```

Replace the `NavigationSplitView` body with an `HStack`-based three-column layout:

```swift
    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar — Library
            if showLibrarySidebar {
                LibrarySidebar(
                    libraryService: libraryService,
                    onSongSelect: { song in loadSongFromLibrary(song) },
                    onSetlistSongSelect: { song, setlistId, index in
                        libraryService.setActiveSetlist(setlistId, startingAt: index)
                        loadSongFromLibrary(song)
                    }
                )
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                Divider()
            }

            // Center — Player
            VStack(spacing: 0) {
                if audioEngine.state == .empty {
                    emptyState
                } else {
                    playerDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right sidebar — Song sections
            if showSectionsSidebar && audioEngine.state != .empty {
                Divider()
                SidebarView(
                    sections: analysisService.lastAnalysis?.sections ?? [],
                    bpm: analysisService.lastAnalysis?.bpm,
                    duration: audioEngine.duration,
                    sampleRate: audioEngine.sampleRate,
                    onSectionTap: { section in
                        selectedSection = section
                        let loop = LoopRegion.from(section: section)
                        loopRegion = loop
                        audioEngine.setLoop(loop)
                        audioEngine.playLoop()
                    },
                    selectedSection: $selectedSection
                )
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { showLibrarySidebar.toggle() }) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Library")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showSectionsSidebar.toggle() }) {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Sections")
            }
        }
        // ... keep existing modifiers: .onDrop, .overlay, .onChange, .onAppear, .onDisappear, .onReceive, .alert
    }
```

Remove the old `NavigationSplitView` wrapper and `SidebarView` from within the detail view. The `playerDetail` computed property stays the same but without SidebarView wrapping.

- [ ] **Step 3: Add loadSongFromLibrary helper**

Add to ContentView:

```swift
    private func loadSongFromLibrary(_ song: SongEntry) {
        guard song.fileExists else { return }
        let url = URL(fileURLWithPath: song.filePath)

        // Save current song's practice state before switching
        saveCurrentPracticeState()

        openFile(url: url)

        // Restore practice state after loading
        audioEngine.speed = song.lastSpeed
        audioEngine.pitch = song.lastPitch
        if song.lastPosition > 0 {
            audioEngine.seek(to: song.lastPosition)
        }
        if let loopStart = song.lastLoopStart, let loopEnd = song.lastLoopEnd {
            loopRegion = LoopRegion(startTime: loopStart, endTime: loopEnd)
        }

        libraryService.incrementPracticeCount(songId: song.id)
    }

    private func saveCurrentPracticeState() {
        guard let url = audioEngine.fileURL else { return }
        let path = url.path
        if let song = libraryService.library.songByPath(path) {
            libraryService.savePracticeState(
                songId: song.id,
                speed: audioEngine.speed,
                pitch: audioEngine.pitch,
                position: audioEngine.currentTime,
                loopStart: loopRegion?.startTime,
                loopEnd: loopRegion?.endTime
            )
        }
    }
```

- [ ] **Step 4: Update openFile to auto-add to library**

In the existing `openFile(url:)` method, add library registration after successful load:

```swift
    func openFile(url: URL) {
        do {
            try audioEngine.loadFile(url: url)
            selectedSection = nil
            loopRegion = nil
            loadError = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)

            // Auto-add to library
            libraryService.addSong(
                filePath: url.path,
                title: audioEngine.title,
                artist: audioEngine.artist,
                bpm: analysisService.lastAnalysis?.bpm ?? 0,
                duration: audioEngine.duration
            )

            Task {
                await analysisService.analyze(fileURL: url)
                // Update BPM in library after analysis completes
                if let bpm = analysisService.lastAnalysis?.bpm,
                   let song = libraryService.library.songByPath(url.path) {
                    libraryService.savePracticeState(
                        songId: song.id,
                        speed: audioEngine.speed,
                        pitch: audioEngine.pitch,
                        position: 0,
                        loopStart: nil,
                        loopEnd: nil
                    )
                }
            }
        } catch {
            loadError = "Could not open file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
```

- [ ] **Step 5: Save practice state on app quit**

In `ThePlayerApp.swift`, add an `onChange` or use `NSApplication` termination notification. Simplest approach — add to the WindowGroup:

```swift
        WindowGroup {
            ContentView(audioEngine: audioEngine, analysisService: analysisService, libraryService: libraryService)
                .onDisappear {
                    // Save is handled by ContentView's saveCurrentPracticeState
                }
        }
```

Actually, better to use `NSApplication.willTerminateNotification` in ContentView's `onAppear`:

Add to the `installKeyMonitor()` method or create a new onAppear block:
```swift
    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
        saveCurrentPracticeState()
    }
```

- [ ] **Step 6: Build to verify**

```bash
xcodegen generate
xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/ContentView.swift ThePlayer/ThePlayerApp.swift
git commit -m "feat: three-column layout with library sidebar, auto-save practice state"
```

---

### Task 5: Setlist Auto-Advance in Transport Bar

**Files:**
- Modify: `ThePlayer/Views/TransportBar.swift`
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Add Next button to TransportBar**

In `ThePlayer/Views/TransportBar.swift`, add a new binding:

```swift
    let isInSetlist: Bool
    let onNextInSetlist: () -> Void
```

After the A-B loop button and snap controls, add:

```swift
                if isInSetlist {
                    Button(action: onNextInSetlist) {
                        Label("Next", systemImage: "forward.end.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
```

- [ ] **Step 2: Wire TransportBar in ContentView**

Update the TransportBar call in `playerDetail`:

```swift
            TransportBar(
                audioEngine: audioEngine,
                loopRegion: $loopRegion,
                isSettingLoop: $isSettingLoop,
                snapToGrid: $snapToGrid,
                snapDivision: $snapDivision,
                isInSetlist: libraryService.activeSetlistId != nil,
                onNextInSetlist: { advanceSetlist() }
            )
```

Add the helper:

```swift
    private func advanceSetlist() {
        saveCurrentPracticeState()
        if let nextSong = libraryService.nextSetlistSong() {
            loadSongFromLibrary(nextSong)
        }
    }
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/TransportBar.swift ThePlayer/Views/ContentView.swift
git commit -m "feat: setlist auto-advance with Next button in transport bar"
```

---

### Task 6: Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

```bash
xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Executed|FAIL)"
```
Expected: All tests pass

- [ ] **Step 2: Build release**

```bash
xcodebuild -scheme ThePlayer -destination 'platform=macOS' -configuration Release build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit any fixes**

```bash
git diff --quiet || (git add -A && git commit -m "chore: final verification fixes")
```
