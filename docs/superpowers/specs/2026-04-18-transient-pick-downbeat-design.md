# Transient-Pick Downbeat

## Goal

Let the user set bar 1 with sample-accurate precision by right-clicking a transient (attack event) on the waveform. Complements the existing drag-to-align: drag for coarse placement, right-click a transient for fine, precise placement.

The existing alignment drag is good for sliding the grid onto the beat, but it's pixel-accurate, not audio-accurate. "Very precise" requires snapping to real audio onsets, not analyzer beats (analyzer beats are quantized to BPM and are exactly what the user may be correcting).

## Scope

Adds a new analyzer output (`onsets`), a right-click menu on the waveform body, and a hover highlight. `firstDownbeatTime` semantics and persistence path are unchanged — this feature produces a new value to feed into the existing `onSetDownbeat(...)` pipeline.

## Architecture

### New data on `TrackAnalysis`

```swift
let onsets: [Float]   // audio times (seconds) of detected attack events
```

Parallel to `beats`. Persisted alongside the rest of `TrackAnalysis` in the cache.

### New analysis pass

In [EssentiaAnalyzer.mm](ThePlayer/Analysis/EssentiaAnalyzer.mm):

1. Run Essentia `OnsetDetection` (method `complex` — picks up both percussive and tonal attacks; `superflux` is a fallback if `complex` misses too many attacks in testing) over the mono mix.
2. Apply `Onsets` to the detection function to get onset frames at hop-size resolution (~11ms at hop 512 / 44.1kHz).
3. **Precision refinement:** for each reported onset, search a ±10ms window of raw samples for the local maximum of short-term RMS (window ≈ 2ms). Use that sample index as the refined onset time. This moves onsets from ~11ms hop resolution to near-sample accuracy.

Expose the refined onset list through the existing `EssentiaAnalysisResult` bridge as `NSArray<NSNumber *> *onsets`.

### Cache

- Bump `AnalysisCache` schema version. Existing cached tracks re-analyze on next open to populate `onsets`.
- `onsets` is `Codable` and encoded alongside `beats` in the persisted blob (same `CodingKeys` pattern as existing fields; default to empty array on decode for forward-compat safety, but the version bump should prevent that path in practice).

### Files

**Modified:**
- [EssentiaAnalyzer.h](ThePlayer/Analysis/EssentiaAnalyzer.h) — add `onsets` property on the result class.
- [EssentiaAnalyzer.mm](ThePlayer/Analysis/EssentiaAnalyzer.mm) — new detection + refinement pass.
- [TrackAnalysis.swift](ThePlayer/Models/TrackAnalysis.swift) — add `onsets: [Float]` property + Codable.
- [AnalysisCache.swift](ThePlayer/Analysis/AnalysisCache.swift) — version bump.
- [AnalysisService.swift](ThePlayer/Analysis/AnalysisService.swift) — pass onsets through from bridge to `TrackAnalysis`.
- [MockAnalyzer.swift](ThePlayer/Analysis/MockAnalyzer.swift) — stub onsets for previews/tests.
- [WaveformView.swift](ThePlayer/Views/WaveformView.swift) — context menu, highlight overlay, mouse-location tracking, wiring.
- [ContentView.swift](ThePlayer/Views/ContentView.swift) — thread `onsets` through to `WaveformView`.

**Added:**
- `ThePlayer/Views/OnsetPicker.swift` — pure nearest-onset helper.
- `ThePlayerTests/OnsetPickerTests.swift` — unit tests for the helper.

## Interaction

### Right-click on waveform body

Opens a context menu with one new item:

- **"Set 1 here"**
  - **Enabled** when the nearest onset is within **30 screen points** of the click location. Screen-distance (not audio-time distance) gating keeps the feel consistent across zoom levels.
  - **Disabled** with subtitle "No onset nearby" otherwise.
  - Activating the item sets `firstDownbeatTime = nearestOnsetTime` and calls the existing `onSetDownbeat(...)` to persist via `UserEditsStore`.

The menu contains only this item for v1. Future items (reset to analyzer, nudge) can stack on later.

### Hover feedback while menu is open

When the context menu opens:

- If a valid nearest onset exists (within 30pt), render a thin full-height vertical line at that onset's content x-position as a subtle highlight. Style: accent color, 1pt width, ~50% opacity. Drawn as a sibling in the waveform `ZStack` after the existing bar-1 red line; `allowsHitTesting(false)`.
- Highlight disappears when the menu closes (either on selection or dismiss).
- If no onset is in range, no highlight — consistent with the disabled menu item.

### Coexistence with existing gestures

- Left-click seek: unchanged.
- Drag-to-align waveform body: unchanged. Complements this feature (coarse drag → precise right-click).
- Section boundary handle drag: unchanged (child-gesture priority).
- Pending-loop / set-downbeat modes: unchanged.
- Right-click is a new gesture type and doesn't compete with existing left-click/drag handling.

## Capturing the click location

SwiftUI's `.contextMenu` doesn't expose the click location. Track the last mouse position on the waveform via `.onContinuousHover` (SwiftUI) — storing the latest hover point in a `@State var mouseLocation: CGPoint?`. When the context menu opens, use that stored point as the "right-click location" for computing the nearest onset. This is cheap and matches the pattern for hover-aware waveform UI already in the project.

## Nearest-onset math

New pure helper (`OnsetPicker.swift`):

```swift
/// Returns the onset time nearest to `time`, or nil if the nearest one
/// is farther than `maxPx` in screen pixels at zoom `pxPerSec`.
/// Ties (two onsets exactly equidistant) resolve to the earlier onset.
func nearestOnset(
    to time: Float,
    in onsets: [Float],
    pxPerSec: Double,
    maxPx: Double
) -> Float?
```

Implementation: binary-search for the insertion point of `time`, compare left/right neighbors, pick the closer (earlier on tie), reject if `|nearest - time| * pxPerSec > maxPx`.

## Constants

- `onsetPickMaxScreenDistance = 30.0` (points). Hard-coded for v1.
- Onset refinement window: ±10ms around detected onset; RMS window 2ms.

## Testing

### Unit tests (`OnsetPickerTests`)

1. Empty onsets → `nil`.
2. Single onset exactly at click → that onset.
3. Two equidistant onsets → earlier one (deterministic tie-break).
4. Nearest onset beyond `maxPx` at the current zoom → `nil`.
5. Same onset set, different zooms: in-range at x50, out-of-range at x1.
6. Click before first onset / after last onset — both boundaries handled.

### Analyzer tests

- `TrackAnalysisTests` — round-trip encode/decode including `onsets`.
- `AnalysisServiceMergeTests` — verify onsets pass through merge unchanged (analyzer-derived, never touched by user edits).

### Manual checks

1. Right-click on a clear drum hit → menu shows "Set 1 here" enabled → select → red bar-1 line snaps precisely onto the attack.
2. Right-click in silence / between attacks → menu shows the item disabled with "No onset nearby".
3. Right-click ~25pt from an attack at x50 zoom → enabled; at x1 zoom the same audio distance may exceed 30pt → disabled. Screen-distance gating feels right.
4. Highlight appears on the correct onset as the menu opens, and disappears on dismiss.
5. Existing drag-to-align still works. Use right-click for fine correction after a coarse drag.
6. Quit & relaunch: onsets load from cache, right-click works instantly with no re-analysis.
7. First-time analysis of a new track: progress indicator completes normally, onsets are populated.
8. At maximum zoom, the red bar-1 line lands on the visual sample peak (not ~11ms before it) — confirms the refinement pass is working.

## Non-goals (v1)

- No always-visible onset ticks across the waveform. Highlight only appears on nearest onset while the menu is open.
- No keyboard shortcut for pick (only right-click menu).
- No adjustable snap radius (hard-coded 30pt).
- No onset detection on loop regions or sections — track-wide only.
- No "Reset to analyzer downbeat" menu item (future).
- No multi-pick / tap-multiple-onsets UX.
- No user-adjustable detection sensitivity / method switching.
- No negative `firstDownbeatTime`; clamp at 0 (unchanged from existing behavior).
