# BPM, Bars, and Timing Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make bar lines correct by adding downbeat detection, time-signature support, and always-visible manual overrides for BPM, downbeat, and time signature — persisted per-song.

**Architecture:** `TrackAnalysis` gains `downbeatOffset: Int` and `timeSignature: TimeSignature`; `UserEdits` gains optional `bpmOverride`, `downbeatOffsetOverride`, `timeSignatureOverride`. Analyzer adds a low-frequency onset-strength heuristic for downbeat pick. `WaveformView` uses `downbeatOffset + beatsPerBar` for bar lines instead of hardcoded `by: 4`. `TransportBar` gets a timing-controls cluster (BPM readout + `÷2`/`×2`, time-sig dropdown, `◀`/`▶` downbeat nudge, `⌖ Set Downbeat` click-mode).

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), Objective-C++ + Essentia, XCTest. Build via `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`.

**Spec:** [docs/superpowers/specs/2026-04-17-bpm-bars-timing-controls-design.md](../specs/2026-04-17-bpm-bars-timing-controls-design.md)

---

## File Map

**Create:**
- `ThePlayer/Models/TimeSignature.swift` — new type
- `ThePlayer/Views/TimingControls.swift` — timing-controls cluster view
- `ThePlayerTests/TimeSignatureTests.swift`
- `ThePlayerTests/TrackAnalysisLegacyDecodeTests.swift` (or new tests appended to existing `TrackAnalysisTests.swift`)

**Modify:**
- `ThePlayer/Models/TrackAnalysis.swift` — add `downbeatOffset`, `timeSignature`
- `ThePlayer/Models/UserEdits.swift` — add optional overrides, bump schema to 2
- `ThePlayer/Models/SnapDivision.swift` — accept `beatsPerBar`
- `ThePlayer/Analysis/EssentiaAnalyzer.h` — add `downbeatOffset` to `EssentiaResult`
- `ThePlayer/Analysis/EssentiaAnalyzer.mm` — compute downbeat heuristic, expose offset
- `ThePlayer/Analysis/AnalysisService.swift` — extend merge, add `saveTimingOverrides`
- `ThePlayer/Views/WaveformView.swift` — use `downbeatOffset + beatsPerBar`, add `isSettingDownbeat` + `onSetDownbeat`
- `ThePlayer/Views/TransportBar.swift` — embed `TimingControls`
- `ThePlayer/Views/ContentView.swift` — wire timing controls + downbeat-set mode
- `ThePlayer/Views/SidebarView.swift` — if it displays bar counts, update to use time signature
- `ThePlayerTests/AnalysisServiceMergeTests.swift` — add timing-merge tests

---

## Phase A — Data Model & Persistence

### Task A1: `TimeSignature` type

**Files:**
- Create: `ThePlayer/Models/TimeSignature.swift`
- Create: `ThePlayerTests/TimeSignatureTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ThePlayerTests/TimeSignatureTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class TimeSignatureTests: XCTestCase {
    func testFourFourHasBeatsPerBar4() {
        XCTAssertEqual(TimeSignature.fourFour.beatsPerBar, 4)
    }

    func testPresetsIncludeCommonSignatures() {
        let set = Set(TimeSignature.presets)
        XCTAssertTrue(set.contains(.fourFour))
        XCTAssertTrue(set.contains(.threeFour))
        XCTAssertTrue(set.contains(.sixEight))
        XCTAssertTrue(set.contains(.twelveEight))
        XCTAssertTrue(set.contains(.twoFour))
    }

    func testEncodeDecodeRoundTrip() throws {
        let ts = TimeSignature.sixEight
        let data = try JSONEncoder().encode(ts)
        let decoded = try JSONDecoder().decode(TimeSignature.self, from: data)
        XCTAssertEqual(decoded, ts)
    }

    func testDisplayString() {
        XCTAssertEqual(TimeSignature.fourFour.displayString, "4/4")
        XCTAssertEqual(TimeSignature.threeFour.displayString, "3/4")
        XCTAssertEqual(TimeSignature.sixEight.displayString, "6/8")
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/TimeSignatureTests`
Expected: FAIL — `TimeSignature` does not exist.

- [ ] **Step 3: Create `TimeSignature`**

Create `ThePlayer/Models/TimeSignature.swift`:

```swift
import Foundation

struct TimeSignature: Codable, Equatable, Hashable {
    let beatsPerBar: Int
    let beatUnit: Int

    static let fourFour = TimeSignature(beatsPerBar: 4, beatUnit: 4)
    static let threeFour = TimeSignature(beatsPerBar: 3, beatUnit: 4)
    static let sixEight = TimeSignature(beatsPerBar: 6, beatUnit: 8)
    static let twelveEight = TimeSignature(beatsPerBar: 12, beatUnit: 8)
    static let twoFour = TimeSignature(beatsPerBar: 2, beatUnit: 4)

    static let presets: [TimeSignature] = [
        .fourFour, .threeFour, .sixEight, .twelveEight, .twoFour
    ]

    var displayString: String { "\(beatsPerBar)/\(beatUnit)" }
}
```

- [ ] **Step 4: Add to project**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate`

- [ ] **Step 5: Run tests — should pass**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/TimeSignatureTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Models/TimeSignature.swift ThePlayerTests/TimeSignatureTests.swift ThePlayer.xcodeproj
git commit -m "feat: add TimeSignature type with presets"
```

---

### Task A2: Extend `TrackAnalysis` with downbeat offset + time signature

**Files:**
- Modify: `ThePlayer/Models/TrackAnalysis.swift`
- Modify: `ThePlayerTests/TrackAnalysisTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `ThePlayerTests/TrackAnalysisTests.swift`:

```swift
func testTrackAnalysisHasDefaultTimingFields() {
    let ta = TrackAnalysis(bpm: 120, beats: [0, 0.5], sections: [], waveformPeaks: [])
    XCTAssertEqual(ta.downbeatOffset, 0)
    XCTAssertEqual(ta.timeSignature, .fourFour)
}

func testTrackAnalysisRoundTripIncludesNewFields() throws {
    let ta = TrackAnalysis(
        bpm: 120, beats: [0, 0.5], sections: [], waveformPeaks: [],
        downbeatOffset: 2, timeSignature: .threeFour
    )
    let data = try JSONEncoder().encode(ta)
    let decoded = try JSONDecoder().decode(TrackAnalysis.self, from: data)
    XCTAssertEqual(decoded.downbeatOffset, 2)
    XCTAssertEqual(decoded.timeSignature, .threeFour)
}

func testTrackAnalysisLegacyJSONDecodesWithDefaults() throws {
    // Legacy JSON: no downbeatOffset, no timeSignature
    let legacyJSON = """
    {"bpm":120,"beats":[0,0.5],"sections":[],"waveformPeaks":[]}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(TrackAnalysis.self, from: legacyJSON)
    XCTAssertEqual(decoded.downbeatOffset, 0)
    XCTAssertEqual(decoded.timeSignature, .fourFour)
}

func testWithSectionsPreservesTimingFields() {
    let original = TrackAnalysis(
        bpm: 120, beats: [0, 0.5], sections: [], waveformPeaks: [],
        downbeatOffset: 2, timeSignature: .threeFour
    )
    let updated = original.with(sections: [
        AudioSection(label: "X", startTime: 0, endTime: 0.5, startBeat: 0, endBeat: 1, colorIndex: 0)
    ])
    XCTAssertEqual(updated.downbeatOffset, 2)
    XCTAssertEqual(updated.timeSignature, .threeFour)
}
```

- [ ] **Step 2: Run tests — should fail**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/TrackAnalysisTests`
Expected: FAIL — `TrackAnalysis` missing the new fields.

- [ ] **Step 3: Extend `TrackAnalysis`**

Replace `ThePlayer/Models/TrackAnalysis.swift` with:

```swift
import Foundation

struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]
    let downbeatOffset: Int
    let timeSignature: TimeSignature

    init(
        bpm: Float,
        beats: [Float],
        sections: [AudioSection],
        waveformPeaks: [Float],
        downbeatOffset: Int = 0,
        timeSignature: TimeSignature = .fourFour
    ) {
        self.bpm = bpm
        self.beats = beats
        self.sections = sections
        self.waveformPeaks = waveformPeaks
        self.downbeatOffset = downbeatOffset
        self.timeSignature = timeSignature
    }

    func with(sections: [AudioSection]) -> TrackAnalysis {
        TrackAnalysis(
            bpm: bpm, beats: beats, sections: sections, waveformPeaks: waveformPeaks,
            downbeatOffset: downbeatOffset, timeSignature: timeSignature
        )
    }

    enum CodingKeys: String, CodingKey {
        case bpm, beats, sections, waveformPeaks, downbeatOffset, timeSignature
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bpm = try c.decode(Float.self, forKey: .bpm)
        self.beats = try c.decode([Float].self, forKey: .beats)
        self.sections = try c.decode([AudioSection].self, forKey: .sections)
        self.waveformPeaks = try c.decode([Float].self, forKey: .waveformPeaks)
        self.downbeatOffset = try c.decodeIfPresent(Int.self, forKey: .downbeatOffset) ?? 0
        self.timeSignature = try c.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) ?? .fourFour
    }
}
```

- [ ] **Step 4: Run tests — should pass**

Same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Run full suite to catch regressions**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Models/TrackAnalysis.swift ThePlayerTests/TrackAnalysisTests.swift
git commit -m "feat: add downbeatOffset and timeSignature to TrackAnalysis"
```

---

### Task A3: Extend `UserEdits` with optional timing overrides + schema v2

**Files:**
- Modify: `ThePlayer/Models/UserEdits.swift`
- Modify: `ThePlayerTests/UserEditsStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `ThePlayerTests/UserEditsStoreTests.swift`:

```swift
func testUserEditsEncodesTimingOverrides() throws {
    var edits = UserEdits(sections: [])
    edits.bpmOverride = 90
    edits.downbeatOffsetOverride = 2
    edits.timeSignatureOverride = .threeFour

    try store.store(edits, forKey: "timing-1")
    let loaded = try store.retrieve(forKey: "timing-1")
    XCTAssertEqual(loaded?.bpmOverride, 90)
    XCTAssertEqual(loaded?.downbeatOffsetOverride, 2)
    XCTAssertEqual(loaded?.timeSignatureOverride, .threeFour)
    XCTAssertEqual(loaded?.schemaVersion, 2)
}

func testUserEditsLegacyV1JSONDecodesOverridesAsNil() throws {
    let url = tempDir.appendingPathComponent("legacy.user.json")
    let json = """
    {"sections":[],"modifiedAt":700000000,"schemaVersion":1}
    """
    try json.write(to: url, atomically: true, encoding: .utf8)
    let loaded = try store.retrieve(forKey: "legacy")
    XCTAssertNotNil(loaded)
    XCTAssertNil(loaded?.bpmOverride)
    XCTAssertNil(loaded?.downbeatOffsetOverride)
    XCTAssertNil(loaded?.timeSignatureOverride)
}
```

- [ ] **Step 2: Run tests — should fail**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/UserEditsStoreTests`
Expected: FAIL — `bpmOverride` etc. don't exist.

- [ ] **Step 3: Extend `UserEdits`**

Replace `ThePlayer/Models/UserEdits.swift` with:

```swift
import Foundation

struct UserEdits: Codable, Equatable {
    static let currentSchemaVersion: Int = 2

    var sections: [AudioSection]
    var bpmOverride: Float?
    var downbeatOffsetOverride: Int?
    var timeSignatureOverride: TimeSignature?
    var modifiedAt: Date
    var schemaVersion: Int

    init(
        sections: [AudioSection],
        bpmOverride: Float? = nil,
        downbeatOffsetOverride: Int? = nil,
        timeSignatureOverride: TimeSignature? = nil,
        modifiedAt: Date = Date(),
        schemaVersion: Int = UserEdits.currentSchemaVersion
    ) {
        self.sections = sections
        self.bpmOverride = bpmOverride
        self.downbeatOffsetOverride = downbeatOffsetOverride
        self.timeSignatureOverride = timeSignatureOverride
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
    }
}
```

`Codable` auto-synthesis handles the new optional fields (nil in legacy v1 JSON). `UserEditsStore.retrieve` already guards `schemaVersion > currentSchemaVersion` — v1 passes that guard.

- [ ] **Step 4: Run tests — should pass**

Same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Run full suite**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Models/UserEdits.swift ThePlayerTests/UserEditsStoreTests.swift
git commit -m "feat: add timing overrides to UserEdits, bump schema to v2"
```

---

### Task A4: Extend `AnalysisService` merge + add `saveTimingOverrides`

**Files:**
- Modify: `ThePlayer/Analysis/AnalysisService.swift`
- Modify: `ThePlayerTests/AnalysisServiceMergeTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `ThePlayerTests/AnalysisServiceMergeTests.swift`:

```swift
extension AnalysisServiceMergeTests {
    func testMergeAppliesBpmOverride() {
        let analyzed = TrackAnalysis(bpm: 180, beats: [], sections: [], waveformPeaks: [])
        var edits = UserEdits(sections: [])
        edits.bpmOverride = 90
        let merged = AnalysisService.mergeCachedAnalysis(analyzed, userEdits: edits)
        XCTAssertEqual(merged.bpm, 90)
    }

    func testMergeAppliesDownbeatOffsetOverride() {
        let analyzed = TrackAnalysis(
            bpm: 120, beats: [], sections: [], waveformPeaks: [],
            downbeatOffset: 0, timeSignature: .fourFour
        )
        var edits = UserEdits(sections: [])
        edits.downbeatOffsetOverride = 3
        let merged = AnalysisService.mergeCachedAnalysis(analyzed, userEdits: edits)
        XCTAssertEqual(merged.downbeatOffset, 3)
    }

    func testMergeAppliesTimeSignatureOverride() {
        let analyzed = TrackAnalysis(bpm: 120, beats: [], sections: [], waveformPeaks: [])
        var edits = UserEdits(sections: [])
        edits.timeSignatureOverride = .threeFour
        let merged = AnalysisService.mergeCachedAnalysis(analyzed, userEdits: edits)
        XCTAssertEqual(merged.timeSignature, .threeFour)
    }

    func testSaveTimingOverridesPatchesWithoutClobberingSections() async throws {
        let key = "timing-patch"
        let analyzed = TrackAnalysis(
            bpm: 120,
            beats: [],
            sections: [AudioSection(label: "A", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 0)],
            waveformPeaks: []
        )
        try cache.store(analyzed, forKey: key)
        try userEdits.store(UserEdits(sections: [
            AudioSection(label: "Mine", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 2)
        ]), forKey: key)

        let service = AnalysisService(
            analyzer: FakeAnalyzer(nextResult: analyzed),
            cache: cache,
            userEdits: userEdits
        )
        try await service.reanalyze(key: key, fileURL: URL(fileURLWithPath: "/dev/null"))

        try service.saveTimingOverrides(bpm: 90, downbeatOffset: 2, timeSignature: .threeFour)

        let loaded = try userEdits.retrieve(forKey: key)
        XCTAssertEqual(loaded?.bpmOverride, 90)
        XCTAssertEqual(loaded?.downbeatOffsetOverride, 2)
        XCTAssertEqual(loaded?.timeSignatureOverride, .threeFour)
        XCTAssertEqual(loaded?.sections.first?.label, "Mine", "sections must not be clobbered")
    }
}
```

- [ ] **Step 2: Run tests — should fail**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/AnalysisServiceMergeTests`
Expected: FAIL.

- [ ] **Step 3: Extend `mergeCachedAnalysis` and add `saveTimingOverrides`**

In `ThePlayer/Analysis/AnalysisService.swift`, replace the existing `mergeCachedAnalysis` with:

```swift
static func mergeCachedAnalysis(_ analysis: TrackAnalysis, userEdits: UserEdits?) -> TrackAnalysis {
    guard let edits = userEdits else { return analysis }
    let mergedSections = edits.sections.isEmpty ? analysis.sections : edits.sections
    return TrackAnalysis(
        bpm: edits.bpmOverride ?? analysis.bpm,
        beats: analysis.beats,
        sections: mergedSections,
        waveformPeaks: analysis.waveformPeaks,
        downbeatOffset: edits.downbeatOffsetOverride ?? analysis.downbeatOffset,
        timeSignature: edits.timeSignatureOverride ?? analysis.timeSignature
    )
}
```

Add this method on `AnalysisService`:

```swift
/// Patch only the timing-override fields on the current sidecar, preserving sections.
func saveTimingOverrides(bpm: Float?, downbeatOffset: Int?, timeSignature: TimeSignature?) throws {
    guard let key = lastAnalysisKey else { return }
    let existing = try userEdits.retrieve(forKey: key) ?? UserEdits(sections: [])
    var updated = existing
    updated.bpmOverride = bpm
    updated.downbeatOffsetOverride = downbeatOffset
    updated.timeSignatureOverride = timeSignature
    updated.modifiedAt = Date()
    try userEdits.store(updated, forKey: key)
    hasUserEditsForCurrent = true
}
```

Also: because merge now applies overrides even when `sections.isEmpty`, update the existing `hasUserEditsForCurrent` assignment. The old logic assumed any sidecar = "has edits." Keep that — any sidecar file existing still counts.

- [ ] **Step 4: Run tests — should pass**

Same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Run full suite**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Analysis/AnalysisService.swift ThePlayerTests/AnalysisServiceMergeTests.swift
git commit -m "feat: merge timing overrides and add saveTimingOverrides"
```

---

## Phase B — SnapDivision & Analyzer

### Task B1: `SnapDivision` takes `beatsPerBar`

**Files:**
- Modify: `ThePlayer/Models/SnapDivision.swift`
- Modify: callers of `snapPositions(beats:bpm:duration:)`

- [ ] **Step 1: Find all callers**

Run: `grep -rn "snapPositions(beats:" /Users/bareloved/Github/theplayer/ThePlayer` to list call sites.
Expected: one call in `WaveformView.swift` (probably `gridPositions` computed prop).

- [ ] **Step 2: Update `SnapDivision`**

Replace `ThePlayer/Models/SnapDivision.swift` with:

```swift
import Foundation

/// Snap grid size in number of bars.
enum SnapDivision: Int, CaseIterable, Identifiable {
    case oneBar = 1
    case twoBars = 2
    case fourBars = 4
    case eightBars = 8
    case sixteenBars = 16

    var id: Int { rawValue }

    var label: String {
        "\(rawValue) bar\(rawValue == 1 ? "" : "s")"
    }

    var shortLabel: String { "\(rawValue)" }

    /// Generate snap positions — every N bars, given beats-per-bar from the time signature.
    func snapPositions(beats: [Float], bpm: Float, duration: Float, beatsPerBar: Int) -> [Float] {
        guard beats.count >= beatsPerBar else { return [] }
        let beatsPerSnap = rawValue * beatsPerBar
        return stride(from: 0, to: beats.count, by: beatsPerSnap).map { beats[$0] }
    }
}
```

- [ ] **Step 3: Update callers**

Update `WaveformView.swift`'s `gridPositions` computed property to pass `beatsPerBar`:

Find:
```swift
private var gridPositions: [Float] {
    snapDivision.snapPositions(beats: beats, bpm: bpm, duration: duration)
}
```

Replace with:
```swift
private var gridPositions: [Float] {
    snapDivision.snapPositions(beats: beats, bpm: bpm, duration: duration, beatsPerBar: timeSignature.beatsPerBar)
}
```

(This assumes `timeSignature` is already a prop on `WaveformView` — if not, Task B4 adds it. For now, if compile fails here because the prop doesn't exist, use `beatsPerBar: 4` temporarily and fix in B4.)

Actually, do the prop addition here to keep commits clean — see B4. Alternatively, to keep B1 self-contained, pass a literal `4`:
```swift
snapPositions(beats: beats, bpm: bpm, duration: duration, beatsPerBar: 4)
```
and update in B4. Choose the literal-4 path to keep task boundaries clean.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run full suite**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Models/SnapDivision.swift ThePlayer/Views/WaveformView.swift
git commit -m "feat: SnapDivision.snapPositions takes beatsPerBar"
```

---

### Task B2: Expose `downbeatOffset` on `EssentiaResult`

**Files:**
- Modify: `ThePlayer/Analysis/EssentiaAnalyzer.h`
- Modify: `ThePlayer/Analysis/EssentiaAnalyzer.mm`

- [ ] **Step 1: Add property to header**

In `ThePlayer/Analysis/EssentiaAnalyzer.h`, modify `EssentiaResult`:

```objectivec
@interface EssentiaResult : NSObject
@property (nonatomic) float bpm;
@property (nonatomic) NSInteger downbeatOffset;  // NEW
@property (nonatomic, strong) NSArray<NSNumber *> *beats;
@property (nonatomic, strong) NSArray<EssentiaSection *> *sections;
@end
```

- [ ] **Step 2: Set default in `EssentiaAnalyzer.mm`**

In `analyzeFileAtPath:error:`, right after `result.bpm = bpm;`, add:

```objectivec
result.downbeatOffset = 0;  // overridden by heuristic in Task B3
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Analysis/EssentiaAnalyzer.h ThePlayer/Analysis/EssentiaAnalyzer.mm
git commit -m "feat(analyzer): expose downbeatOffset on EssentiaResult"
```

---

### Task B3: Downbeat heuristic (low-freq onset strength)

**Files:**
- Modify: `ThePlayer/Analysis/EssentiaAnalyzer.mm`

- [ ] **Step 1: Compute per-beat low-frequency energy**

In `EssentiaAnalyzer.mm`, after the MFCC/HPCP frame loop and before the `beatFeatures*` construction, add:

```objectivec
// --- Per-beat low-frequency energy (for downbeat heuristic) ---
// Low-freq bins: 20-200 Hz. Spectrum length is 2048/2+1 = 1025; freq per bin = 44100/2048 ≈ 21.5 Hz.
// Keep spectrumVec references; we need to re-run just the spectrum for this, OR we keep a sidecar vector.
// Cheaper: during the existing loop, we can also collect per-frame low-freq sum.
```

Actually, the cleanest way: compute it INSIDE the existing frame loop. So the edit happens earlier. Replace this step with a two-part edit:

**Part A (inside the existing frame loop):** After `spectrum->compute();` but before `mfcc->compute();`, add a per-frame low-frequency sum capture. Extend the state:

Before the loop, add:
```objectivec
std::vector<Real> frameLowEnergy;
```

Inside the loop, after `spectrum->compute();`, add:
```objectivec
// Sum magnitude in the 20-200 Hz band
Real lowE = 0;
int lowStartBin = (int)std::floor(20.0 * 2048.0 / 44100.0);
int lowEndBin = (int)std::ceil(200.0 * 2048.0 / 44100.0);
if (lowEndBin > (int)spectrumVec.size()) lowEndBin = (int)spectrumVec.size();
for (int b = lowStartBin; b < lowEndBin; b++) lowE += spectrumVec[b];
frameLowEnergy.push_back(lowE);
```

**Part B (after the loop, before `beatFeatures*` construction):** Compute per-beat low-frequency energy:

```objectivec
auto frameToTime2 = [](size_t i) -> float {
    return (float)(i * 1024) / 44100.0f;
};

std::vector<Real> beatLowEnergy;
if (!ticks.empty() && !frameLowEnergy.empty()) {
    size_t fi = 0;
    for (size_t b = 0; b + 1 < ticks.size(); b++) {
        float t0 = (float)ticks[b];
        float t1 = (float)ticks[b + 1];
        Real sum = 0;
        int count = 0;
        while (fi < frameLowEnergy.size() && frameToTime2(fi) < t1) {
            if (frameToTime2(fi) >= t0) {
                sum += frameLowEnergy[fi];
                count++;
            }
            fi++;
        }
        beatLowEnergy.push_back(count > 0 ? sum / (Real)count : 0);
    }
}
```

**Part C (downbeat pick):** After `beatLowEnergy` is built, but before the SSM block, add:

```objectivec
// --- Downbeat heuristic: for each offset 0..3, sum low-freq energy at beats matching that offset ---
int chosenDownbeatOffset = 0;
if (beatLowEnergy.size() >= 4) {
    Real bestScore = -1;
    for (int offset = 0; offset < 4; offset++) {
        Real score = 0;
        for (size_t b = offset; b < beatLowEnergy.size(); b += 4) {
            score += beatLowEnergy[b];
        }
        if (score > bestScore) {
            bestScore = score;
            chosenDownbeatOffset = offset;
        }
    }
}
```

**Part D (set result):** Replace `result.downbeatOffset = 0;` (from B2) with:

```objectivec
result.downbeatOffset = chosenDownbeatOffset;
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run full suite**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS (no test exercises this path directly).

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Analysis/EssentiaAnalyzer.mm
git commit -m "feat(analyzer): pick downbeat offset from low-frequency onset strength"
```

---

### Task B4: Read `downbeatOffset` in Swift wrapper

**Files:**
- Modify: `ThePlayer/Analysis/AnalysisService.swift`

- [ ] **Step 1: Copy `downbeatOffset` into `TrackAnalysis`**

In `EssentiaAnalyzerSwift.analyze(fileURL:progress:)`, in the `TrackAnalysis(...)` constructor call, add:

```swift
let analysis = TrackAnalysis(
    bpm: result.bpm,
    beats: beats,
    sections: sections,
    waveformPeaks: peaks,
    downbeatOffset: Int(result.downbeatOffset),
    timeSignature: .fourFour  // auto-detect is 4/4-only; user can override
)
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run full suite**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Analysis/AnalysisService.swift
git commit -m "feat: propagate analyzer downbeat offset into TrackAnalysis"
```

---

## Phase C — Waveform & UI

### Task C1: `WaveformView` uses `downbeatOffset + beatsPerBar` for bar lines

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift`

- [ ] **Step 1: Add props**

Add to `WaveformView`'s property list (right after `let bpm: Float`):

```swift
let downbeatOffset: Int
let timeSignature: TimeSignature
let isSettingDownbeat: Bool
let onSetDownbeat: ((Int) -> Void)?
```

Update all call sites (currently just `ContentView`) to pass:
```swift
downbeatOffset: 0,
timeSignature: .fourFour,
isSettingDownbeat: false,
onSetDownbeat: nil
```

(These will be replaced with real values in C3.)

- [ ] **Step 2: Replace hardcoded bar stride**

Find:
```swift
private var barPositions: Set<Float> {
    guard beats.count >= 4 else { return [] }
    let bars = stride(from: 0, to: beats.count, by: 4).map { beats[$0] }
    return Set(bars.map { ($0 * 100).rounded() / 100 })
}
```

Replace with:
```swift
private var barPositions: Set<Float> {
    let bpb = timeSignature.beatsPerBar
    guard beats.count >= bpb, bpb > 0 else { return [] }
    let bars = stride(from: downbeatOffset, to: beats.count, by: bpb).map { beats[$0] }
    return Set(bars.map { ($0 * 100).rounded() / 100 })
}
```

Also update `gridPositions` (from Task B1) to pass the real time signature:
```swift
private var gridPositions: [Float] {
    snapDivision.snapPositions(beats: beats, bpm: bpm, duration: duration, beatsPerBar: timeSignature.beatsPerBar)
}
```

- [ ] **Step 3: Handle "set downbeat" click mode**

Find the existing `.onTapGesture { location in ... }` block. It already has section-edit and loop handling; add a new case:

```swift
.onTapGesture { location in
    let fraction = Float(location.x / totalWidth)
    let time = fraction * duration
    if isSettingDownbeat, let onSetDownbeat {
        // Find nearest beat index
        var bestIdx = 0
        var bestDist: Float = .infinity
        for (i, t) in beats.enumerated() {
            let d = abs(t - time)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        onSetDownbeat(bestIdx)
        return
    }
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

- [ ] **Step 4: Visual cue for downbeat mode**

Find the existing loop-mode visual cue:
```swift
.overlay {
    if isSettingLoop {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(.orange, lineWidth: 2)
            .allowsHitTesting(false)
    }
}
```

Replace with:
```swift
.overlay {
    if isSettingLoop {
        RoundedRectangle(cornerRadius: 8).strokeBorder(.orange, lineWidth: 2).allowsHitTesting(false)
    } else if isSettingDownbeat {
        RoundedRectangle(cornerRadius: 8).strokeBorder(.cyan, lineWidth: 2).allowsHitTesting(false)
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run full suite**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift ThePlayer/Views/ContentView.swift
git commit -m "feat: WaveformView uses downbeatOffset + beatsPerBar; add Set Downbeat click mode"
```

---

### Task C2: `TimingControls` cluster view

**Files:**
- Create: `ThePlayer/Views/TimingControls.swift`

- [ ] **Step 1: Create the view**

Create `ThePlayer/Views/TimingControls.swift`:

```swift
import SwiftUI

struct TimingControls: View {
    let bpm: Float
    let timeSignature: TimeSignature
    let downbeatOffset: Int
    let isSettingDownbeat: Bool
    let hasBpmOverride: Bool
    let hasTimeSigOverride: Bool
    let hasDownbeatOverride: Bool

    let onSetBpm: (Float) -> Void
    let onResetBpm: () -> Void
    let onSetTimeSignature: (TimeSignature) -> Void
    let onResetTimeSignature: () -> Void
    let onShiftDownbeat: (Int) -> Void  // ±1
    let onResetDownbeat: () -> Void
    let onToggleSetDownbeat: () -> Void

    @State private var editingBpm = false
    @State private var bpmText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            // BPM
            if editingBpm {
                TextField("BPM", text: $bpmText, onCommit: commitBpm)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .font(.caption)
            } else {
                Text("\(Int(bpm.rounded())) BPM")
                    .font(.caption.monospaced())
                    .foregroundStyle(hasBpmOverride ? .blue : .primary)
                    .onTapGesture { beginEditingBpm() }
                    .contextMenu {
                        Button("Reset to auto-detected", action: onResetBpm).disabled(!hasBpmOverride)
                    }
            }
            Button("÷2") { onSetBpm(bpm / 2) }
                .buttonStyle(.bordered).controlSize(.mini)
            Button("×2") { onSetBpm(bpm * 2) }
                .buttonStyle(.bordered).controlSize(.mini)

            Divider().frame(height: 14)

            // Time signature
            Menu(timeSignature.displayString) {
                ForEach(TimeSignature.presets, id: \.self) { ts in
                    Button(ts.displayString) { onSetTimeSignature(ts) }
                }
                Divider()
                Button("Reset to auto-detected", action: onResetTimeSignature).disabled(!hasTimeSigOverride)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.caption)
            .foregroundStyle(hasTimeSigOverride ? .blue : .primary)

            Divider().frame(height: 14)

            // Downbeat shift
            Button(action: { onShiftDownbeat(-1) }) { Image(systemName: "chevron.left") }
                .buttonStyle(.bordered).controlSize(.mini)
                .help("Shift downbeat earlier")
            Button(action: { onShiftDownbeat(1) }) { Image(systemName: "chevron.right") }
                .buttonStyle(.bordered).controlSize(.mini)
                .help("Shift downbeat later")
            Button(action: onToggleSetDownbeat) {
                Image(systemName: "scope")
            }
            .buttonStyle(.bordered).controlSize(.mini)
            .tint(isSettingDownbeat ? .cyan : nil)
            .help(isSettingDownbeat ? "Click a beat on the waveform" : "Set downbeat by clicking a beat")
            .contextMenu {
                Button("Reset to auto-detected", action: onResetDownbeat).disabled(!hasDownbeatOverride)
            }
        }
    }

    private func beginEditingBpm() {
        bpmText = String(Int(bpm.rounded()))
        editingBpm = true
    }

    private func commitBpm() {
        if let v = Float(bpmText), v > 0 { onSetBpm(v) }
        editingBpm = false
    }
}
```

- [ ] **Step 2: Add to project + build**

Run: `cd /Users/bareloved/Github/theplayer && xcodegen generate && xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/TimingControls.swift ThePlayer.xcodeproj
git commit -m "feat: add TimingControls cluster view"
```

---

### Task C3: Wire `TimingControls` into `TransportBar` + `ContentView`

**Files:**
- Modify: `ThePlayer/Views/TransportBar.swift`
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Add prop to `TransportBar`**

Add to `TransportBar`:

```swift
let timingControls: AnyView?
```

Default callers pass `nil` (none do yet; you'll update `ContentView`).

In the `utilityRow`, add at the end:

```swift
if let timingControls { timingControls }
```

(Using `AnyView?` is the least invasive way to inject — alternative: take all the concrete props and embed `TimingControls` directly. Prefer `AnyView?` for scoping.)

Actually, cleaner approach: add an overload-style init that includes the TimingControls props, OR just take the view directly. Use `AnyView?` because the existing file is already compact.

- [ ] **Step 2: Add `ContentView` state + handlers**

In `ContentView`, near existing `@State` declarations, add:

```swift
@State private var isSettingDownbeat: Bool = false
```

Add a computed binding for whether each field is overridden — derive from what `analysisService` exposes. Add a helper that merges currents from the analysis service. Since we need the override flags to color-tint the UI, expose them by asking the sidecar directly:

```swift
private func hasOverride<T: Equatable>(_ analyzerValue: T, _ mergedValue: T) -> Bool {
    analyzerValue != mergedValue
}
```

Wait — the merged value is `lastAnalysis`; the analyzer value isn't directly exposed. Simplest: extend `AnalysisService` to expose a derived `TrackAnalysis?` that's the raw cache (no user edits) so UI can diff. Add this in the same commit:

Add to `AnalysisService`:
```swift
/// Raw analyzer output for the currently loaded track, ignoring user edits.
private(set) var baseAnalysis: TrackAnalysis?
```

Set it alongside `lastAnalysis`:
- In `analyze(fileURL:)` cached-path: `baseAnalysis = cached` before merge.
- In `analyze(fileURL:)` fresh-path: `baseAnalysis = result` before merge.
- In `reanalyze(...)`: `baseAnalysis = result` before merge.
- In `discardUserEdits()`: after reload, set `baseAnalysis = cached`.

- [ ] **Step 3: Wire handlers**

In `ContentView.playerDetail`, pass to `TransportBar`:

```swift
timingControls: AnyView(
    TimingControls(
        bpm: analysisService.lastAnalysis?.bpm ?? 0,
        timeSignature: analysisService.lastAnalysis?.timeSignature ?? .fourFour,
        downbeatOffset: analysisService.lastAnalysis?.downbeatOffset ?? 0,
        isSettingDownbeat: isSettingDownbeat,
        hasBpmOverride: analysisService.baseAnalysis?.bpm != analysisService.lastAnalysis?.bpm,
        hasTimeSigOverride: analysisService.baseAnalysis?.timeSignature != analysisService.lastAnalysis?.timeSignature,
        hasDownbeatOverride: analysisService.baseAnalysis?.downbeatOffset != analysisService.lastAnalysis?.downbeatOffset,
        onSetBpm: { newBpm in
            saveTiming(bpm: newBpm, downbeat: nil, timeSig: nil, mode: .bpm)
        },
        onResetBpm: { saveTiming(bpm: nil, downbeat: nil, timeSig: nil, mode: .bpm) },
        onSetTimeSignature: { ts in
            saveTiming(bpm: nil, downbeat: nil, timeSig: ts, mode: .timeSig)
        },
        onResetTimeSignature: { saveTiming(bpm: nil, downbeat: nil, timeSig: nil, mode: .timeSig) },
        onShiftDownbeat: { delta in
            let current = analysisService.lastAnalysis?.downbeatOffset ?? 0
            let bpb = analysisService.lastAnalysis?.timeSignature.beatsPerBar ?? 4
            let next = ((current + delta) % bpb + bpb) % bpb
            saveTiming(bpm: nil, downbeat: next, timeSig: nil, mode: .downbeat)
        },
        onResetDownbeat: { saveTiming(bpm: nil, downbeat: nil, timeSig: nil, mode: .downbeat) },
        onToggleSetDownbeat: { isSettingDownbeat.toggle() }
    )
)
```

Add the helper below `playerDetail`:

```swift
private enum TimingField { case bpm, timeSig, downbeat }

private func saveTiming(bpm: Float?, downbeat: Int?, timeSig: TimeSignature?, mode: TimingField) {
    // Read current sidecar values; patch only the requested field.
    let key = analysisService.lastAnalysisKey
    guard key != nil else { return }
    let existing = (try? analysisService.userEdits.retrieve(forKey: key!)) ?? UserEdits(sections: [])
    var next = existing
    switch mode {
    case .bpm: next.bpmOverride = bpm
    case .timeSig: next.timeSignatureOverride = timeSig
    case .downbeat: next.downbeatOffsetOverride = downbeat
    }
    next.modifiedAt = Date()
    try? analysisService.userEdits.store(next, forKey: key!)

    // Refresh lastAnalysis
    if let base = analysisService.baseAnalysis {
        analysisService.lastAnalysis = AnalysisService.mergeCachedAnalysis(base, userEdits: next)
        analysisService.hasUserEditsForCurrent = true
    }
}
```

Note: `lastAnalysis` and `hasUserEditsForCurrent` are `private(set)` on `AnalysisService`. Either change them to `internal(set)` or add mutation methods on the service. Prefer adding a method:

```swift
// In AnalysisService:
func applyTimingPatch(_ edits: UserEdits) throws {
    guard let key = lastAnalysisKey else { return }
    try userEdits.store(edits, forKey: key)
    if let base = baseAnalysis {
        lastAnalysis = Self.mergeCachedAnalysis(base, userEdits: edits)
        hasUserEditsForCurrent = true
    }
}
```

Then `saveTiming` in `ContentView` calls this. Simpler and keeps mutability encapsulated.

- [ ] **Step 4: Wire `WaveformView` downbeat props**

In `ContentView.playerDetail`'s `WaveformView(...)` construction, update the four new props:

```swift
downbeatOffset: analysisService.lastAnalysis?.downbeatOffset ?? 0,
timeSignature: analysisService.lastAnalysis?.timeSignature ?? .fourFour,
isSettingDownbeat: isSettingDownbeat,
onSetDownbeat: { beatIdx in
    let bpb = analysisService.lastAnalysis?.timeSignature.beatsPerBar ?? 4
    let offset = beatIdx % bpb
    saveTiming(bpm: nil, downbeat: offset, timeSig: nil, mode: .downbeat)
    isSettingDownbeat = false
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run full suite**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/ContentView.swift ThePlayer/Views/TransportBar.swift ThePlayer/Analysis/AnalysisService.swift
git commit -m "feat: wire TimingControls into TransportBar and ContentView"
```

---

### Task C4: Handle bar-count in section editor

**Files:**
- Modify: `ThePlayer/Models/AudioSection.swift` (if `barCount` is used elsewhere)
- Modify: `ThePlayer/Views/SidebarView.swift` (if it shows bar counts)

- [ ] **Step 1: Find bar-count usages**

Run: `grep -rn "barCount" /Users/bareloved/Github/theplayer/ThePlayer /Users/bareloved/Github/theplayer/ThePlayerTests`

- [ ] **Step 2: Decide**

`AudioSection.barCount` currently computes `(endBeat - startBeat) / 4`. Two choices:
1. **Leave at /4.** Accept that section-editor bar counts lie for non-4/4 songs. YAGNI — no visible impact until you have a 3/4 song in the sidebar with a bar count shown.
2. **Add a `barCount(timeSignature:)` helper** on `AudioSection` and update call sites.

Choose #2 if the sidebar prominently shows bar counts — otherwise #1. Use `grep` output to decide.

If choosing #2:

Add to `AudioSection`:
```swift
func barCount(timeSignature: TimeSignature) -> Int {
    (endBeat - startBeat) / timeSignature.beatsPerBar
}
```

Deprecate the old `barCount` getter with:
```swift
@available(*, deprecated, message: "Use barCount(timeSignature:) for accurate results in non-4/4")
var barCount: Int { (endBeat - startBeat) / 4 }
```

Update the SidebarView (or wherever used) to pass the current `TrackAnalysis.timeSignature`.

- [ ] **Step 3: Build + test**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Models/AudioSection.swift ThePlayer/Views/SidebarView.swift
git commit -m "feat: AudioSection.barCount(timeSignature:) for non-4/4 support"
```

---

## Phase D — Manual Integration Test

### Task D1: Manual smoke test

*(manual — no code changes)*

- [ ] **Step 1: Clear cache**

```bash
rm -rf "$HOME/Library/Application Support/The Player/cache/"*.json
```

- [ ] **Step 2: Load a song that had wrong bars**

Verify:
- Auto-detected downbeat is right OR one `◀` / `▶` press fixes it.
- `⌖` button enters "click a beat" mode (cyan border), one click sets beat 1.
- Bar lines reflect the new offset immediately.
- Close + reopen the song: offset persists.

- [ ] **Step 3: Test `×2` / `÷2`**

Song whose BPM was doubled (if you have one): click `÷2`, confirm BPM readout halves, bar lines recompute. Close + reopen: stays halved.

- [ ] **Step 4: Test time-signature dropdown**

Pick `3/4` on a 4/4 song (intentionally wrong): bars should now be every 3 beats. Pick `4/4` back. Confirm reset-to-auto-detected works via right-click.

- [ ] **Step 5: Test interaction with section editor**

With overrides in place, enter section editor, drag a boundary. Exit. Confirm:
- Sections still load correctly.
- Timing overrides still applied.
- Section-edit banner still shows.

---

## Self-Review

Spec coverage: all five sections (TimeSignature, extended TrackAnalysis, extended UserEdits, analyzer downbeat heuristic, merge + saveTimingOverrides, UI cluster, bar-line computation, optional barCount helper) have tasks. Placeholders: none ("reset to auto-detected" behavior is fully specified via `saveTiming(...)` with nil for the field). Type consistency: `beatsPerBar: Int`, `downbeatOffset: Int`, `timeSignature: TimeSignature`, `TimingField` enum all match across tasks.

---

## Execution Handoff

Plan complete. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task with review
2. **Inline Execution** — batch with checkpoints

Which approach?
