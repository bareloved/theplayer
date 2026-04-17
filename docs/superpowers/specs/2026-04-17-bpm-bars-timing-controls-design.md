# BPM, Bars, and Timing Controls

**Date:** 2026-04-17
**Status:** Design approved (user delegated: "just build it i trust you")

## Problem

Bar lines in the waveform are wrong for many songs. Root causes:

- **Downbeat isn't detected.** `RhythmExtractor2013` outputs beats but not downbeats, so the UI hardcodes "every 4 beats = 1 bar starting at beats[0]" — arbitrary and often off-phase.
- **Time signature assumed 4/4.** Songs in 3/4, 6/8, 12/8 get wrong bar counts.
- **No manual override** for the rare half/double-time BPM misdetection (e.g., 90 BPM detected as 180).

## Goals

- Correct bar lines on most songs without manual intervention (downbeat heuristic).
- Always-correct bar lines when the user intervenes — one-click fixes for the common cases.
- Zero regression in the section editor, loop regions, or snap — they already operate on beat indices and times, not bar math.

## Non-Goals

- Auto-detecting time signature (hard, low accuracy, manual override is fast).
- Fixing BPM detection itself (algorithm stays; we only add manual override).
- Beat-drift tracking over the song (assumed constant BPM).

## Data Model

### `TimeSignature`

New type:

```swift
struct TimeSignature: Codable, Equatable, Hashable {
    let beatsPerBar: Int
    let beatUnit: Int  // 4 for quarter, 8 for eighth
    static let fourFour   = TimeSignature(beatsPerBar: 4, beatUnit: 4)
    static let threeFour  = TimeSignature(beatsPerBar: 3, beatUnit: 4)
    static let sixEight   = TimeSignature(beatsPerBar: 6, beatUnit: 8)
    static let twelveEight = TimeSignature(beatsPerBar: 12, beatUnit: 8)
    static let twoFour    = TimeSignature(beatsPerBar: 2, beatUnit: 4)
    static let presets: [TimeSignature] = [.fourFour, .threeFour, .sixEight, .twelveEight, .twoFour]
}
```

### `TrackAnalysis` (extend)

```swift
struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]
    let downbeatOffset: Int         // NEW - default 0, set by analyzer heuristic
    let timeSignature: TimeSignature // NEW - default .fourFour

    // Legacy decode: absent fields default to 0 / fourFour.
}
```

### `UserEdits` (extend)

```swift
struct UserEdits: Codable, Equatable {
    static let currentSchemaVersion: Int = 2  // bump from 1

    var sections: [AudioSection]
    var bpmOverride: Float?                    // NEW - nil = use analyzer value
    var downbeatOffsetOverride: Int?           // NEW
    var timeSignatureOverride: TimeSignature?  // NEW
    var modifiedAt: Date
    var schemaVersion: Int
}
```

Schema bump: existing v1 sidecars decode cleanly (missing fields become nil). Future load of v2+ sidecar into older app logs warning and ignores per `UserEditsStore.retrieve`.

## Analyzer: Downbeat Heuristic

Added in `EssentiaAnalyzer.mm` after beat detection. Only picks among `beatsPerBar` (4) offsets for now.

```
For each candidate offset ∈ 0..3:
  score = 0
  For each i in beats where i % 4 == offset:
    score += low_frequency_onset_strength_at(beats[i])
  offsets[offset] = score
Pick offset with highest score.
```

Low-frequency onset strength: sum of positive spectral flux in the 20-200 Hz band at each beat time. Captures kick drums, which typically land on downbeats in most genres. Uses the spectrum frames already computed in the existing pipeline.

Outputs `downbeatOffset: Int` on `EssentiaResult`; Swift copies it into `TrackAnalysis`.

## Merge & Persistence

`AnalysisService.mergeCachedAnalysis(_:userEdits:)` already overlays sections. Extend to also overlay bpm / downbeatOffset / timeSignature when the corresponding override is non-nil:

```swift
static func mergeCachedAnalysis(_ a: TrackAnalysis, userEdits: UserEdits?) -> TrackAnalysis {
    guard let edits = userEdits else { return a }
    return TrackAnalysis(
        bpm: edits.bpmOverride ?? a.bpm,
        beats: a.beats,
        sections: edits.sections.isEmpty ? a.sections : edits.sections,
        waveformPeaks: a.waveformPeaks,
        downbeatOffset: edits.downbeatOffsetOverride ?? a.downbeatOffset,
        timeSignature: edits.timeSignatureOverride ?? a.timeSignature
    )
}
```

New write path:

```swift
func saveTimingOverrides(bpm: Float?, downbeatOffset: Int?, timeSignature: TimeSignature?) throws
```

Loads the current sidecar (if any), patches the three optional fields, writes back. Keeps sections intact. `hasUserEditsForCurrent` stays true if any field is set.

## UI

### TransportBar: Timing Controls (utility row)

Cluster of compact controls, right after the existing Snap button:

- **BPM readout + override:** `91 BPM` text; click to edit inline (TextField with numeric filter). Two small buttons next to it: `÷2`, `×2`. Each halves/doubles the current BPM and saves to sidecar.
- **Time signature dropdown:** `4/4 ▼` — menu of presets (4/4, 3/4, 6/8, 12/8, 2/4). Picking one saves.
- **Downbeat shift:** `◀` `▶` — nudge `downbeatOffset` by ±1 (modulo `beatsPerBar`). Updates bar lines live. Saves on release.
- **Set Downbeat button:** `⌖` — enters "click a beat" mode for one click. Clicking any beat on the waveform computes `downbeatOffset = beatIndex % beatsPerBar`, saves, exits mode.

Reset (per-field): right-click any of these controls → "Reset to auto-detected". Uses a menu, not a separate button, to keep the row compact.

### WaveformView: Bar Line Computation

Replace:
```swift
private var barPositions: Set<Float> {
    guard beats.count >= 4 else { return [] }
    let bars = stride(from: 0, to: beats.count, by: 4).map { beats[$0] }
    return Set(bars.map { ($0 * 100).rounded() / 100 })
}
```

with:
```swift
private var barPositions: Set<Float> {
    let bpb = timeSignature.beatsPerBar
    guard beats.count >= bpb else { return [] }
    let bars = stride(from: downbeatOffset, to: beats.count, by: bpb).map { beats[$0] }
    return Set(bars.map { ($0 * 100).rounded() / 100 })
}
```

New props on `WaveformView`: `downbeatOffset: Int`, `timeSignature: TimeSignature`, `isSettingDownbeat: Bool`, `onSetDownbeat: ((Int) -> Void)?`. Wired through `ContentView` from `analysisService.lastAnalysis` (which is already the merged version).

"Click a beat" mode: when `isSettingDownbeat` is true, tap converts click x → nearest beat index → calls `onSetDownbeat(beatIndex)`. Visual cue: cyan border like the existing loop-setting mode.

### Dependent Places

- `SnapDivision.snapPositions(...)` — takes `beatsPerBar` parameter (was hardcoded 4).
- `AudioSection.barCount` — compute as `(endBeat - startBeat) / timeSignature.beatsPerBar`; since `AudioSection` doesn't know the time signature, pass it in as a function param or compute at render time from analysis. Simplest: move `barCount` out of the model into the rendering call site (or a view helper).

## Testing

**Unit:**
- `TimeSignature.fourFour.beatsPerBar == 4`, etc.
- `TrackAnalysis` legacy JSON (no `downbeatOffset`, no `timeSignature`) decodes with defaults.
- `UserEdits` v1 JSON (no override fields) decodes with nils; schemaVersion still considered valid on load when it's ≤ currentSchemaVersion (current file guards on `> currentSchemaVersion`).
- `AnalysisService.mergeCachedAnalysis` applies each override independently; nil overrides pass through analyzer values.
- `AnalysisService.saveTimingOverrides` patches without clobbering sections.

**Manual:**
- Load a track that previously had wrong bars. Auto downbeat should land on audible beat 1 more often than not. If wrong, `◀` / `▶` or `⌖ Set Downbeat` fixes it in one click.
- Verify 3/4 and 6/8 dropdown renders correct bar count in section editor.
- `÷2` on a doubled-BPM track halves display; re-open song → stays halved.
- Right-click each control → "Reset to auto-detected" → reverts.

## Out of Scope

- Auto time-signature detection.
- BPM drift tracking.
- Multiple time signatures per song.
