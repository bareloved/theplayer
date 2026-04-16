# Section Analyzer Improvements & Manual Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the positional section labeler with a repetition-aware analyzer, and add an "Edit Sections" mode that lets users fix sections by hand and persist edits in a sidecar that survives re-analysis.

**Architecture:** Three layers, mostly independent.
1. **Data layer** — add a stable `UUID` to `AudioSection`; new `UserEditsStore` writes `<hash>.user.json` sidecars; `AnalysisService` merges sidecar over cache on load.
2. **UI layer** — new `SectionEditorViewModel` owns edit state and `UndoManager`; `WaveformView` gains an `isEditingSections` mode with draggable boundary handles, a toolbar, and a label inspector.
3. **Analyzer layer** — replace SBic in `EssentiaAnalyzer.mm` with beat-synchronous chroma+MFCC features → self-similarity matrix → Foote novelty boundaries → agglomerative clustering → heuristic label assignment.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), Objective-C++ + Essentia for DSP, XCTest. Build via `xcodebuild -scheme ThePlayer test`.

**Spec:** [docs/superpowers/specs/2026-04-16-section-analyzer-improvements-and-manual-editor-design.md](../specs/2026-04-16-section-analyzer-improvements-and-manual-editor-design.md)

---

## File Map

**Create:**
- `ThePlayer/Analysis/UserEditsStore.swift` — sidecar persistence
- `ThePlayer/Models/UserEdits.swift` — `UserEdits` struct
- `ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift` — edit state + undo
- `ThePlayer/Views/SectionEditor/SectionEditorToolbar.swift` — toolbar UI
- `ThePlayer/Views/SectionEditor/SectionInspector.swift` — label/color inspector
- `ThePlayer/Views/SectionEditor/SectionBoundaryHandle.swift` — draggable handle
- `ThePlayer/Views/SectionEditor/SectionLabelPresets.swift` — preset list + color map
- `ThePlayerTests/UserEditsStoreTests.swift`
- `ThePlayerTests/SectionEditorViewModelTests.swift`
- `ThePlayerTests/AnalysisServiceMergeTests.swift`

**Modify:**
- `ThePlayer/Models/AudioSection.swift` — add `stableId: UUID`
- `ThePlayer/Models/TrackAnalysis.swift` — add `with(sections:)` helper
- `ThePlayer/Analysis/AnalysisService.swift` — merge sidecar on load; preserve sidecar on re-analysis
- `ThePlayer/Analysis/EssentiaAnalyzer.mm` — replace SBic block with new pipeline
- `ThePlayer/Views/WaveformView.swift` — add `isEditingSections` mode + handles
- `ThePlayer/Views/ContentView.swift` — wire the editor view model + toggle
- `ThePlayer/Views/TransportBar.swift` — add edit-mode toggle button
- `project.yml` (if needed for new file groups — `xcodegen generate` after)

---

## Phase A — Data Foundation

### Task A1: Add stable UUID to `AudioSection`

**Files:**
- Modify: `ThePlayer/Models/AudioSection.swift`
- Modify: `ThePlayerTests/TrackAnalysisTests.swift` (verify decode of legacy JSON without `stableId`)

**Why:** `id` is currently `"\(label)-\(startTime)"` so it changes on rename/drag. Undo/redo and selection need a stable handle. Old cached analyses must still decode.

- [ ] **Step 1: Write failing test for stable ID round-trip and legacy decode**

Append to `ThePlayerTests/TrackAnalysisTests.swift`:

```swift
func testAudioSectionHasStableIdAfterEncodeDecode() throws {
    let section = AudioSection(
        label: "Verse",
        startTime: 0, endTime: 10,
        startBeat: 0, endBeat: 16,
        colorIndex: 1
    )
    let data = try JSONEncoder().encode(section)
    let decoded = try JSONDecoder().decode(AudioSection.self, from: data)
    XCTAssertEqual(decoded.stableId, section.stableId)
}

func testAudioSectionDecodesLegacyJSONWithoutStableId() throws {
    let legacyJSON = """
    {"label":"Verse","startTime":0,"endTime":10,"startBeat":0,"endBeat":16,"colorIndex":1}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AudioSection.self, from: legacyJSON)
    XCTAssertEqual(decoded.label, "Verse")
    // stableId must be present (auto-generated)
    XCTAssertNotNil(decoded.stableId)
}
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/TrackAnalysisTests/testAudioSectionHasStableIdAfterEncodeDecode -only-testing:ThePlayerTests/TrackAnalysisTests/testAudioSectionDecodesLegacyJSONWithoutStableId`
Expected: FAIL — `stableId` does not exist.

- [ ] **Step 3: Add `stableId` to `AudioSection`**

Replace contents of `ThePlayer/Models/AudioSection.swift` with:

```swift
import SwiftUI

struct AudioSection: Identifiable, Equatable {
    let stableId: UUID
    var label: String
    var startTime: Float
    var endTime: Float
    var startBeat: Int
    var endBeat: Int
    var colorIndex: Int

    var id: UUID { stableId }
    var duration: Float { endTime - startTime }
    var barCount: Int { (endBeat - startBeat) / 4 }

    init(
        stableId: UUID = UUID(),
        label: String,
        startTime: Float,
        endTime: Float,
        startBeat: Int,
        endBeat: Int,
        colorIndex: Int
    ) {
        self.stableId = stableId
        self.label = label
        self.startTime = startTime
        self.endTime = endTime
        self.startBeat = startBeat
        self.endBeat = endBeat
        self.colorIndex = colorIndex
    }

    private static let palette: [Color] = [
        .blue, .green, .red, .yellow, .purple, .orange, .cyan, .pink
    ]

    var color: Color { Self.palette[colorIndex % Self.palette.count] }
}

extension AudioSection: Codable {
    enum CodingKeys: String, CodingKey {
        case stableId, label, startTime, endTime, startBeat, endBeat, colorIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.stableId = try c.decodeIfPresent(UUID.self, forKey: .stableId) ?? UUID()
        self.label = try c.decode(String.self, forKey: .label)
        self.startTime = try c.decode(Float.self, forKey: .startTime)
        self.endTime = try c.decode(Float.self, forKey: .endTime)
        self.startBeat = try c.decode(Int.self, forKey: .startBeat)
        self.endBeat = try c.decode(Int.self, forKey: .endBeat)
        self.colorIndex = try c.decode(Int.self, forKey: .colorIndex)
    }
}
```

Note: properties are now `var` because the editor mutates them. `id` returns `stableId` (was a computed string).

- [ ] **Step 4: Run failing tests — should now pass**

Run the same test command as Step 2.
Expected: PASS.

- [ ] **Step 5: Run full test suite and fix any breakage**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS. If `id` was used as a `String` anywhere, fix the call site to use `stableId.uuidString` or update the comparison.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Models/AudioSection.swift ThePlayerTests/TrackAnalysisTests.swift
git commit -m "feat: add stable UUID to AudioSection with legacy JSON fallback"
```

---

### Task A2: Add `TrackAnalysis.with(sections:)` helper

**Files:**
- Modify: `ThePlayer/Models/TrackAnalysis.swift`
- Modify: `ThePlayerTests/TrackAnalysisTests.swift`

- [ ] **Step 1: Write failing test**

Append to `ThePlayerTests/TrackAnalysisTests.swift`:

```swift
func testTrackAnalysisWithSectionsReplacesSectionsOnly() {
    let original = TrackAnalysis(
        bpm: 120,
        beats: [0, 0.5, 1.0],
        sections: [AudioSection(label: "A", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 0)],
        waveformPeaks: [0.1, 0.2]
    )
    let newSections = [
        AudioSection(label: "B", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 1)
    ]
    let updated = original.with(sections: newSections)
    XCTAssertEqual(updated.bpm, 120)
    XCTAssertEqual(updated.beats, [0, 0.5, 1.0])
    XCTAssertEqual(updated.waveformPeaks, [0.1, 0.2])
    XCTAssertEqual(updated.sections.first?.label, "B")
}
```

- [ ] **Step 2: Run test to confirm failure**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/TrackAnalysisTests/testTrackAnalysisWithSectionsReplacesSectionsOnly`
Expected: FAIL — `with(sections:)` does not exist.

- [ ] **Step 3: Add helper**

Replace `ThePlayer/Models/TrackAnalysis.swift` with:

```swift
import Foundation

struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]

    func with(sections: [AudioSection]) -> TrackAnalysis {
        TrackAnalysis(bpm: bpm, beats: beats, sections: sections, waveformPeaks: waveformPeaks)
    }
}
```

- [ ] **Step 4: Run test — should pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Models/TrackAnalysis.swift ThePlayerTests/TrackAnalysisTests.swift
git commit -m "feat: add TrackAnalysis.with(sections:) override helper"
```

---

### Task A3: Create `UserEdits` model

**Files:**
- Create: `ThePlayer/Models/UserEdits.swift`

- [ ] **Step 1: Write the file**

Create `ThePlayer/Models/UserEdits.swift`:

```swift
import Foundation

struct UserEdits: Codable, Equatable {
    static let currentSchemaVersion: Int = 1

    var sections: [AudioSection]
    var modifiedAt: Date
    var schemaVersion: Int

    init(sections: [AudioSection], modifiedAt: Date = Date(), schemaVersion: Int = UserEdits.currentSchemaVersion) {
        self.sections = sections
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate`
Expected: project regenerated; new file picked up under `ThePlayer/Models/`.

- [ ] **Step 3: Verify build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Models/UserEdits.swift project.yml ThePlayer.xcodeproj
git commit -m "feat: add UserEdits model with schema version"
```

---

### Task A4: Implement `UserEditsStore`

**Files:**
- Create: `ThePlayer/Analysis/UserEditsStore.swift`
- Create: `ThePlayerTests/UserEditsStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ThePlayerTests/UserEditsStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/UserEditsStoreTests`
Expected: FAIL — `UserEditsStore` does not exist.

- [ ] **Step 3: Implement `UserEditsStore`**

Create `ThePlayer/Analysis/UserEditsStore.swift`:

```swift
import Foundation
import os

final class UserEditsStore {
    private let directory: URL
    private let logger = Logger(subsystem: "com.theplayer.app", category: "UserEditsStore")

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("The Player/cache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).user.json")
    }

    func store(_ edits: UserEdits, forKey key: String) throws {
        let data = try JSONEncoder().encode(edits)
        try data.write(to: url(forKey: key), options: .atomic)
    }

    func retrieve(forKey key: String) throws -> UserEdits? {
        let fileURL = url(forKey: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let edits = try JSONDecoder().decode(UserEdits.self, from: data)
        guard edits.schemaVersion <= UserEdits.currentSchemaVersion else {
            logger.warning("Ignoring user edits with unknown schema version \(edits.schemaVersion) for key \(key)")
            return nil
        }
        return edits
    }

    func delete(forKey key: String) throws {
        let fileURL = url(forKey: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func exists(forKey key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forKey: key).path)
    }
}
```

- [ ] **Step 4: Add to project**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate`

- [ ] **Step 5: Run tests — should pass**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/UserEditsStoreTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Analysis/UserEditsStore.swift ThePlayerTests/UserEditsStoreTests.swift project.yml ThePlayer.xcodeproj
git commit -m "feat: add UserEditsStore for sidecar persistence of section edits"
```

---

### Task A5: Wire `UserEditsStore` into `AnalysisService` (merge on load)

**Files:**
- Modify: `ThePlayer/Analysis/AnalysisService.swift`
- Create: `ThePlayerTests/AnalysisServiceMergeTests.swift`

- [ ] **Step 1: Write failing test**

Create `ThePlayerTests/AnalysisServiceMergeTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to confirm failure**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/AnalysisServiceMergeTests`
Expected: FAIL — `mergeCachedAnalysis` does not exist.

- [ ] **Step 3: Modify `AnalysisService` to merge sidecar**

Replace `ThePlayer/Analysis/AnalysisService.swift` with:

```swift
import Foundation
import Observation

struct EssentiaAnalyzerSwift: TrackAnalyzerProtocol {
    func analyze(fileURL: URL, progress: @escaping (Float) -> Void) async throws -> TrackAnalysis {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                progress(0.1)

                let analyzer = EssentiaAnalyzerObjC()
                do {
                    let result = try analyzer.analyzeFile(atPath: fileURL.path)

                    progress(0.8)

                    let sections = result.sections.enumerated().map { _, section in
                        AudioSection(
                            label: section.label,
                            startTime: section.startTime,
                            endTime: section.endTime,
                            startBeat: Int(section.startBeat),
                            endBeat: Int(section.endBeat),
                            colorIndex: Int(section.colorIndex)
                        )
                    }

                    let beats = result.beats.map { $0.floatValue }
                    let peaks = (try? WaveformExtractor.extractPeaks(from: fileURL)) ?? []

                    progress(1.0)

                    let analysis = TrackAnalysis(
                        bpm: result.bpm,
                        beats: beats,
                        sections: sections,
                        waveformPeaks: peaks
                    )
                    continuation.resume(returning: analysis)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@Observable
final class AnalysisService {
    private(set) var isAnalyzing = false
    private(set) var progress: Float = 0
    private(set) var lastAnalysis: TrackAnalysis?
    private(set) var lastAnalysisKey: String?
    private(set) var lastFileURL: URL?
    private(set) var hasUserEditsForCurrent = false
    private(set) var analysisError: String?

    private let analyzer: TrackAnalyzerProtocol
    private let cache: AnalysisCache
    let userEdits: UserEditsStore

    init(
        analyzer: TrackAnalyzerProtocol = EssentiaAnalyzerSwift(),
        cache: AnalysisCache = AnalysisCache(),
        userEdits: UserEditsStore = UserEditsStore()
    ) {
        self.analyzer = analyzer
        self.cache = cache
        self.userEdits = userEdits
    }

    static func mergeCachedAnalysis(_ analysis: TrackAnalysis, userEdits: UserEdits?) -> TrackAnalysis {
        guard let edits = userEdits, !edits.sections.isEmpty else { return analysis }
        return analysis.with(sections: edits.sections)
    }

    func analyze(fileURL: URL) async {
        isAnalyzing = true
        progress = 0
        analysisError = nil
        lastFileURL = fileURL

        do {
            let key = try AnalysisCache.fileHash(for: fileURL)
            lastAnalysisKey = key

            if let cached = try cache.retrieve(forKey: key) {
                let edits = try userEdits.retrieve(forKey: key)
                hasUserEditsForCurrent = edits != nil
                lastAnalysis = Self.mergeCachedAnalysis(cached, userEdits: edits)
                progress = 1.0
                isAnalyzing = false
                return
            }

            let result = try await analyzer.analyze(fileURL: fileURL) { [weak self] p in
                Task { @MainActor in
                    self?.progress = p
                }
            }

            try cache.store(result, forKey: key)
            let edits = try userEdits.retrieve(forKey: key)
            hasUserEditsForCurrent = edits != nil
            lastAnalysis = Self.mergeCachedAnalysis(result, userEdits: edits)
        } catch {
            analysisError = error.localizedDescription
            lastAnalysis = nil
        }

        isAnalyzing = false
    }

    /// Persist edited sections for the currently loaded track.
    func saveUserEdits(_ sections: [AudioSection]) throws {
        guard let key = lastAnalysisKey else { return }
        try userEdits.store(UserEdits(sections: sections), forKey: key)
        hasUserEditsForCurrent = true
    }

    /// Discard sidecar and reload analyzer output for the currently loaded track.
    func discardUserEdits() async {
        guard let key = lastAnalysisKey, let cached = try? cache.retrieve(forKey: key) else { return }
        try? userEdits.delete(forKey: key)
        hasUserEditsForCurrent = false
        lastAnalysis = cached
    }
}
```

- [ ] **Step 4: Run merge tests — should pass**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/AnalysisServiceMergeTests`
Expected: PASS.

- [ ] **Step 5: Run full suite to catch regressions**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Analysis/AnalysisService.swift ThePlayerTests/AnalysisServiceMergeTests.swift
git commit -m "feat: merge user edits sidecar over cached analysis on load"
```

---

### Task A6: Re-analysis preserves sidecar (no clobber)

**Files:**
- Modify: `ThePlayerTests/AnalysisServiceMergeTests.swift`

`AnalysisService.analyze` already merges on load — but if the cache exists it returns early without re-running. We need a separate explicit re-analyze entry point that runs even with a cached entry, replaces the cache, and preserves the sidecar.

- [ ] **Step 1: Add failing test for `reanalyze`**

Append to `ThePlayerTests/AnalysisServiceMergeTests.swift`:

```swift
final class FakeAnalyzer: TrackAnalyzerProtocol {
    var nextResult: TrackAnalysis
    init(nextResult: TrackAnalysis) { self.nextResult = nextResult }
    func analyze(fileURL: URL, progress: @escaping (Float) -> Void) async throws -> TrackAnalysis {
        progress(1.0)
        return nextResult
    }
}

func testReanalyzePreservesUserEditsAndUpdatesCache() async throws {
    let key = "preserve-key"
    let stale = TrackAnalysis(bpm: 100, beats: [], sections: [
        AudioSection(label: "Old", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 0)
    ], waveformPeaks: [])
    try cache.store(stale, forKey: key)
    try userEdits.store(UserEdits(sections: [
        AudioSection(label: "Mine", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 2)
    ]), forKey: key)

    let fresh = TrackAnalysis(bpm: 130, beats: [], sections: [
        AudioSection(label: "New", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 1)
    ], waveformPeaks: [])
    let service = AnalysisService(
        analyzer: FakeAnalyzer(nextResult: fresh),
        cache: cache,
        userEdits: userEdits
    )

    try await service.reanalyze(key: key, fileURL: URL(fileURLWithPath: "/dev/null"))

    // Cache replaced
    XCTAssertEqual(try cache.retrieve(forKey: key)?.bpm, 130)
    // Sidecar still present and applied
    XCTAssertEqual(service.lastAnalysis?.sections.first?.label, "Mine")
    XCTAssertTrue(service.hasUserEditsForCurrent)
}
```

- [ ] **Step 2: Run test to confirm failure**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/AnalysisServiceMergeTests/testReanalyzePreservesUserEditsAndUpdatesCache`
Expected: FAIL — `reanalyze(key:fileURL:)` does not exist.

- [ ] **Step 3: Add `reanalyze` to `AnalysisService`**

In `ThePlayer/Analysis/AnalysisService.swift`, add inside `AnalysisService`:

```swift
func reanalyze(key providedKey: String? = nil, fileURL: URL) async throws {
    isAnalyzing = true
    progress = 0
    analysisError = nil
    lastFileURL = fileURL

    let key: String
    if let providedKey { key = providedKey }
    else { key = try AnalysisCache.fileHash(for: fileURL) }
    lastAnalysisKey = key

    let result = try await analyzer.analyze(fileURL: fileURL) { [weak self] p in
        Task { @MainActor in self?.progress = p }
    }
    try cache.store(result, forKey: key)
    let edits = try userEdits.retrieve(forKey: key)
    hasUserEditsForCurrent = edits != nil
    lastAnalysis = Self.mergeCachedAnalysis(result, userEdits: edits)
    isAnalyzing = false
}
```

- [ ] **Step 4: Run test — should pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Analysis/AnalysisService.swift ThePlayerTests/AnalysisServiceMergeTests.swift
git commit -m "feat: add reanalyze() that preserves user edits sidecar"
```

---

## Phase B — Editor State & View Model

### Task B1: Section label presets

**Files:**
- Create: `ThePlayer/Views/SectionEditor/SectionLabelPresets.swift`

- [ ] **Step 1: Create file**

```swift
import SwiftUI

enum SectionLabelPresets {
    /// Common section labels in display order.
    static let labels: [String] = [
        "Intro", "Verse", "Pre-Chorus", "Chorus",
        "Bridge", "Solo", "Breakdown", "Drop", "Outro"
    ]

    /// Default color index for known labels. Mirrors AudioSection.palette indices.
    /// Returns nil for unknown labels (caller should keep current colorIndex).
    static func defaultColorIndex(for label: String) -> Int? {
        switch label {
        case "Intro":      return 0  // blue
        case "Verse":      return 1  // green
        case "Pre-Chorus": return 5  // orange
        case "Chorus":     return 2  // red
        case "Bridge":     return 3  // yellow
        case "Solo":       return 4  // purple
        case "Breakdown":  return 6  // cyan
        case "Drop":       return 7  // pink
        case "Outro":      return 0  // blue
        default:           return nil
        }
    }
}
```

- [ ] **Step 2: Add to project**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate`

- [ ] **Step 3: Verify build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/SectionEditor/SectionLabelPresets.swift project.yml ThePlayer.xcodeproj
git commit -m "feat: add section label presets and color defaults"
```

---

### Task B2: `SectionEditorViewModel` — core mutations

**Files:**
- Create: `ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift`
- Create: `ThePlayerTests/SectionEditorViewModelTests.swift`

This is the brain of the editor. It owns the working copy of `[AudioSection]`, performs add/delete/rename/move/recolor with invariants, drives an `UndoManager`, and notifies a sink (the `AnalysisService`) on commit.

Per spec: min section length is 1 beat; first section starts at 0; last section ends at duration; total time coverage preserved; no gaps; no overlaps. Snap to nearest beat from `beats: [Float]`.

- [ ] **Step 1: Write failing tests**

Create `ThePlayerTests/SectionEditorViewModelTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class SectionEditorViewModelTests: XCTestCase {

    private func makeSections() -> [AudioSection] {
        [
            AudioSection(label: "Intro",  startTime: 0,  endTime: 10, startBeat: 0,  endBeat: 16, colorIndex: 0),
            AudioSection(label: "Verse",  startTime: 10, endTime: 30, startBeat: 16, endBeat: 48, colorIndex: 1),
            AudioSection(label: "Chorus", startTime: 30, endTime: 50, startBeat: 48, endBeat: 80, colorIndex: 2),
        ]
    }

    private func makeBeats() -> [Float] {
        // 0.5s spacing: 100 beats covering 0..50s
        (0..<100).map { Float($0) * 0.5 }
    }

    private func makeVM() -> SectionEditorViewModel {
        SectionEditorViewModel(
            sections: makeSections(),
            beats: makeBeats(),
            duration: 50
        )
    }

    func testRenameUpdatesLabel() {
        let vm = makeVM()
        vm.rename(sectionId: vm.sections[1].stableId, to: "Pre-Chorus")
        XCTAssertEqual(vm.sections[1].label, "Pre-Chorus")
    }

    func testMoveBoundarySnapsToBeatAndUpdatesAdjacentSections() {
        let vm = makeVM()
        // Boundary between section 0 and 1 is at 10s. Move to ~12.3s → snaps to 12.5s (a beat).
        vm.moveBoundary(beforeSectionId: vm.sections[1].stableId, toTime: 12.3, snapToBeat: true)
        XCTAssertEqual(vm.sections[0].endTime, 12.5)
        XCTAssertEqual(vm.sections[1].startTime, 12.5)
    }

    func testMoveBoundaryRespectsMinimumOneBeatLength() {
        let vm = makeVM()
        // Try to drag boundary past adjacent boundary — should clamp to leave >= 1 beat (0.5s)
        vm.moveBoundary(beforeSectionId: vm.sections[1].stableId, toTime: 100, snapToBeat: false)
        XCTAssertLessThan(vm.sections[0].endTime, vm.sections[1].endTime)
        XCTAssertGreaterThanOrEqual(vm.sections[1].endTime - vm.sections[1].startTime, 0.5)
    }

    func testCannotMoveOuterEdges() {
        let vm = makeVM()
        let firstId = vm.sections[0].stableId
        // Attempt to move boundary "before" the first section is a no-op
        vm.moveBoundary(beforeSectionId: firstId, toTime: 5, snapToBeat: false)
        XCTAssertEqual(vm.sections[0].startTime, 0)
    }

    func testAddSplitsSectionAtTime() {
        let vm = makeVM()
        // Split Verse (10..30) at t=20 → Verse (10..20), "Section" (20..30)
        vm.addSplit(inSectionId: vm.sections[1].stableId, atTime: 20, snapToBeat: true)
        XCTAssertEqual(vm.sections.count, 4)
        XCTAssertEqual(vm.sections[1].endTime, 20)
        XCTAssertEqual(vm.sections[2].startTime, 20)
        XCTAssertEqual(vm.sections[2].label, "Section")
        // Total coverage preserved
        XCTAssertEqual(vm.sections.first?.startTime, 0)
        XCTAssertEqual(vm.sections.last?.endTime, 50)
    }

    func testDeleteMergesIntoPreviousNeighbor() {
        let vm = makeVM()
        let chorusId = vm.sections[2].stableId
        vm.delete(sectionId: chorusId)
        XCTAssertEqual(vm.sections.count, 2)
        XCTAssertEqual(vm.sections[1].label, "Verse")
        XCTAssertEqual(vm.sections[1].endTime, 50) // absorbed Chorus range
    }

    func testDeleteFirstMergesIntoNext() {
        let vm = makeVM()
        let introId = vm.sections[0].stableId
        vm.delete(sectionId: introId)
        XCTAssertEqual(vm.sections.count, 2)
        XCTAssertEqual(vm.sections[0].label, "Verse")
        XCTAssertEqual(vm.sections[0].startTime, 0)
    }

    func testCannotDeleteLastRemainingSection() {
        let vm = SectionEditorViewModel(
            sections: [AudioSection(label: "Only", startTime: 0, endTime: 50, startBeat: 0, endBeat: 80, colorIndex: 0)],
            beats: makeBeats(),
            duration: 50
        )
        vm.delete(sectionId: vm.sections[0].stableId)
        XCTAssertEqual(vm.sections.count, 1)
    }

    func testRecolorUpdatesColorIndex() {
        let vm = makeVM()
        vm.recolor(sectionId: vm.sections[0].stableId, colorIndex: 5)
        XCTAssertEqual(vm.sections[0].colorIndex, 5)
    }

    func testRenameToKnownLabelAutoUpdatesColorWhenNotUserOverridden() {
        let vm = makeVM()
        let id = vm.sections[1].stableId  // Verse, colorIndex 1
        vm.rename(sectionId: id, to: "Chorus")
        XCTAssertEqual(vm.sections[1].colorIndex, 2)  // Chorus → red(2)
    }

    func testRenameDoesNotOverrideManualColorThisSession() {
        let vm = makeVM()
        let id = vm.sections[1].stableId
        vm.recolor(sectionId: id, colorIndex: 7)
        vm.rename(sectionId: id, to: "Chorus")
        XCTAssertEqual(vm.sections[1].colorIndex, 7)
    }

    func testReorderSwapsLabelAndColorOnly() {
        let vm = makeVM()
        let aId = vm.sections[1].stableId
        vm.reorder(sectionId: aId, direction: .right)
        // Label/color of original sections[1] now at index 2; times unchanged for both.
        XCTAssertEqual(vm.sections[1].label, "Chorus")
        XCTAssertEqual(vm.sections[2].label, "Verse")
        XCTAssertEqual(vm.sections[1].startTime, 10)
        XCTAssertEqual(vm.sections[2].startTime, 30)
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/SectionEditorViewModelTests`
Expected: FAIL — `SectionEditorViewModel` does not exist.

- [ ] **Step 3: Implement `SectionEditorViewModel`**

Create `ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift`:

```swift
import SwiftUI
import Observation

@Observable
final class SectionEditorViewModel {
    enum ReorderDirection { case left, right }

    private(set) var sections: [AudioSection]
    private(set) var manualColorOverrides: Set<UUID> = []  // session-only

    let beats: [Float]
    let duration: Float

    /// Called whenever sections mutate; consumer persists.
    var onChange: (([AudioSection]) -> Void)?

    let undoManager = UndoManager()

    init(sections: [AudioSection], beats: [Float], duration: Float) {
        self.sections = sections
        self.beats = beats
        self.duration = duration
    }

    // MARK: - Mutations

    func rename(sectionId: UUID, to newLabel: String) {
        guard let idx = sections.firstIndex(where: { $0.stableId == sectionId }) else { return }
        let prev = sections[idx]
        applyChange(undoLabel: "Rename Section") {
            self.sections[idx].label = newLabel
            // Auto-update color if label is known AND user hasn't manually picked a color
            if !self.manualColorOverrides.contains(sectionId),
               let defaultColor = SectionLabelPresets.defaultColorIndex(for: newLabel) {
                self.sections[idx].colorIndex = defaultColor
            }
        } undo: {
            self.sections[idx] = prev
        }
    }

    func recolor(sectionId: UUID, colorIndex: Int) {
        guard let idx = sections.firstIndex(where: { $0.stableId == sectionId }) else { return }
        let prev = sections[idx].colorIndex
        let prevManual = manualColorOverrides.contains(sectionId)
        applyChange(undoLabel: "Change Section Color") {
            self.sections[idx].colorIndex = colorIndex
            self.manualColorOverrides.insert(sectionId)
        } undo: {
            self.sections[idx].colorIndex = prev
            if !prevManual { self.manualColorOverrides.remove(sectionId) }
        }
    }

    func moveBoundary(beforeSectionId: UUID, toTime requested: Float, snapToBeat: Bool) {
        guard let idx = sections.firstIndex(where: { $0.stableId == beforeSectionId }), idx > 0 else { return }
        let leftPrev = sections[idx - 1]
        let rightPrev = sections[idx]

        let snapped = snapToBeat ? Self.snapToNearestBeat(time: requested, beats: beats) : requested
        // Constraints: at least 1 beat (or 0.5s fallback) on each side
        let minLen: Float = beats.count >= 2 ? Float(beats[1] - beats[0]) : 0.5
        let lowerBound = leftPrev.startTime + minLen
        let upperBound = rightPrev.endTime - minLen
        let clamped = max(lowerBound, min(upperBound, snapped))

        applyChange(undoLabel: "Move Boundary") {
            self.sections[idx - 1].endTime = clamped
            self.sections[idx].startTime = clamped
            self.recomputeBeatsForRange(idx - 1 ... idx)
        } undo: {
            self.sections[idx - 1] = leftPrev
            self.sections[idx] = rightPrev
        }
    }

    func addSplit(inSectionId: UUID, atTime requested: Float, snapToBeat: Bool) {
        guard let idx = sections.firstIndex(where: { $0.stableId == inSectionId }) else { return }
        let original = sections[idx]
        let snapped = snapToBeat ? Self.snapToNearestBeat(time: requested, beats: beats) : requested
        let minLen: Float = beats.count >= 2 ? Float(beats[1] - beats[0]) : 0.5
        let lower = original.startTime + minLen
        let upper = original.endTime - minLen
        guard upper > lower else { return }
        let cut = max(lower, min(upper, snapped))

        let leftId = original.stableId
        let newRight = AudioSection(
            label: "Section",
            startTime: cut,
            endTime: original.endTime,
            startBeat: original.startBeat,
            endBeat: original.endBeat,
            colorIndex: 0
        )

        applyChange(undoLabel: "Add Section") {
            var leftEdited = original
            leftEdited.endTime = cut
            self.sections[idx] = leftEdited
            self.sections.insert(newRight, at: idx + 1)
            self.recomputeBeatsForRange(idx ... idx + 1)
            _ = leftId
        } undo: {
            self.sections.remove(at: idx + 1)
            self.sections[idx] = original
        }
    }

    func delete(sectionId: UUID) {
        guard sections.count > 1,
              let idx = sections.firstIndex(where: { $0.stableId == sectionId }) else { return }
        let removed = sections[idx]
        if idx > 0 {
            let neighbor = sections[idx - 1]
            applyChange(undoLabel: "Delete Section") {
                self.sections[idx - 1].endTime = removed.endTime
                self.sections.remove(at: idx)
                self.recomputeBeatsForRange((idx - 1) ... (idx - 1))
            } undo: {
                self.sections[idx - 1] = neighbor
                self.sections.insert(removed, at: idx)
            }
        } else {
            let neighbor = sections[idx + 1]
            applyChange(undoLabel: "Delete Section") {
                self.sections[idx + 1].startTime = removed.startTime
                self.sections.remove(at: idx)
                self.recomputeBeatsForRange(idx ... idx)
            } undo: {
                self.sections[idx + 1] = neighbor
                self.sections.insert(removed, at: idx)
            }
        }
    }

    func reorder(sectionId: UUID, direction: ReorderDirection) {
        guard let idx = sections.firstIndex(where: { $0.stableId == sectionId }) else { return }
        let other: Int
        switch direction {
        case .left:  other = idx - 1
        case .right: other = idx + 1
        }
        guard sections.indices.contains(other) else { return }

        let aPrev = sections[idx]
        let bPrev = sections[other]

        applyChange(undoLabel: "Reorder Section") {
            // Swap label, colorIndex, and stableId — keep time ranges in place.
            self.sections[idx].label = bPrev.label
            self.sections[idx].colorIndex = bPrev.colorIndex
            self.sections[other].label = aPrev.label
            self.sections[other].colorIndex = aPrev.colorIndex
        } undo: {
            self.sections[idx] = aPrev
            self.sections[other] = bPrev
        }
    }

    func replaceAll(with newSections: [AudioSection]) {
        let prev = sections
        applyChange(undoLabel: "Reset Sections") {
            self.sections = newSections
            self.manualColorOverrides.removeAll()
        } undo: {
            self.sections = prev
        }
    }

    // MARK: - Helpers

    static func snapToNearestBeat(time: Float, beats: [Float]) -> Float {
        guard !beats.isEmpty else { return time }
        return beats.min(by: { abs($0 - time) < abs($1 - time) }) ?? time
    }

    private func recomputeBeatsForRange(_ range: ClosedRange<Int>) {
        for i in range where sections.indices.contains(i) {
            let s = sections[i]
            var startBeat = 0
            var endBeat = 0
            for (b, t) in beats.enumerated() {
                if t <= s.startTime + 0.05 { startBeat = b }
                if t <= s.endTime + 0.05 { endBeat = b }
            }
            sections[i].startBeat = startBeat
            sections[i].endBeat = endBeat
        }
    }

    private func applyChange(undoLabel: String, _ action: () -> Void, undo: @escaping () -> Void) {
        action()
        onChange?(sections)
        undoManager.registerUndo(withTarget: self) { vm in
            undo()
            vm.onChange?(vm.sections)
            // Register redo
            vm.applyChange(undoLabel: undoLabel, action, undo: undo)
        }
        undoManager.setActionName(undoLabel)
    }
}
```

- [ ] **Step 4: Add to project**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate`

- [ ] **Step 5: Run tests — should pass**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/SectionEditorViewModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift ThePlayerTests/SectionEditorViewModelTests.swift project.yml ThePlayer.xcodeproj
git commit -m "feat: add SectionEditorViewModel with undo, snap, and invariants"
```

---

### Task B3: Undo / redo round-trip test

**Files:**
- Modify: `ThePlayerTests/SectionEditorViewModelTests.swift`

- [ ] **Step 1: Add failing tests for undo/redo**

Append to `ThePlayerTests/SectionEditorViewModelTests.swift`:

```swift
func testUndoRevertsRename() {
    let vm = makeVM()
    let id = vm.sections[1].stableId
    let originalLabel = vm.sections[1].label
    vm.rename(sectionId: id, to: "Pre-Chorus")
    vm.undoManager.undo()
    XCTAssertEqual(vm.sections[1].label, originalLabel)
}

func testRedoReappliesRename() {
    let vm = makeVM()
    let id = vm.sections[1].stableId
    vm.rename(sectionId: id, to: "Pre-Chorus")
    vm.undoManager.undo()
    vm.undoManager.redo()
    XCTAssertEqual(vm.sections[1].label, "Pre-Chorus")
}

func testUndoRevertsDelete() {
    let vm = makeVM()
    let id = vm.sections[2].stableId
    vm.delete(sectionId: id)
    XCTAssertEqual(vm.sections.count, 2)
    vm.undoManager.undo()
    XCTAssertEqual(vm.sections.count, 3)
    XCTAssertEqual(vm.sections[2].label, "Chorus")
}

func testOnChangeFiresAfterMutationAndUndo() {
    let vm = makeVM()
    var fireCount = 0
    vm.onChange = { _ in fireCount += 1 }
    vm.rename(sectionId: vm.sections[0].stableId, to: "X")
    vm.undoManager.undo()
    XCTAssertEqual(fireCount, 2)
}
```

- [ ] **Step 2: Run — all should pass already (implementation in B2 covered this)**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/SectionEditorViewModelTests`
Expected: PASS. If any fail, debug and fix the `applyChange` / undo registration logic — common cause is the redo closure capturing a stale state; verify the undo block re-registers the redo action.

- [ ] **Step 3: Commit**

```bash
git add ThePlayerTests/SectionEditorViewModelTests.swift
git commit -m "test: cover undo/redo round-trip in SectionEditorViewModel"
```

---

## Phase C — Editor UI

### Task C1: Section inspector view (label + color)

**Files:**
- Create: `ThePlayer/Views/SectionEditor/SectionInspector.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

struct SectionInspector: View {
    @Bindable var viewModel: SectionEditorViewModel
    let selectedSectionId: UUID?
    let onLabelCommit: (String) -> Void
    let onColorPick: (Int) -> Void

    @State private var draftLabel: String = ""

    private var section: AudioSection? {
        guard let id = selectedSectionId else { return nil }
        return viewModel.sections.first(where: { $0.stableId == id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Section")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let section {
                HStack {
                    TextField("Label", text: $draftLabel, onCommit: {
                        onLabelCommit(draftLabel)
                    })
                    .textFieldStyle(.roundedBorder)

                    Menu {
                        ForEach(SectionLabelPresets.labels, id: \.self) { preset in
                            Button(preset) {
                                draftLabel = preset
                                onLabelCommit(preset)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .onAppear { draftLabel = section.label }
                .onChange(of: section.stableId) { _, _ in draftLabel = section.label }

                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { idx in
                        Circle()
                            .fill(colorForIndex(idx))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white, lineWidth: section.colorIndex == idx ? 2 : 0)
                            )
                            .onTapGesture { onColorPick(idx) }
                    }
                }

                Text("\(formatTime(section.startTime)) – \(formatTime(section.endTime))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            } else {
                Text("Select a section to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func colorForIndex(_ idx: Int) -> Color {
        let palette: [Color] = [.blue, .green, .red, .yellow, .purple, .orange, .cyan, .pink]
        return palette[idx % palette.count]
    }

    private func formatTime(_ s: Float) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return "\(m):\(String(format: "%02d", sec))"
    }
}
```

- [ ] **Step 2: Add to project + build**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate && xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/SectionEditor/SectionInspector.swift project.yml ThePlayer.xcodeproj
git commit -m "feat: add SectionInspector with label autocomplete and color swatches"
```

---

### Task C2: Editor toolbar

**Files:**
- Create: `ThePlayer/Views/SectionEditor/SectionEditorToolbar.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

struct SectionEditorToolbar: View {
    @Bindable var viewModel: SectionEditorViewModel
    let canDelete: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                Label("Add", systemImage: "plus")
            }
            Button(action: onDelete) {
                Label("Delete", systemImage: "minus")
            }
            .disabled(!canDelete)

            Divider().frame(height: 16)

            Button(action: { viewModel.undoManager.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.undoManager.canUndo)
            .help("Undo")

            Button(action: { viewModel.undoManager.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.undoManager.canRedo)
            .help("Redo")

            Divider().frame(height: 16)

            Button(action: onReset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .help("Revert all section edits to analyzer output")

            Spacer()

            Button(action: onDone) {
                Label("Done", systemImage: "checkmark")
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: Add to project + build**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate && xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/SectionEditor/SectionEditorToolbar.swift project.yml ThePlayer.xcodeproj
git commit -m "feat: add SectionEditorToolbar with add/delete/undo/redo/reset/done"
```

---

### Task C3: Boundary handle overlay

**Files:**
- Create: `ThePlayer/Views/SectionEditor/SectionBoundaryHandle.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

/// A draggable vertical handle positioned at a section boundary.
/// `xPosition` is the current pixel x; the parent maps drag-translation back to time.
struct SectionBoundaryHandle: View {
    let xPosition: CGFloat
    let height: CGFloat
    let isHovered: Bool
    let onDragChanged: (CGFloat) -> Void  // delta in pixels from drag start
    let onDragEnded: () -> Void

    @State private var dragStartX: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.white.opacity(isHovered ? 0.95 : 0.8))
            .frame(width: 3, height: height)
            .overlay(
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(radius: 2)
                    .offset(y: -height / 2 + 6)
            )
            .contentShape(Rectangle().size(width: 12, height: height))
            .offset(x: xPosition - 1.5)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartX == nil { dragStartX = value.startLocation.x }
                        let delta = value.location.x - (dragStartX ?? value.startLocation.x)
                        onDragChanged(delta)
                    }
                    .onEnded { _ in
                        dragStartX = nil
                        onDragEnded()
                    }
            )
            .onHover { _ in
                NSCursor.resizeLeftRight.set()
            }
    }
}
```

- [ ] **Step 2: Add to project + build**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate && xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/SectionEditor/SectionBoundaryHandle.swift project.yml ThePlayer.xcodeproj
git commit -m "feat: add SectionBoundaryHandle drag overlay"
```

---

### Task C4: Wire edit mode into `WaveformView`

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift`

The waveform needs to (a) accept an optional `editorViewModel`, (b) when active: draw boundary handles, suppress seek-on-tap to instead select a section, and dim the rest of the UI.

- [ ] **Step 1: Add edit-mode props to `WaveformView`**

In `ThePlayer/Views/WaveformView.swift`, add new properties to the struct (after `onLoopPointSet`):

```swift
let editorViewModel: SectionEditorViewModel?
let selectedSectionId: UUID?
let onSelectSection: ((UUID?) -> Void)?
```

Update `init` and all call sites to pass `editorViewModel: nil, selectedSectionId: nil, onSelectSection: nil` by default. (You'll wire them in C5.)

- [ ] **Step 2: Add boundary-handle overlay**

In the `ZStack(alignment: .leading)` inside `body`, after `playhead(...)` add:

```swift
if let vm = editorViewModel {
    boundaryHandles(viewModel: vm, width: totalWidth, height: height)
}
```

Then add a private function:

```swift
@ViewBuilder
private func boundaryHandles(viewModel vm: SectionEditorViewModel, width: CGFloat, height: CGFloat) -> some View {
    // One handle per inner boundary (between section i and i+1)
    ForEach(Array(vm.sections.enumerated()), id: \.element.stableId) { idx, section in
        if idx > 0 {
            let x = CGFloat(section.startTime / duration) * width
            SectionBoundaryHandle(
                xPosition: x,
                height: height,
                isHovered: false,
                onDragChanged: { delta in
                    let timeDelta = Float(delta / width) * duration
                    let newTime = section.startTime + timeDelta
                    let snap = !NSEvent.modifierFlags.contains(.option)
                    vm.moveBoundary(beforeSectionId: section.stableId, toTime: newTime, snapToBeat: snap)
                },
                onDragEnded: { /* persistence triggered via onChange */ }
            )
        }
    }
}
```

- [ ] **Step 3: Replace tap behavior when in edit mode**

Find the `.onTapGesture { location in ... }` block. Replace its body with:

```swift
.onTapGesture { location in
    let fraction = Float(location.x / totalWidth)
    let time = fraction * duration
    if let onSelectSection = onSelectSection, editorViewModel != nil {
        let hit = sections.first(where: { time >= $0.startTime && time < $0.endTime })
        onSelectSection(hit?.stableId)
        return
    }
    if isSettingLoop {
        onLoopPointSet(time)
    } else {
        onSeek(time)
    }
}
```

- [ ] **Step 4: Add selection outline in `sectionBands`**

Replace `sectionBands` with:

```swift
private func sectionBands(width: CGFloat, height: CGFloat) -> some View {
    HStack(spacing: 0) {
        ForEach(sections) { section in
            let sectionWidth = CGFloat((section.endTime - section.startTime) / duration) * width
            let isSelected = section.stableId == selectedSectionId
            Rectangle()
                .fill(section.color.opacity(isSelected ? 0.25 : 0.1))
                .overlay(
                    Rectangle()
                        .strokeBorder(section.color, lineWidth: isSelected ? 2 : 0)
                )
                .frame(width: sectionWidth, height: height)
        }
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. If existing call sites break (`ContentView` constructs `WaveformView`), update them to pass `editorViewModel: nil, selectedSectionId: nil, onSelectSection: nil` for now.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift ThePlayer/Views/ContentView.swift
git commit -m "feat: add edit-mode overlay and selection to WaveformView"
```

---

### Task C5: Wire edit mode into `ContentView` + transport toggle

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`
- Modify: `ThePlayer/Views/TransportBar.swift`

- [ ] **Step 1: Add edit-mode state to `ContentView`**

In `ContentView`, add near the other `@State` declarations:

```swift
@State private var sectionEditor: SectionEditorViewModel?
@State private var selectedSectionForEdit: UUID?
@State private var showResetConfirm = false
```

Add a helper:

```swift
private func enterSectionEditor() {
    guard let analysis = analysisService.lastAnalysis else { return }
    let vm = SectionEditorViewModel(
        sections: analysis.sections,
        beats: analysis.beats,
        duration: Float(audioEngine.duration)
    )
    vm.onChange = { [weak analysisService] sections in
        try? analysisService?.saveUserEdits(sections)
    }
    sectionEditor = vm
    selectedSectionForEdit = nil
}

private func exitSectionEditor() {
    sectionEditor = nil
    selectedSectionForEdit = nil
}
```

- [ ] **Step 2: Pass editor view model + overlays to `WaveformView` in `ContentView`**

Find the `WaveformView(...)` construction and:
- Pass `editorViewModel: sectionEditor`
- Pass `selectedSectionId: selectedSectionForEdit`
- Pass `onSelectSection: { selectedSectionForEdit = $0 }`

Wrap the waveform in a `ZStack` overlay so the toolbar + inspector appear above when editing:

```swift
ZStack(alignment: .topTrailing) {
    WaveformView(... existing args ..., editorViewModel: sectionEditor, selectedSectionId: selectedSectionForEdit, onSelectSection: { selectedSectionForEdit = $0 })

    if let vm = sectionEditor {
        VStack(alignment: .trailing, spacing: 8) {
            SectionEditorToolbar(
                viewModel: vm,
                canDelete: selectedSectionForEdit != nil && vm.sections.count > 1,
                onAdd: {
                    let id = selectedSectionForEdit ?? vm.sections.first(where: {
                        Float(audioEngine.currentTime) >= $0.startTime && Float(audioEngine.currentTime) < $0.endTime
                    })?.stableId
                    if let id { vm.addSplit(inSectionId: id, atTime: Float(audioEngine.currentTime), snapToBeat: true) }
                },
                onDelete: {
                    if let id = selectedSectionForEdit {
                        vm.delete(sectionId: id)
                        selectedSectionForEdit = nil
                    }
                },
                onReset: { showResetConfirm = true },
                onDone: { exitSectionEditor() }
            )
            SectionInspector(
                viewModel: vm,
                selectedSectionId: selectedSectionForEdit,
                onLabelCommit: { newLabel in
                    if let id = selectedSectionForEdit { vm.rename(sectionId: id, to: newLabel) }
                },
                onColorPick: { idx in
                    if let id = selectedSectionForEdit { vm.recolor(sectionId: id, colorIndex: idx) }
                }
            )
        }
        .padding(12)
    }
}
.confirmationDialog("Reset all section edits?", isPresented: $showResetConfirm) {
    Button("Reset", role: .destructive) {
        Task {
            await analysisService.discardUserEdits()
            if let analysis = analysisService.lastAnalysis {
                sectionEditor?.replaceAll(with: analysis.sections)
            }
        }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Your manual edits will be discarded and the analyzer's sections restored.")
}
```

- [ ] **Step 3: Add toggle button to `TransportBar`**

In `ThePlayer/Views/TransportBar.swift`, add a closure prop:

```swift
let onToggleSectionEditor: () -> Void
let isSectionEditing: Bool
```

In the right-side controls cluster, add:

```swift
Button(action: onToggleSectionEditor) {
    Image(systemName: isSectionEditing ? "pencil.circle.fill" : "pencil.circle")
}
.buttonStyle(.plain)
.help(isSectionEditing ? "Exit section editor" : "Edit sections")
```

In `ContentView`, pass:

```swift
onToggleSectionEditor: {
    if sectionEditor == nil { enterSectionEditor() } else { exitSectionEditor() }
},
isSectionEditing: sectionEditor != nil
```

- [ ] **Step 4: Build and launch**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke test** (cannot be automated)

Open the app in Xcode, load a song with sections, click the pencil icon. Verify:
- Boundary handles appear between sections
- Clicking a section selects it (colored outline)
- Inspector shows label + color picker
- Drag a boundary — snaps to beat, adjacent sections update
- Hold Option during drag — no snap
- Add splits at playhead
- Delete merges into previous
- Rename via dropdown updates label and color
- Picking a color overrides the auto-color
- Undo (⌘Z) reverses each operation
- Reset shows dialog, confirm restores analyzer sections
- Done exits the mode
- Reload the song — your edits persist

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Views/ContentView.swift ThePlayer/Views/TransportBar.swift
git commit -m "feat: wire section editor mode into ContentView and TransportBar"
```

---

### Task C6: Re-analysis "edits preserved" banner + discard

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Add banner state and view**

In `ContentView`, add `@State private var showEditsBanner = false`. After re-analysis triggers (wherever the user can re-run analysis — currently only at first load), show a small banner above the waveform when `analysisService.hasUserEditsForCurrent` is `true` AND the user just re-analyzed.

For a first cut, surface the banner whenever `hasUserEditsForCurrent` is `true` and not in edit mode:

```swift
if analysisService.hasUserEditsForCurrent && sectionEditor == nil {
    HStack {
        Image(systemName: "pencil.circle")
        Text("Manual section edits applied")
            .font(.caption)
        Spacer()
        Button("Discard Edits") {
            Task { await analysisService.discardUserEdits() }
        }
        .controlSize(.small)
    }
    .padding(8)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    .padding(.horizontal, 12)
}
```

Place it directly above the waveform in `playerDetail`.

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/ContentView.swift
git commit -m "feat: show 'edits applied' banner with discard action"
```

---

## Phase D — Improved Analyzer

### Task D1: Beat-synchronous chroma + MFCC features

**Files:**
- Modify: `ThePlayer/Analysis/EssentiaAnalyzer.mm`

We need beat-synchronous feature vectors. Strategy: compute frame-level HPCP (12-dim) and MFCC (13-dim) at the existing `hopSize=1024 @ 44100 Hz`, then average frames between consecutive beat ticks to get one 25-dim vector per beat.

- [ ] **Step 1: Add HPCP computation alongside the existing MFCC loop**

In `EssentiaAnalyzer.mm`, locate the section starting at line 63 (`Algorithm* frameCutter = factory.create("FrameCutter", ...`). Add HPCP-related algorithms before the `while(true)` loop:

```objectivec
Algorithm* spectralPeaks = factory.create("SpectralPeaks",
    "minFrequency", 40.0,
    "maxFrequency", 5000.0,
    "magnitudeThreshold", 0.0);
Algorithm* hpcp = factory.create("HPCP", "size", 12);

std::vector<Real> peakFreqs, peakMags, hpcpVec;
spectralPeaks->input("spectrum").set(spectrumVec);
spectralPeaks->output("frequencies").set(peakFreqs);
spectralPeaks->output("magnitudes").set(peakMags);

hpcp->input("frequencies").set(peakFreqs);
hpcp->input("magnitudes").set(peakMags);
hpcp->output("hpcp").set(hpcpVec);

std::vector<std::vector<Real>> allHpcps;
```

Inside the existing `while(true)` loop, after `mfcc->compute();` add:

```objectivec
spectralPeaks->compute();
hpcp->compute();
allHpcps.push_back(hpcpVec);
```

After the loop (before `delete frameCutter`), add:

```objectivec
delete spectralPeaks;
delete hpcp;
```

- [ ] **Step 2: Build (HPCP wired but not yet used)**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. Fix any header issues — HPCP and SpectralPeaks are standard Essentia algorithms registered by `essentia::init()`, no extra headers needed.

- [ ] **Step 3: Implement beat-synchronous feature aggregation**

After the feature-extraction loop and before the SBic block (current line ~100), add:

```objectivec
// Build beat-synchronous features: avg(MFCC + HPCP) between consecutive ticks
auto frameToTime = [&](size_t i) -> float {
    return (float)(i * 1024) / 44100.0f;
};

std::vector<std::vector<Real>> beatFeatures;
if (!ticks.empty() && allMfccs.size() == allHpcps.size() && allMfccs.size() > 0) {
    size_t frameIdx = 0;
    for (size_t b = 0; b + 1 < ticks.size(); b++) {
        float t0 = (float)ticks[b];
        float t1 = (float)ticks[b + 1];
        std::vector<Real> sumMfcc(allMfccs[0].size(), 0.0);
        std::vector<Real> sumHpcp(allHpcps[0].size(), 0.0);
        int count = 0;
        while (frameIdx < allMfccs.size() && frameToTime(frameIdx) < t1) {
            if (frameToTime(frameIdx) >= t0) {
                for (size_t k = 0; k < sumMfcc.size(); k++) sumMfcc[k] += allMfccs[frameIdx][k];
                for (size_t k = 0; k < sumHpcp.size(); k++) sumHpcp[k] += allHpcps[frameIdx][k];
                count++;
            }
            frameIdx++;
        }
        if (count > 0) {
            std::vector<Real> combined;
            combined.reserve(sumMfcc.size() + sumHpcp.size());
            for (auto v : sumMfcc) combined.push_back(v / count);
            for (auto v : sumHpcp) combined.push_back(v / count);
            beatFeatures.push_back(combined);
        } else {
            beatFeatures.push_back(std::vector<Real>(sumMfcc.size() + sumHpcp.size(), 0.0));
        }
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Analysis/EssentiaAnalyzer.mm
git commit -m "feat(analyzer): compute beat-synchronous MFCC+HPCP features"
```

---

### Task D2: Self-similarity matrix + Foote novelty boundary detection

**Files:**
- Modify: `ThePlayer/Analysis/EssentiaAnalyzer.mm`

- [ ] **Step 1: Add SSM + novelty after `beatFeatures` block**

Insert in `EssentiaAnalyzer.mm` after the `beatFeatures` construction:

```objectivec
// --- Self-similarity matrix (cosine similarity between beat features) ---
auto cosineSim = [](const std::vector<Real>& a, const std::vector<Real>& b) -> float {
    Real dot = 0, na = 0, nb = 0;
    for (size_t i = 0; i < a.size(); i++) {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return (float)(dot / (std::sqrt(na) * std::sqrt(nb)));
};

size_t N = beatFeatures.size();
std::vector<std::vector<float>> SSM(N, std::vector<float>(N, 0.0f));
for (size_t i = 0; i < N; i++) {
    for (size_t j = i; j < N; j++) {
        float s = cosineSim(beatFeatures[i], beatFeatures[j]);
        SSM[i][j] = s;
        SSM[j][i] = s;
    }
}

// --- Foote novelty curve via checkerboard kernel along diagonal ---
// Kernel size in beats — ~4 bars at 4/4 = 16 beats; clamp for short songs.
int K = std::min((int)16, (int)(N / 4));
std::vector<float> novelty(N, 0.0f);
if (K >= 2 && N > (size_t)(2 * K)) {
    for (size_t t = K; t + K < N; t++) {
        float pos = 0, neg = 0;
        for (int di = -K; di < 0; di++) {
            for (int dj = -K; dj < 0; dj++) {
                pos += SSM[t + di][t + dj];
            }
        }
        for (int di = 0; di < K; di++) {
            for (int dj = 0; dj < K; dj++) {
                pos += SSM[t + di][t + dj];
            }
        }
        for (int di = -K; di < 0; di++) {
            for (int dj = 0; dj < K; dj++) {
                neg += SSM[t + di][t + dj];
            }
        }
        for (int di = 0; di < K; di++) {
            for (int dj = -K; dj < 0; dj++) {
                neg += SSM[t + di][t + dj];
            }
        }
        novelty[t] = (pos - neg);
    }
}

// --- Pick peaks (adaptive threshold) and convert to time boundaries ---
std::vector<float> noveltyBoundaries;
if (!novelty.empty()) {
    Real meanN = 0, stdN = 0;
    int nz = 0;
    for (auto v : novelty) if (v != 0) { meanN += v; nz++; }
    if (nz > 0) meanN /= nz;
    for (auto v : novelty) if (v != 0) stdN += (v - meanN) * (v - meanN);
    if (nz > 1) stdN = std::sqrt(stdN / nz);
    Real threshold = meanN + 0.5 * stdN;

    // Local maxima above threshold, with a min-distance of K beats.
    int minDistance = std::max(K, 4);
    int lastPeak = -minDistance;
    for (int t = 1; t + 1 < (int)novelty.size(); t++) {
        if (novelty[t] > threshold &&
            novelty[t] >= novelty[t - 1] &&
            novelty[t] >= novelty[t + 1] &&
            t - lastPeak >= minDistance) {
            noveltyBoundaries.push_back((float)ticks[t]);
            lastPeak = t;
        }
    }
}
```

- [ ] **Step 2: Replace SBic block with the novelty result**

Locate the existing SBic block (currently `if (allMfccs.size() > 10) { ... }` at lines 103-127) and **delete it**. Also delete the `std::vector<Real> segmentation;` declaration above it.

Then in the boundary-collection block (currently around lines 144-154 — the `for (Real seg : segmentation)` loop), replace it with:

```objectivec
// Use novelty boundaries instead of SBic segmentation.
for (float t : noveltyBoundaries) {
    if (t > 0 && t < audioDuration) {
        boundaries.push_back(t);
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Analysis/EssentiaAnalyzer.mm
git commit -m "feat(analyzer): replace SBic with SSM + Foote novelty boundary detection"
```

---

### Task D3: Cluster segments by similarity and assign repetition-aware labels

**Files:**
- Modify: `ThePlayer/Analysis/EssentiaAnalyzer.mm`

- [ ] **Step 1: After boundary list is finalized, compute per-segment mean features and cluster**

Insert the following **after** the line `boundaries.push_back(audioDuration);` (around current line 187), and **before** the existing label-assignment block:

```objectivec
// --- Per-segment mean feature vectors ---
size_t segCount = boundaries.size() - 1;
std::vector<std::vector<Real>> segMeans(segCount);
if (!beatFeatures.empty()) {
    for (size_t s = 0; s < segCount; s++) {
        float t0 = boundaries[s];
        float t1 = boundaries[s + 1];
        std::vector<Real> sum(beatFeatures[0].size(), 0.0);
        int count = 0;
        for (size_t b = 0; b + 1 < ticks.size() && b < beatFeatures.size(); b++) {
            float bt = (float)ticks[b];
            if (bt >= t0 && bt < t1) {
                for (size_t k = 0; k < sum.size(); k++) sum[k] += beatFeatures[b][k];
                count++;
            }
        }
        if (count > 0) {
            for (auto& v : sum) v /= count;
        }
        segMeans[s] = sum;
    }
}

// --- Agglomerative clustering by cosine similarity (threshold 0.85) ---
std::vector<int> cluster(segCount, -1);
int nextCluster = 0;
for (size_t i = 0; i < segCount; i++) {
    if (cluster[i] >= 0) continue;
    cluster[i] = nextCluster;
    for (size_t j = i + 1; j < segCount; j++) {
        if (cluster[j] >= 0) continue;
        if (cosineSim(segMeans[i], segMeans[j]) >= 0.85f) {
            cluster[j] = nextCluster;
        }
    }
    nextCluster++;
}

// --- Heuristic mapping cluster → human label ---
// Find the most-repeated cluster; that's the chorus.
std::map<int, int> clusterCounts;
for (int c : cluster) clusterCounts[c]++;
int chorusCluster = -1;
int maxCount = 1;
for (auto& kv : clusterCounts) {
    if (kv.second > maxCount) { maxCount = kv.second; chorusCluster = kv.first; }
}

// Find the second-most-repeated cluster that appears interleaved with chorus → verse.
int verseCluster = -1;
int verseCount = 1;
for (auto& kv : clusterCounts) {
    if (kv.first == chorusCluster) continue;
    if (kv.second > verseCount) { verseCount = kv.second; verseCluster = kv.first; }
}

NSMutableArray<NSString*>* heuristicLabels = [NSMutableArray arrayWithCapacity:segCount];
for (size_t i = 0; i < segCount; i++) {
    NSString* label;
    int c = cluster[i];
    bool unique = (clusterCounts[c] == 1);
    if (c == chorusCluster && chorusCluster >= 0) {
        label = @"Chorus";
    } else if (c == verseCluster && verseCluster >= 0) {
        label = @"Verse";
    } else if (i == 0 && unique) {
        label = @"Intro";
    } else if (i == segCount - 1 && unique) {
        label = @"Outro";
    } else if (unique) {
        label = @"Bridge";
    } else {
        label = [NSString stringWithFormat:@"Section %zu", i + 1];
    }
    [heuristicLabels addObject:label];
}
```

- [ ] **Step 2: Replace the existing positional label-pattern block**

Locate the existing label-assignment block (currently around lines 189-202: `NSArray *labelPatterns; ... labelPatterns = @[...];`). **Delete it entirely**.

In the `for (size_t i = 0; i < boundaries.size() - 1; i++)` loop below it, replace:

```objectivec
NSString *label;
if (i < labelPatterns.count) {
    label = labelPatterns[i];
} else {
    label = [NSString stringWithFormat:@"Section %zu", i + 1];
}
section.label = label;
```

with:

```objectivec
NSString *label = i < heuristicLabels.count ? heuristicLabels[i] : [NSString stringWithFormat:@"Section %zu", i + 1];
section.label = label;
```

- [ ] **Step 3: Add `<map>` include if not already**

At the top of `EssentiaAnalyzer.mm`, ensure `#include <map>` is present (other Essentia headers include it transitively but be explicit).

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Analysis/EssentiaAnalyzer.mm
git commit -m "feat(analyzer): cluster segments by similarity for repetition-aware labels"
```

---

### Task D4: Manual integration test of new analyzer

**Files:** *(manual — no code changes)*

- [ ] **Step 1: Clear analysis cache for a test track**

```bash
rm -rf "$HOME/Library/Application Support/The Player/cache/"*.json
```

- [ ] **Step 2: Open app, load 3 tracks across genres**

For each track verify:
- Analysis completes without crash within ~10s
- Section count is reasonable (3-8 for a typical pop song)
- The chorus is labeled "Chorus" and is genuinely the repeating chorus
- Verse is labeled "Verse" and is genuinely a verse-like section
- Boundaries land near actual transitions (you may need to A/B against the previous behavior — check git log if you want the SBic version back temporarily)

- [ ] **Step 3: If results are poor, document specific failures**

Record: file name, expected sections, actual sections. Open issues for tuning rather than blocking the merge — the manual editor exists precisely to handle imperfect results.

- [ ] **Step 4: Confirm sidecar override still works**

- Edit sections on a track, save edits.
- Re-analyze (you can force this by removing the cache JSON for that track and reopening).
- Banner should appear; sections should reflect your edits, not the new analyzer output.
- Click "Discard Edits" — analyzer output appears.

- [ ] **Step 5: Commit any tuning tweaks if you needed them**

```bash
git add ThePlayer/Analysis/EssentiaAnalyzer.mm
git commit -m "tune(analyzer): adjust novelty threshold and clustering for real-world tracks"
```

(Skip if no tweaks needed.)

---

## Self-Review (already performed inline; summary)

- **Spec coverage:** All five components (analyzer, sidecar, merge, editor UI, re-analysis preservation) have tasks. ID stability is addressed in A1. Loop-region independence is verified at design time per `LoopRegion` reading times not section IDs.
- **Type consistency:** `stableId: UUID` used consistently. `SectionEditorViewModel.sections` is `[AudioSection]` everywhere. `onChange` signature is `([AudioSection]) -> Void`.
- **No placeholders:** All steps have concrete code or commands.

---

## Plan Complete

Plan saved to `docs/superpowers/plans/2026-04-16-section-analyzer-improvements-and-manual-editor.md`.

Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session with checkpoints for review.

Which approach?
