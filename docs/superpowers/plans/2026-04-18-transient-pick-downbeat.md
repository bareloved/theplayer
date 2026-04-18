# Transient-Pick Downbeat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user right-click a waveform transient to set it as bar 1 (the downbeat) with sample-accurate precision.

**Architecture:** Add a new `onsets: [Float]` field to `TrackAnalysis`, populated during analysis by a new Essentia `OnsetDetection`+refinement pass. On the waveform, right-clicking opens a context menu whose "Set 1 here" item snaps `firstDownbeatTime` to the nearest onset within 30 screen points of the cursor. The existing `onSetDownbeat(...)` pipeline persists the result.

**Tech Stack:** Swift / SwiftUI (macOS), Objective-C++ bridge, Essentia C++ library, XCTest.

**Companion spec:** [docs/superpowers/specs/2026-04-18-transient-pick-downbeat-design.md](../specs/2026-04-18-transient-pick-downbeat-design.md)

---

## File Structure

| File | Role |
|------|------|
| `ThePlayer/Models/TrackAnalysis.swift` | Add `onsets: [Float]` property + Codable. |
| `ThePlayer/Analysis/EssentiaAnalyzer.h` | Expose `onsets` on `EssentiaResult`. |
| `ThePlayer/Analysis/EssentiaAnalyzer.mm` | New onset detection + refinement pass. |
| `ThePlayer/Analysis/AnalysisService.swift` | Thread `onsets` from bridge → `TrackAnalysis`. |
| `ThePlayer/Analysis/AnalysisCache.swift` | Invalidate cached entries missing `onsets`. |
| `ThePlayer/Analysis/MockAnalyzer.swift` | Stub `onsets` for previews/tests. |
| `ThePlayer/Views/OnsetPicker.swift` (NEW) | Pure nearest-onset helper. |
| `ThePlayer/Views/WaveformView.swift` | Mouse-location tracking, context menu, highlight overlay, wiring. |
| `ThePlayer/Views/ContentView.swift` | Thread `onsets` into `WaveformView`. |
| `ThePlayerTests/OnsetPickerTests.swift` (NEW) | Unit tests for picker. |
| `ThePlayerTests/TrackAnalysisTests.swift` | Round-trip encode/decode including onsets + legacy decoding. |

---

## Task 1: Add `onsets` field to `TrackAnalysis`

**Files:**
- Modify: `ThePlayer/Models/TrackAnalysis.swift`
- Test: `ThePlayerTests/TrackAnalysisTests.swift`

- [ ] **Step 1: Write failing test — `onsets` round-trips through Codable**

Open `ThePlayerTests/TrackAnalysisTests.swift` and add this test at the end of the class (keep it self-contained — don't touch existing tests):

```swift
func testTrackAnalysisRoundTripIncludesOnsets() throws {
    let ta = TrackAnalysis(
        bpm: 120,
        beats: [0, 0.5, 1.0],
        sections: [],
        waveformPeaks: [],
        onsets: [0.123, 0.612, 1.104]
    )
    let data = try JSONEncoder().encode(ta)
    let decoded = try JSONDecoder().decode(TrackAnalysis.self, from: data)
    XCTAssertEqual(decoded.onsets, [0.123, 0.612, 1.104])
}

func testTrackAnalysisLegacyJSONWithoutOnsetsDecodesToEmptyArray() throws {
    let legacyJSON = """
    {"bpm":120,"beats":[0,0.5],"sections":[],"waveformPeaks":[]}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(TrackAnalysis.self, from: legacyJSON)
    XCTAssertEqual(decoded.onsets, [])
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run in Xcode: Product → Test, filter to `TrackAnalysisTests/testTrackAnalysisRoundTripIncludesOnsets`.
Or CLI:

```bash
xcodebuild test -project ThePlayer.xcodeproj -scheme ThePlayer -only-testing:ThePlayerTests/TrackAnalysisTests/testTrackAnalysisRoundTripIncludesOnsets 2>&1 | tail -20
```

Expected: FAIL with "Extra argument 'onsets' in call" (compilation error).

- [ ] **Step 3: Add `onsets` property, initializer arg, Codable key**

Replace the entire contents of `ThePlayer/Models/TrackAnalysis.swift` with:

```swift
import Foundation

struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]
    let downbeatOffset: Int
    let firstDownbeatTime: Float
    let timeSignature: TimeSignature
    let onsets: [Float]

    init(
        bpm: Float,
        beats: [Float],
        sections: [AudioSection],
        waveformPeaks: [Float],
        downbeatOffset: Int = 0,
        firstDownbeatTime: Float? = nil,
        timeSignature: TimeSignature = .fourFour,
        onsets: [Float] = []
    ) {
        self.bpm = bpm
        self.beats = beats
        self.sections = sections
        self.waveformPeaks = waveformPeaks
        self.downbeatOffset = downbeatOffset
        if let t = firstDownbeatTime {
            self.firstDownbeatTime = t
        } else if !beats.isEmpty {
            let idx = max(0, min(downbeatOffset, beats.count - 1))
            self.firstDownbeatTime = beats[idx]
        } else {
            self.firstDownbeatTime = 0
        }
        self.timeSignature = timeSignature
        self.onsets = onsets
    }

    func with(sections: [AudioSection]) -> TrackAnalysis {
        TrackAnalysis(
            bpm: bpm, beats: beats, sections: sections, waveformPeaks: waveformPeaks,
            downbeatOffset: downbeatOffset, firstDownbeatTime: firstDownbeatTime,
            timeSignature: timeSignature, onsets: onsets
        )
    }

    func with(firstDownbeatTime: Float) -> TrackAnalysis {
        TrackAnalysis(
            bpm: bpm, beats: beats, sections: sections, waveformPeaks: waveformPeaks,
            downbeatOffset: downbeatOffset, firstDownbeatTime: firstDownbeatTime,
            timeSignature: timeSignature, onsets: onsets
        )
    }

    enum CodingKeys: String, CodingKey {
        case bpm, beats, sections, waveformPeaks, downbeatOffset, firstDownbeatTime, timeSignature, onsets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bpm = try c.decode(Float.self, forKey: .bpm)
        self.beats = try c.decode([Float].self, forKey: .beats)
        self.sections = try c.decode([AudioSection].self, forKey: .sections)
        self.waveformPeaks = try c.decode([Float].self, forKey: .waveformPeaks)
        self.downbeatOffset = try c.decodeIfPresent(Int.self, forKey: .downbeatOffset) ?? 0
        self.timeSignature = try c.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) ?? .fourFour
        self.onsets = try c.decodeIfPresent([Float].self, forKey: .onsets) ?? []
        if let t = try c.decodeIfPresent(Float.self, forKey: .firstDownbeatTime) {
            self.firstDownbeatTime = t
        } else if !beats.isEmpty {
            let idx = max(0, min(self.downbeatOffset, self.beats.count - 1))
            self.firstDownbeatTime = beats[idx]
        } else {
            self.firstDownbeatTime = 0
        }
    }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

```bash
xcodebuild test -project ThePlayer.xcodeproj -scheme ThePlayer -only-testing:ThePlayerTests/TrackAnalysisTests 2>&1 | tail -20
```

Expected: all `TrackAnalysisTests` pass, including the two new tests.

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Models/TrackAnalysis.swift ThePlayerTests/TrackAnalysisTests.swift
git commit -m "feat(analysis): add onsets field to TrackAnalysis"
```

---

## Task 2: Invalidate cache entries missing onsets

**Files:**
- Modify: `ThePlayer/Analysis/AnalysisCache.swift`

Context: the existing cache has no explicit version field — it invalidates on a content signal (peak count). Add a parallel signal: if the decoded analysis has empty `onsets` but non-empty `beats` (i.e. it's a real analysis from before this feature), treat it as stale and force re-analysis.

- [ ] **Step 1: Modify `retrieve(forKey:)` to invalidate pre-onset entries**

Replace the body of the `retrieve(forKey:)` function in `ThePlayer/Analysis/AnalysisCache.swift` with:

```swift
func retrieve(forKey key: String) throws -> TrackAnalysis? {
    let url = directory.appendingPathComponent("\(key).json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let analysis = try JSONDecoder().decode(TrackAnalysis.self, from: data)

    // Invalidate entries whose peaks were extracted at the old lower
    // resolution — force re-analysis to pick up the current density.
    // The lower bound exempts tiny synthetic fixtures used by tests.
    let n = analysis.waveformPeaks.count
    if n >= 1000, n < WaveformExtractor.targetPeakCount {
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    // Invalidate entries from before onset detection shipped: they have
    // beats but no onsets. Tiny synthetic fixtures used by tests never have
    // enough peaks to trip the n >= 1000 check above, so gate this on the
    // same peak count to stay friendly to tests.
    if n >= 1000, analysis.onsets.isEmpty, !analysis.beats.isEmpty {
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    return analysis
}
```

- [ ] **Step 2: Build, confirm it compiles**

```bash
xcodebuild build -project ThePlayer.xcodeproj -scheme ThePlayer 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Analysis/AnalysisCache.swift
git commit -m "feat(cache): invalidate pre-onset analysis entries"
```

---

## Task 3: `OnsetPicker` helper + unit tests

**Files:**
- Create: `ThePlayer/Views/OnsetPicker.swift`
- Create: `ThePlayerTests/OnsetPickerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ThePlayerTests/OnsetPickerTests.swift` with:

```swift
import XCTest
@testable import ThePlayer

final class OnsetPickerTests: XCTestCase {

    func testEmptyOnsetsReturnsNil() {
        XCTAssertNil(OnsetPicker.nearestOnset(to: 1.0, in: [], pxPerSec: 100, maxPx: 30))
    }

    func testExactMatchReturnsSelf() {
        let result = OnsetPicker.nearestOnset(to: 1.0, in: [0.5, 1.0, 1.5], pxPerSec: 100, maxPx: 30)
        XCTAssertEqual(result, 1.0)
    }

    func testNearestIsChosen() {
        // 0.9 is closer to 1.0 than 0.5.
        let result = OnsetPicker.nearestOnset(to: 0.9, in: [0.5, 1.0, 1.5], pxPerSec: 100, maxPx: 30)
        XCTAssertEqual(result, 1.0)
    }

    func testEquidistantTieReturnsEarlierOnset() {
        // click at 1.0, onsets at 0.8 and 1.2 — both 0.2s away. Earlier wins.
        let result = OnsetPicker.nearestOnset(to: 1.0, in: [0.8, 1.2], pxPerSec: 100, maxPx: 100)
        XCTAssertEqual(result, 0.8)
    }

    func testOutOfRangeReturnsNil() {
        // nearest onset is 0.5s away; at 100 px/sec that's 50px > maxPx=30.
        let result = OnsetPicker.nearestOnset(to: 1.5, in: [1.0], pxPerSec: 100, maxPx: 30)
        XCTAssertNil(result)
    }

    func testZoomChangesInRangeness() {
        // Same audio gap (0.5s); fails at 100 px/s but succeeds at 200 px/s when maxPx=120.
        XCTAssertNil(OnsetPicker.nearestOnset(to: 1.5, in: [1.0], pxPerSec: 100, maxPx: 30))
        XCTAssertEqual(OnsetPicker.nearestOnset(to: 1.5, in: [1.0], pxPerSec: 200, maxPx: 120), 1.0)
    }

    func testClickBeforeFirstOnset() {
        let result = OnsetPicker.nearestOnset(to: 0.0, in: [0.1, 1.0, 2.0], pxPerSec: 1000, maxPx: 500)
        XCTAssertEqual(result, 0.1)
    }

    func testClickAfterLastOnset() {
        let result = OnsetPicker.nearestOnset(to: 5.0, in: [0.1, 1.0, 2.0], pxPerSec: 1000, maxPx: 5000)
        XCTAssertEqual(result, 2.0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project ThePlayer.xcodeproj -scheme ThePlayer -only-testing:ThePlayerTests/OnsetPickerTests 2>&1 | tail -10
```

Expected: FAIL — "Cannot find 'OnsetPicker' in scope" (file doesn't exist yet, and the test target may also need the file added).

- [ ] **Step 3: Create `OnsetPicker.swift`**

Create `ThePlayer/Views/OnsetPicker.swift` with:

```swift
import Foundation

enum OnsetPicker {
    /// Returns the onset time nearest to `time`, or `nil` if the nearest
    /// onset is farther than `maxPx` in screen pixels at zoom `pxPerSec`.
    /// Assumes `onsets` is sorted ascending. Ties resolve to the earlier onset.
    static func nearestOnset(
        to time: Float,
        in onsets: [Float],
        pxPerSec: Double,
        maxPx: Double
    ) -> Float? {
        guard !onsets.isEmpty else { return nil }

        // Binary-search the insertion point of `time`.
        var lo = 0
        var hi = onsets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if onsets[mid] < time { lo = mid + 1 } else { hi = mid }
        }

        // Compare the neighbor on either side. `lo` is the first index whose
        // onset is >= time (may be == onsets.count). The earlier candidate is
        // at lo - 1 (if it exists).
        let right: Float? = lo < onsets.count ? onsets[lo] : nil
        let left: Float? = lo > 0 ? onsets[lo - 1] : nil

        let best: Float
        switch (left, right) {
        case let (l?, r?):
            let dL = abs(time - l)
            let dR = abs(r - time)
            // Tie → earlier onset (the left one).
            best = dL <= dR ? l : r
        case let (l?, nil): best = l
        case let (nil, r?): best = r
        default: return nil
        }

        let distancePx = Double(abs(best - time)) * pxPerSec
        return distancePx <= maxPx ? best : nil
    }
}
```

- [ ] **Step 4: Add both files to the Xcode project**

Both new files must be added to the Xcode project so they compile and the test target sees them:

1. Open `ThePlayer.xcodeproj` in Xcode.
2. In the Project navigator, right-click the `ThePlayer/Views` group → "Add Files to ThePlayer…" → select `OnsetPicker.swift` → ensure "ThePlayer" target is checked → Add.
3. Right-click the `ThePlayerTests` group → "Add Files to ThePlayer…" → select `OnsetPickerTests.swift` → ensure "ThePlayerTests" target is checked (NOT the main target) → Add.
4. Save.

- [ ] **Step 5: Run the tests, verify they pass**

```bash
xcodebuild test -project ThePlayer.xcodeproj -scheme ThePlayer -only-testing:ThePlayerTests/OnsetPickerTests 2>&1 | tail -15
```

Expected: all 8 `OnsetPickerTests` pass.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Views/OnsetPicker.swift ThePlayerTests/OnsetPickerTests.swift ThePlayer.xcodeproj/project.pbxproj
git commit -m "feat(onsets): pure nearest-onset helper with screen-distance gating"
```

---

## Task 4: Essentia onset detection + refinement

**Files:**
- Modify: `ThePlayer/Analysis/EssentiaAnalyzer.h`
- Modify: `ThePlayer/Analysis/EssentiaAnalyzer.mm`

Context: Essentia exposes `OnsetDetection` (produces a detection function per frame) and `Onsets` (peak-picks the detection function to produce onset times). The returned times are at hop-size resolution (~11ms at 44.1kHz, hop=512). We'll post-refine each onset to the local short-term RMS peak in a ±10ms window of the raw samples for near-sample accuracy.

- [ ] **Step 1: Add `onsets` property to the bridge header**

Modify `ThePlayer/Analysis/EssentiaAnalyzer.h`. Replace the `@interface EssentiaResult` block with:

```objc
@interface EssentiaResult : NSObject
@property (nonatomic) float bpm;
@property (nonatomic) NSInteger downbeatOffset;
@property (nonatomic, strong) NSArray<NSNumber *> *beats;
@property (nonatomic, strong) NSArray<NSNumber *> *onsets;
@property (nonatomic, strong) NSArray<EssentiaSection *> *sections;
@end
```

- [ ] **Step 2: Add the detection + refinement pass in the analyzer**

In `ThePlayer/Analysis/EssentiaAnalyzer.mm`, add this block **immediately after** the existing `// --- BPM and beat detection ---` section (i.e. right after `delete rhythm;` on roughly line 62). It inserts a new section labeled `// --- Onset detection + sample-accurate refinement ---`.

Add this code (a full block — do not paraphrase):

```objc
        // --- Onset detection + sample-accurate refinement ---
        // Hop size 512 @ 44.1 kHz → ~11.6 ms detection-function resolution.
        // We then refine each reported onset to the local short-term RMS peak
        // in a ±10 ms window of raw samples.
        std::vector<Real> refinedOnsets;
        {
            const int onsetFrameSize = 1024;
            const int onsetHopSize = 512;
            Algorithm* odFrameCutter = factory.create("FrameCutter",
                "frameSize", onsetFrameSize,
                "hopSize", onsetHopSize);
            Algorithm* odWindowing = factory.create("Windowing",
                "type", std::string("hann"));
            Algorithm* odSpectrum = factory.create("Spectrum");
            Algorithm* onsetDetection = factory.create("OnsetDetection",
                "method", std::string("complex"),
                "sampleRate", 44100.0);

            std::vector<Real> odFrame, odWindowed, odSpec, odPhase;
            Real odValue;

            odFrameCutter->input("signal").set(audio);
            odFrameCutter->output("frame").set(odFrame);

            odWindowing->input("frame").set(odFrame);
            odWindowing->output("frame").set(odWindowed);

            odSpectrum->input("frame").set(odWindowed);
            odSpectrum->output("spectrum").set(odSpec);

            onsetDetection->input("spectrum").set(odSpec);
            onsetDetection->input("phase").set(odPhase); // unused for "complex" but must be bound
            onsetDetection->output("onsetDetection").set(odValue);

            std::vector<Real> detectionFunction;
            while (true) {
                odFrameCutter->compute();
                if (odFrame.empty()) break;
                odWindowing->compute();
                odSpectrum->compute();
                // "complex" method only reads the spectrum — phase vector may be empty.
                onsetDetection->compute();
                detectionFunction.push_back(odValue);
            }

            delete odFrameCutter;
            delete odWindowing;
            delete odSpectrum;
            delete onsetDetection;

            // Peak-pick the detection function into onset times.
            std::vector<Real> rawOnsets;
            if (!detectionFunction.empty()) {
                Algorithm* onsets = factory.create("Onsets",
                    "frameRate", 44100.0 / (Real)onsetHopSize);
                // Onsets expects a TNT::Array2D<Real> with rows = detectors, cols = frames.
                TNT::Array2D<Real> detectionMatrix(1, (int)detectionFunction.size());
                for (int i = 0; i < (int)detectionFunction.size(); i++) {
                    detectionMatrix[0][i] = detectionFunction[i];
                }
                std::vector<Real> weights; weights.push_back(1.0);
                onsets->input("detections").set(detectionMatrix);
                onsets->input("weights").set(weights);
                onsets->output("onsets").set(rawOnsets);
                onsets->compute();
                delete onsets;
            }

            // Refine each onset to the local short-term RMS peak within ±10ms.
            const Real sr = 44100.0;
            const int refineRadius = (int)(0.010 * sr); // ±10 ms window
            const int rmsWindow = (int)(0.002 * sr);    // 2 ms RMS window
            for (Real t : rawOnsets) {
                int center = (int)(t * sr);
                int lo = std::max(0, center - refineRadius);
                int hi = std::min((int)audio.size() - 1, center + refineRadius);
                if (hi - lo < rmsWindow) { refinedOnsets.push_back(t); continue; }

                // Slide a 2ms RMS window across [lo, hi] and pick the peak center.
                // Use running sum of squares for O(n) refinement.
                double sumSq = 0.0;
                for (int i = lo; i < lo + rmsWindow && i < (int)audio.size(); i++) {
                    sumSq += (double)audio[i] * (double)audio[i];
                }
                double bestRms = sumSq;
                int bestStart = lo;
                for (int i = lo + 1; i + rmsWindow <= hi; i++) {
                    sumSq -= (double)audio[i - 1] * (double)audio[i - 1];
                    sumSq += (double)audio[i + rmsWindow - 1] * (double)audio[i + rmsWindow - 1];
                    if (sumSq > bestRms) { bestRms = sumSq; bestStart = i; }
                }
                Real refined = (Real)(bestStart + rmsWindow / 2) / sr;
                refinedOnsets.push_back(refined);
            }
        }
```

- [ ] **Step 3: Populate `result.onsets` in the result-building section**

In `ThePlayer/Analysis/EssentiaAnalyzer.mm`, find the block that starts with `// --- Build result ---` and ends with `result.beats = beatArray;`. Right after `result.beats = beatArray;`, insert:

```objc
        // Onsets (sample-accurate refined times)
        NSMutableArray<NSNumber *> *onsetArray = [NSMutableArray arrayWithCapacity:refinedOnsets.size()];
        for (Real t : refinedOnsets) {
            [onsetArray addObject:@(t)];
        }
        result.onsets = onsetArray;
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -project ThePlayer.xcodeproj -scheme ThePlayer 2>&1 | tail -15
```

Expected: BUILD SUCCEEDED. If you see `Onsets` input/output name errors, check `Vendor/essentia/include/essentia/utils/extractor_music/MusicRhythmDescriptors.cpp` for the actual I/O names used there and adapt (Essentia is version-pinned in this repo).

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Analysis/EssentiaAnalyzer.h ThePlayer/Analysis/EssentiaAnalyzer.mm
git commit -m "feat(analysis): detect and refine sample-accurate onsets"
```

---

## Task 5: Thread `onsets` through `AnalysisService` + `MockAnalyzer`

**Files:**
- Modify: `ThePlayer/Analysis/AnalysisService.swift`
- Modify: `ThePlayer/Analysis/MockAnalyzer.swift`
- Modify: `ThePlayerTests/AnalysisServiceMergeTests.swift`

- [ ] **Step 1: Write a failing test — onsets survive merge unchanged**

In `ThePlayerTests/AnalysisServiceMergeTests.swift`, add at the end of the class:

```swift
func testMergePreservesOnsets() throws {
    let analyzed = TrackAnalysis(
        bpm: 120,
        beats: [0, 0.5, 1.0],
        sections: [AudioSection(label: "A", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 0)],
        waveformPeaks: [0.1],
        onsets: [0.05, 0.52, 1.03]
    )
    let edited = [AudioSection(label: "Manual", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 2)]
    let merged = AnalysisService.mergeCachedAnalysis(
        analyzed,
        userEdits: UserEdits(sections: edited)
    )
    XCTAssertEqual(merged.onsets, [0.05, 0.52, 1.03])
    XCTAssertEqual(merged.sections.first?.label, "Manual")
}
```

- [ ] **Step 2: Run the test — expect it to fail**

```bash
xcodebuild test -project ThePlayer.xcodeproj -scheme ThePlayer -only-testing:ThePlayerTests/AnalysisServiceMergeTests/testMergePreservesOnsets 2>&1 | tail -10
```

Expected: FAIL — "Extra argument 'onsets' in call" or assertion failure (merge will produce `onsets: []`).

- [ ] **Step 3: Update `AnalysisService.mergeCachedAnalysis` to preserve onsets**

In `ThePlayer/Analysis/AnalysisService.swift`, replace the existing `static func mergeCachedAnalysis(...)` with:

```swift
static func mergeCachedAnalysis(_ analysis: TrackAnalysis, userEdits: UserEdits?) -> TrackAnalysis {
    guard let edits = userEdits else { return analysis }
    let mergedSections = edits.sections.isEmpty ? analysis.sections : edits.sections
    let mergedBpm = edits.bpmOverride ?? analysis.bpm
    let mergedTimeSig = edits.timeSignatureOverride ?? analysis.timeSignature
    let mergedFirstDb = edits.downbeatTimeOverride ?? analysis.firstDownbeatTime
    return TrackAnalysis(
        bpm: mergedBpm,
        beats: analysis.beats,
        sections: mergedSections,
        waveformPeaks: analysis.waveformPeaks,
        downbeatOffset: analysis.downbeatOffset,
        firstDownbeatTime: mergedFirstDb,
        timeSignature: mergedTimeSig,
        onsets: analysis.onsets
    )
}
```

- [ ] **Step 4: Thread onsets through `EssentiaAnalyzerSwift.analyze`**

In `ThePlayer/Analysis/AnalysisService.swift`, inside `EssentiaAnalyzerSwift.analyze(...)`, find the block that builds beats:

```swift
let beats = result.beats.map { $0.floatValue }
let peaks = (try? WaveformExtractor.extractPeaks(from: fileURL)) ?? []
```

and immediately after it insert:

```swift
let onsets = (result.onsets ?? []).map { $0.floatValue }
```

Then update the `TrackAnalysis(...)` initializer call in the same function to pass `onsets: onsets`. The updated init call should read:

```swift
let analysis = TrackAnalysis(
    bpm: result.bpm,
    beats: beats,
    sections: sections,
    waveformPeaks: peaks,
    downbeatOffset: Int(result.downbeatOffset),
    timeSignature: .fourFour,
    onsets: onsets
)
```

Note: `result.onsets` is nullable because older Obj-C bridge code may return a result without it; fall back to `[]`.

- [ ] **Step 5: Add stub onsets to `MockAnalyzer`**

In `ThePlayer/Analysis/MockAnalyzer.swift`, replace the `return TrackAnalysis(...)` block with:

```swift
return TrackAnalysis(
    bpm: 120.0,
    beats: stride(from: Float(0), to: 180, by: 0.5).map { $0 },
    sections: [
        AudioSection(label: "Intro", startTime: 0, endTime: 15, startBeat: 0, endBeat: 30, colorIndex: 0),
        AudioSection(label: "Verse", startTime: 15, endTime: 45, startBeat: 30, endBeat: 90, colorIndex: 1),
        AudioSection(label: "Chorus", startTime: 45, endTime: 75, startBeat: 90, endBeat: 150, colorIndex: 2),
        AudioSection(label: "Verse", startTime: 75, endTime: 105, startBeat: 150, endBeat: 210, colorIndex: 1),
        AudioSection(label: "Chorus", startTime: 105, endTime: 135, startBeat: 210, endBeat: 270, colorIndex: 2),
        AudioSection(label: "Bridge", startTime: 135, endTime: 155, startBeat: 270, endBeat: 310, colorIndex: 3),
        AudioSection(label: "Outro", startTime: 155, endTime: 180, startBeat: 310, endBeat: 360, colorIndex: 0),
    ],
    waveformPeaks: (0..<500).map { _ in Float.random(in: 0.1...0.9) },
    onsets: stride(from: Float(0), to: 180, by: 0.5).map { $0 + 0.01 }
)
```

- [ ] **Step 6: Run the tests**

```bash
xcodebuild test -project ThePlayer.xcodeproj -scheme ThePlayer -only-testing:ThePlayerTests/AnalysisServiceMergeTests 2>&1 | tail -15
```

Expected: all tests in `AnalysisServiceMergeTests` pass, including the new one.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Analysis/AnalysisService.swift ThePlayer/Analysis/MockAnalyzer.swift ThePlayerTests/AnalysisServiceMergeTests.swift
git commit -m "feat(analysis): thread onsets through service and mock"
```

---

## Task 6: Add `onsets` parameter to `WaveformView`

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift`
- Modify: `ThePlayer/Views/ContentView.swift`

This task only plumbs the data in — the interaction (context menu, overlay) is Task 7. Splitting keeps each diff focused.

- [ ] **Step 1: Add `onsets` property to `WaveformView`**

In `ThePlayer/Views/WaveformView.swift`, add a new stored property next to `beats`:

```swift
let beats: [Float]
let onsets: [Float]
```

Insert the `let onsets: [Float]` line directly below `let beats: [Float]` (currently line 7).

- [ ] **Step 2: Pass `onsets` from `ContentView`**

In `ThePlayer/Views/ContentView.swift`, find the `WaveformView(...)` initializer around line 190 and add `onsets:` directly below `beats:`. The updated call site:

```swift
WaveformView(
    peaks: analysisService.lastAnalysis?.waveformPeaks ?? [],
    sections: analysisService.lastAnalysis?.sections ?? [],
    beats: analysisService.lastAnalysis?.beats ?? [],
    onsets: analysisService.lastAnalysis?.onsets ?? [],
    bpm: analysisService.lastAnalysis?.bpm ?? 0,
    // ... (remaining args unchanged)
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project ThePlayer.xcodeproj -scheme ThePlayer 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift ThePlayer/Views/ContentView.swift
git commit -m "feat(waveform): pipe onsets into WaveformView"
```

---

## Task 7: Right-click context menu + highlight overlay

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift`

- [ ] **Step 1: Add state for the highlighted onset + last mouse location**

In `ThePlayer/Views/WaveformView.swift`, add these `@State` properties next to the existing ones (after `@State private var waveformDragOffset: CGFloat = 0`):

```swift
@State private var mouseLocation: CGPoint?
@State private var highlightedOnset: Float?
```

- [ ] **Step 2: Track mouse location in the existing `.onContinuousHover`**

In the same file, find the `.onContinuousHover { phase in ... }` modifier attached to the waveform body (currently around line 164) and update it to also store the raw location:

```swift
.onContinuousHover { phase in
    switch phase {
    case .active(let location):
        let fraction = Float(location.x / totalWidth)
        hoverTime = fraction * duration
        hoverLocation = location
        mouseLocation = location
    case .ended:
        hoverTime = nil
        hoverLocation = nil
        mouseLocation = nil
    }
}
```

- [ ] **Step 3: Add the highlight overlay to the ZStack**

In the same file, add a new overlay rectangle as a sibling inside the ZStack, **after** the `downbeatIndicator(...)` call (currently line 85) and **before** `boundaryHandles(...)`. Insert:

```swift
if let onset = highlightedOnset, duration > 0 {
    let x = CGFloat(onset / duration) * totalWidth
    Rectangle()
        .fill(Color.accentColor.opacity(0.5))
        .frame(width: 1, height: waveHeight)
        .offset(x: x)
        .allowsHitTesting(false)
}
```

- [ ] **Step 4: Attach `.contextMenu` to the waveform body**

In the same file, find the `.gesture(DragGesture(...))` → `.onTapGesture` → `.onContinuousHover` chain. Add a `.contextMenu` modifier **before** `.onContinuousHover`:

```swift
.contextMenu {
    let pxPerSec = Double(totalWidth) / Double(max(duration, 0.001))
    let clickTime: Float = {
        guard let loc = mouseLocation, totalWidth > 0 else { return 0 }
        return Float(loc.x / totalWidth) * duration
    }()
    let nearest = OnsetPicker.nearestOnset(
        to: clickTime,
        in: onsets,
        pxPerSec: pxPerSec,
        maxPx: 30.0
    )
    Button(action: {
        if let t = nearest {
            onSetDownbeat?(t)
        }
    }) {
        Text("Set 1 here")
        if nearest == nil { Text("No onset nearby") }
    }
    .disabled(nearest == nil)
}
```

- [ ] **Step 5: Update `highlightedOnset` when the menu appears**

SwiftUI's `.contextMenu` does not expose open/close events directly. We approximate by computing the highlighted onset from the current mouse location every time the body re-renders, and clear it via `.onDisappear` tied to a hidden canary — in practice we can drive it off `mouseLocation` changes.

Add this modifier to the same waveform body (next to the `.contextMenu` you just added):

```swift
.onChange(of: mouseLocation) { _, newLoc in
    guard let loc = newLoc, totalWidth > 0, duration > 0 else {
        highlightedOnset = nil
        return
    }
    let pxPerSec = Double(totalWidth) / Double(max(duration, 0.001))
    let clickTime = Float(loc.x / totalWidth) * duration
    highlightedOnset = OnsetPicker.nearestOnset(
        to: clickTime,
        in: onsets,
        pxPerSec: pxPerSec,
        maxPx: 30.0
    )
}
```

Note: this makes the highlight **always** render on the nearest in-range onset whenever the cursor hovers the waveform — slightly more visible than "only while the menu is open". This is a pragmatic trade-off for SwiftUI on macOS (no reliable hook for menu open/close). If during manual testing the hover highlight feels too visible, replace `.onChange` with a tracked focus flag driven by `onHover` over the menu's parent — but start with this.

- [ ] **Step 6: Build, smoke-test by running the app**

```bash
xcodebuild build -project ThePlayer.xcodeproj -scheme ThePlayer 2>&1 | tail -5
```

Then launch the app from Xcode. Load a track. Right-click near a drum hit → expect "Set 1 here" enabled; selecting it should snap the red bar-1 line to the attack.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift
git commit -m "feat(waveform): right-click to set 1 at nearest onset"
```

---

## Task 8: Manual verification checklist

**Files:** None — verification only.

- [ ] **Step 1: Delete the cache to force re-analysis**

```bash
rm -rf "$HOME/Library/Application Support/The Player/cache"
```

- [ ] **Step 2: Run through the manual checks**

Launch the app and verify each of these:

1. Open a track with clear drum hits. Wait for analysis to complete (progress bar).
2. Right-click on a visible drum-hit peak → context menu shows "Set 1 here" enabled → select → red bar-1 line snaps precisely onto the attack.
3. Right-click in a near-silent region → context menu shows disabled "Set 1 here" with subtitle "No onset nearby".
4. Right-click ~25pt from an attack at x50 zoom → enabled. At x1 zoom same attack's pixel distance may exceed 30pt → disabled.
5. Hover near an onset without right-clicking → the thin accent-color highlight line appears on the nearest in-range onset; moving farther away clears it.
6. Existing drag-to-align the waveform still works. Combine: drag to roughly align, then right-click the nearest visible attack for precise snap.
7. Quit & relaunch: onsets survive — right-click continues to work instantly with no re-analysis.
8. At maximum zoom, the red bar-1 line lands on the visual sample peak (not ~10ms before it) — confirms refinement.

- [ ] **Step 3: If all checks pass, tag the feature branch for traceability (optional)**

```bash
git log --oneline -n 10
```

Confirm all commits from Tasks 1–7 land cleanly on the feature branch.

---

## Non-goals reminder

- No always-visible onset ticks (only the nearest in-range onset highlights on hover).
- No keyboard shortcut for pick.
- No adjustable snap radius (30pt hard-coded).
- No "Reset to analyzer downbeat" menu item.
- No onset detection on sections/loops — track-wide only.
