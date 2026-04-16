# Section Analyzer Improvements & Manual Editor

**Date:** 2026-04-16
**Status:** Design approved, awaiting implementation plan

## Problem

The current section analyzer in `EssentiaAnalyzer.mm` produces unreliable results:

1. **Boundaries are roughly on-beat but miss real transitions.** SBic detects timbral drift, not musical structure — so the start of a verse, the chorus, or a C-part can be missed entirely.
2. **Labels are fake.** "Verse" / "Chorus" / "Intro" / "Outro" are assigned positionally based on section count (see [EssentiaAnalyzer.mm:189-202](../../../ThePlayer/Analysis/EssentiaAnalyzer.mm)). There is no acoustic classification — the 2nd section of 4 is *always* labeled "Verse" regardless of what's actually there.

We need to (a) make the analyzer materially better, and (b) accept that no automated analyzer will ever be perfect, so give users a fast way to fix sections by hand and persist their edits.

## Goals

- Replace section detection with a repetition-aware algorithm so the chorus, verse, and unique parts (bridge, C-part) are detected as such.
- Provide an explicit "Edit Sections" mode in the waveform view for renaming, dragging boundaries, adding/deleting/reordering sections, recoloring, undo/redo, and reset.
- Persist user edits in a sidecar file that overrides analyzer output on load, without mutating the analyzer cache or the user's audio files.
- Re-running the analyzer must not clobber manual edits.

## Non-Goals

- Cloud or hosted ML analyzers (offline-only, per existing architecture).
- Editing beats / BPM / waveform peaks — only sections.
- Cross-machine sync of user edits.
- Embedding edits in audio file tags.

## Architecture

Three coordinated changes, each independently shippable behind the others:

1. **Analyzer upgrade** in `EssentiaAnalyzer.mm` — replace the SBic block with a self-similarity matrix (SSM) + Foote novelty pipeline; cluster resulting segments to label by repetition.
2. **New persistence layer** — `UserEditsStore` writes `<hash>.user.json` sidecars next to `AnalysisCache`. `AnalysisService` merges on load: cache provides base `TrackAnalysis`, sidecar overrides `sections`.
3. **New "Edit Sections" mode** in `WaveformView` — toggled from the transport bar. Adds boundary handles, an editor toolbar, a label inspector, and an `UndoManager`-backed edit history. Edits debounce-write to the sidecar.

`TrackAnalysis` stays unchanged — sections remain `[AudioSection]`. The override happens at load time, so downstream rendering, loop regions, etc. don't need to know whether sections came from the analyzer or the user.

## Component 1 — Improved Analyzer

Replace the SBic block at [EssentiaAnalyzer.mm:101-127](../../../ThePlayer/Analysis/EssentiaAnalyzer.mm) with a repetition-aware pipeline.

### Features (per beat)

- **HPCP** (chroma) — captures harmonic / chord content. Strongest cue for "this is the same chorus."
- **MFCC mean** — captures timbre (drums in vs. out, vocals vs. instrumental).
- Concatenate into one feature vector per beat (beat-synchronous: average frame-level features between consecutive ticks from `RhythmExtractor2013`).

### Self-Similarity Matrix

N×N cosine-similarity matrix over beat-synchronous features. Repeating sections appear as bright off-diagonal stripes.

For a 4-min track at ~480 beats this is ~230k cells — trivial; total analysis time stays within a few seconds.

### Boundary Detection (Foote Novelty)

Slide a checkerboard kernel along the SSM diagonal to produce a novelty curve. Peaks = transitions.

- Pick peaks with adaptive threshold (mean + k·std, tune k).
- Snap each peak to the nearest beat from `ticks`.
- Enforce a minimum section length (e.g. 4 bars at the detected BPM).

### Section Labeling by Repetition

Cluster segments by mean-feature cosine similarity using simple agglomerative clustering (threshold ~0.85). Segments in the same cluster share a label group.

Heuristic mapping from clusters to human labels:

- Largest cluster (most repetitions, mid- or high-energy) → **Chorus**
- Cluster appearing between choruses → **Verse**
- First segment if unique → **Intro**; last if unique → **Outro**
- Unique mid-song segment → **Bridge**
- Anything unmatched → **Section N** (user renames)

This is still imperfect, but it'll catch the chorus repetition and the missing C-part — the C-part shows up as its own unique cluster instead of being silently merged.

### Output

Same `EssentiaResult` shape; no Swift-side changes from this component.

## Component 2 — User Edits Sidecar

### New Type

`ThePlayer/Analysis/UserEditsStore.swift`:

```swift
struct UserEdits: Codable, Equatable {
    var sections: [AudioSection]
    var modifiedAt: Date
    var schemaVersion: Int  // start at 1
}

final class UserEditsStore {
    init(directory: URL? = nil)
    func store(_ edits: UserEdits, forKey key: String) throws
    func retrieve(forKey key: String) throws -> UserEdits?
    func delete(forKey key: String) throws
    func exists(forKey key: String) -> Bool
}
```

### Storage Location

`Application Support/The Player/cache/<hash>.user.json` — same directory as `AnalysisCache` so backup/clear behavior matches. Same `AnalysisCache.fileHash(for:)` keying.

### Merge on Load

In `AnalysisService` where it currently returns the cached `TrackAnalysis`:

```swift
let analysis = try cache.retrieve(forKey: hash)
if let edits = try userEdits.retrieve(forKey: hash) {
    return analysis.with(sections: edits.sections)
}
return analysis
```

Add `TrackAnalysis.with(sections: [AudioSection]) -> TrackAnalysis` helper. Everything downstream remains unaware of the override.

### Write Triggers (debounced 500ms)

- Boundary drag end
- Label change committed
- Color change
- Add / delete / reorder
- Reset → calls `delete(forKey:)`, then re-emits the unedited analysis

### Re-Analysis Behavior

If the user runs analysis again on a track that has user edits:

- New analyzer output replaces the cache.
- Sidecar is **not** deleted.
- Sidecar continues to override on load.
- Surface a banner above the waveform: *"Analyzer re-ran — your manual edits are still applied. [Discard edits]"*. Discard → confirmation → `userEdits.delete(forKey:)` → reload.

### Schema Versioning

`schemaVersion: 1` initially. On unknown future version → ignore sidecar, log warning. Migration logic added when needed.

## Component 3 — "Edit Sections" Mode UI

### Entry

A pencil/edit icon button in the transport bar (and right-click → "Edit Sections" on the section strip) toggles `WaveformView` into `isEditingSections` state.

### Visual State Changes

- Section strip gets a subtle outline; rest of UI dims slightly to signal modal state.
- Each boundary between sections gets a **draggable handle** (vertical bar with grab affordance).
- Each section becomes click-selectable; selected section shows a colored outline.
- Floating **toolbar** above the waveform: `[+ Add] [⌫ Delete] [↶ Undo] [↷ Redo] [⟲ Reset] [✓ Done]`.
- **Label inspector** panel (right side or floating): free-text label field with autocomplete dropdown of presets (Intro, Verse, Pre-Chorus, Chorus, Bridge, Solo, Breakdown, Drop, Outro), and a color swatch picker.

### Operations

| Operation | Behavior |
|---|---|
| Drag boundary | Moves boundary; snaps to nearest beat; hold ⌥ to disable snap. Updates `endBeat`/`startBeat` of adjacent sections. |
| Add | Splits selected section at playhead (or click position) snapped to beat. New section default label "Section", neutral color. |
| Delete | Removes selected section, merging range into previous (or next, if first). Disabled if only one section. |
| Reorder | Drag section *body* horizontally past a neighbor to swap label/color. |
| Color | Swatch picker in inspector. Auto-assigns on label change *unless* user has manually picked a color this session. |
| Reset | Confirmation dialog → `userEdits.delete(forKey:)` → reload from analyzer cache. |
| Done | Exits the mode. |

### Boundary Drag Constraints

- Cannot drag past adjacent boundary (min section length: 1 beat).
- First section always starts at 0; last always ends at audio duration. Outer edges not draggable.
- Snap to nearest beat using `TrackAnalysis.beats`; hold ⌥ for sub-beat precision.

### Playback During Edit

- Audio keeps playing; spacebar still play/pause.
- Loop regions preserved but locked from edit while in section-edit mode.
- Keyboard shortcuts that conflict (e.g. delete) scoped to section operations only while in edit mode.

### Undo / Redo

SwiftUI `UndoManager` registers each operation as a single undoable action. `⌘Z` / `⇧⌘Z` work in edit mode. Undo stack clears on exit.

## Data Model Changes

### `AudioSection` — Add Stable ID

Current `id` is `"\(label)-\(startTime)"`, which changes on rename or boundary drag. For undo/redo and selection persistence, add:

```swift
let stableId: UUID
```

- Generated on creation; Codable.
- Old cached analyses without `stableId` get one assigned at load (decode with default).
- Existing computed `id` can stay for backward compatibility or be removed if nothing depends on it.

### `LoopRegion` — Verify Independence

Loops reference time ranges, not section IDs (per [LoopRegion.swift](../../../ThePlayer/Models/LoopRegion.swift)). Section edits should not break loops. Quick verification during implementation.

## Testing

**Unit:**
- `UserEditsStore` round-trip (store / retrieve / delete / exists).
- `AnalysisService` merge logic — sidecar overrides cache; missing sidecar passes through; corrupt sidecar logs and falls back.
- Boundary drag math — snap to beat, min length, edge constraints.
- Add / delete invariants — total time coverage preserved, no gaps, no overlaps.
- Analyzer's clustering produces stable labels for a known synthetic SSM (golden test).

**Manual:**
- Real-world tracks across genres (EDM, rock, jazz, hip-hop) — automated section accuracy isn't measurable in unit tests.
- Re-analysis with sidecar present → banner appears, edits preserved, discard works.
- Edit during playback → audio uninterrupted, spacebar works.
- Undo/redo across all operation types.

## Open Questions

None at design time — surfaced ones resolved in Section 5 of the brainstorming session. Implementation plan will surface concrete questions per task.
