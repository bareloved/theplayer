# Manual Section Editing — Design

**Date:** 2026-04-22
**Status:** Approved for planning
**Supersedes:** `2026-04-16-section-analyzer-improvements-and-manual-editor-design.md` (auto-analyzer approach abandoned)

## Problem

The analyzer-produced sections are low quality — they rarely match what the user actually hears as section boundaries, and users end up correcting every track. The current manual editor is mode-gated (Enter/Done), leans on a separate inspector panel, and its primary create action (the "Add" toolbar button + split-at-playhead) is indirect. The result: users fight the analyzer output and the editor.

## Goal

Replace the analyzer as the source of sections with a direct, modifier-gated gesture on the waveform, and collapse the editor UI so editing is ambient rather than mode-gated. One headline interaction: **hold Option and drag across the waveform to create a section.**

## Non-Goals

- Automatic section detection of any kind (stripped entirely).
- Sparse sections / gaps between sections — the model remains a full partition of `[0, duration]`.
- Cross-track section templates.

## Decisions (from brainstorming)

1. **Partition model retained.** Sections tile `[0, duration]`. Extending one shrinks its neighbor.
2. **Option+drag creates a section** with carve-out semantics: engulfed sections are deleted, partially-overlapped sections are trimmed, an in-section drag produces a 3-way split.
3. **Ambient editing.** No Enter/Done mode. All gestures are modifier-gated or target explicit UI (label badges, boundary handles).
4. **Inline rename at creation.** New section shows an auto-focused label field. Enter commits, Esc keeps default.
5. **Auto-analyzer stripped.** No section detection call, no fallback button. Fresh tracks start with a single "Untitled" section spanning the full duration.
6. **Inspector removed.** Rename via double-click label; color derives from label preset; right-click for context actions (Rename, Change color ▸, Delete).
7. **Label click selects + loops.** Clicking a section's label badge toggles selection and sets `LoopRegion` to that section's range. Clicking the same badge again deselects and clears the loop.
8. **Migration:** ignore `TrackAnalysis.sections` entirely on load. Old cached analyzer sections do not surface; empty `UserEdits.sections` yields the single default "Untitled" section.

## Data Model

No schema changes. `AudioSection` unchanged. `UserEdits.sections` remains the only persisted source of truth for sections.

Baseline state when `UserEdits.sections` is empty: the UI synthesizes a single in-memory `AudioSection(label: "Untitled", startTime: 0, endTime: duration, startBeat: 0, endBeat: lastBeatIndex, colorIndex: 0)`. This synthesized section is **not** written to disk until the user first mutates; keeps the on-disk sidecar clean and preserves "has the user touched sections yet?" as a meaningful signal.

## Gesture Grammar (waveform surface)

| Input | Action |
|---|---|
| Plain click | Seek (snaps to nearest beat if `snapToGrid`) |
| Plain drag | No-op |
| Cmd + drag | Align first-downbeat (existing) |
| **Option + drag** | **Create section over drag range** (snaps endpoints if `snapToGrid`) |
| Click on section label badge | Toggle: select + set loop to section; clicking selected section → deselect + clear loop |
| Double-click section label badge | Inline rename |
| Right-click on section band or badge | Context menu: Rename · Change color ▸ · Delete |
| Drag boundary handle | Move boundary (existing) |
| ⌫ / ⌘⌫ with section selected | Delete selected section |
| ⌘Z / ⇧⌘Z | Undo / redo (routed to `vm.undoManager`) |
| Esc with section selected | Deselect + clear loop |

Modifier state is read from `NSEvent.modifierFlags` at drag start (same pattern already used by Cmd-drag for downbeat alignment). If neither Cmd nor Option is held, a drag is inert.

### Minimum drag distance

Option+drag requires **≥ 8 px** of travel before it commits on release; shorter drags cancel silently. Prevents accidental hair-thin sections from a mis-click.

### Snap behavior

When `snapToGrid` is on, both endpoints snap to the nearest beat in `TrackAnalysis.beats` on commit. The in-flight preview band also renders at snapped positions so the user sees what they'll get. When off, endpoints are exact seconds.

## `SectionsViewModel` (renamed from `SectionEditorViewModel`)

Owned by `ContentView` for the lifetime of a loaded track. No longer optional — always present once a track is loaded.

**New method:**

```swift
func createSection(startTime: Float, endTime: Float, snapToBeat: Bool) -> UUID?
```

Semantics:
1. Normalize `(s, e) = (min, max)` and clamp to `[0, duration]`.
2. If `snapToBeat`, snap each to nearest beat.
3. If `e - s < minLen`, return `nil` (no-op).
4. For each existing section that overlaps `(s, e)`:
   - Fully engulfed (`existing.startTime >= s && existing.endTime <= e`) → delete it.
   - Partial left overlap → set `existing.endTime = s`.
   - Partial right overlap → set `existing.startTime = e`.
   - Range entirely inside one section → split into up to three pieces `[before, new, after]`. If `before` is shorter than `minLen` it's dropped and the new section's `startTime` extends to the original section's `startTime`. If `after` is shorter than `minLen` it's dropped and the new section's `endTime` extends to the original section's `endTime`.
5. Insert the new section with `label: ""`, rotating `colorIndex` (next index not already used by an immediate neighbor, to avoid color collisions).
6. Recompute `startBeat`/`endBeat` for all affected sections.
7. Wrap the entire operation in one `applyChange` undo group labeled "Add Section". Return the new section's `stableId`.

**Existing methods kept:** `rename`, `recolor`, `moveBoundary`, `delete`, `replaceAll`.
**Removed:** `reorder` (visual order is time order; explicit reorder is dead weight once labels are free-form).

**Delete invariant:** `delete` continues to refuse if only one section remains; the track always has at least one section covering the full duration.

## Analyzer pipeline changes

- Remove the section-detection call in the Essentia bridge and any associated buffers/dependencies.
- `TrackAnalysis.sections` field stays on the struct for Codable compatibility with already-cached files we don't want to invalidate mid-session, but `AnalysisService` always produces `[]` and **never reads `TrackAnalysis.sections` when deriving the active partition**.
- `MockAnalyzer` drops section output.
- `AnalysisService.hasUserSectionEdits` becomes equivalent to "`UserEdits.sections` is non-empty", since the analyzer baseline is always empty.
- `AnalysisServiceMergeTests` section-merge cases rewritten as "empty-analyzer + user-sections → user-sections".

## UI surface

### New
- **Section label badge** rendered inside each band at top-left, inset ~4 px from the band's left and ~3 px from top. Pill fill uses `section.color.opacity(0.6)`; text color picked for contrast. Truncates with `…`; hides entirely if the band is narrower than ~20 px. 2 px outline in section color when selected.
- **Hit target on the badge**: click (toggle select+loop), double-click (inline rename), right-click (context menu).
- **Inline rename field** replaces the pill text when active; Enter commits, Esc cancels; auto-focuses immediately after Option+drag creates a new section.
- **Option+drag preview**: translucent band (same color as the next rotating palette slot) with a dashed border between drag start and current cursor, snapped if snap is on.

### Relocated
- Context menu on the band: Rename · Change color ▸ (palette swatches) · Delete.
- Undo/Redo wired to standard app-wide ⌘Z / ⇧⌘Z via `NSWindow.firstResponder` routing to `vm.undoManager` — no dedicated toolbar buttons.
- Boundary drag handles always visible whenever sections exist; no longer gated on editor mode.

### Removed
- `SectionEditorToolbar` (entire view deleted).
- `SectionInspector` (entire view deleted).
- "Enter/Done section editor" toggle in `TransportBar` and related wiring (`enterSectionEditor` / `exitSectionEditor`) in `ContentView`.
- Reset-to-analyzer button and its confirmation dialog.
- Editor-mode-only gate on the tap-to-select behavior in `WaveformView`.

## Edge cases

- **Empty sections on load**: `UserEdits.sections.isEmpty` → UI shows one synthesized "Untitled" section spanning `[0, duration]`. First user mutation persists the real partition.
- **Option+drag crossing duration bounds**: endpoints clamped to `[0, duration]`.
- **Option+drag with endpoints that snap to the same beat**: collapses to `< minLen` → cancel.
- **Loop region lifecycle:**
  - Deleting the section currently serving as the loop source → clear `loopRegion`.
  - Moving a boundary of that section → live-update `loopRegion` to match.
  - Undoing a delete does **not** re-arm the loop (matches existing behavior for analogous ops).
- **Fully-engulfed deletion**: if Option+drag engulfs one or more existing sections, they are removed in the same undo group as the new section's creation; one Undo restores the prior partition.
- **Color collision with neighbor**: when rotating `colorIndex`, skip any color index used by either immediate neighbor.

## Migration

One-time: wipe `TrackAnalysis.sections` consumption at the point where the active partition is derived. No on-disk rewrite needed. Users with existing `UserEdits.sections` see their manual partitions unchanged. Users whose only sections came from the analyzer get a fresh "Untitled" single-section state.

## Testing

Unit:
- `SectionsViewModel.createSection`:
  - Range entirely inside one section → 3-way split; shortest piece dropped when below `minLen`.
  - Range with partial left overlap → left section shrinks to `startTime`.
  - Range with partial right overlap → right section shrinks from `endTime`.
  - Range engulfing one section → section deleted.
  - Range spanning three sections (partial-L, engulfed-mid, partial-R) → correct three-way result.
  - Snap on: endpoints land on beats; snap off: exact.
  - Degenerate range (< `minLen`): returns `nil`, no mutation.
  - Color index skips immediate neighbors.
- `delete`: deleting last section refused.
- Label→color auto-mapping on rename unchanged.
- `AnalysisService.hasUserSectionEdits` true only when `UserEdits.sections` non-empty.

Integration / UI (SwiftUI or snapshot-style):
- Option+drag of ≥ 8 px calls `createSection`; < 8 px does not.
- Plain drag (no modifier) does nothing.
- Cmd+drag still aligns downbeat (regression guard).
- Label click toggles selection and `loopRegion`.
- Esc clears selection and `loopRegion`.
- ⌫ on selected section calls `delete`.

## Implementation order (sketch)

1. `SectionsViewModel.createSection` + tests (pure logic, no UI).
2. Strip analyzer section pipeline; update `MockAnalyzer` + merge tests.
3. Rewire `ContentView` to always own a `SectionsViewModel`; synthesize default Untitled section when edits empty.
4. Add Option+drag gesture to `WaveformView` (mirror Cmd-drag pattern).
5. Build `SectionLabelBadge` view; wire click/double-click/right-click handlers.
6. Delete `SectionEditorToolbar`, `SectionInspector`, editor-mode wiring, Reset UI.
7. Wire ⌘Z/⇧⌘Z, ⌫, Esc handlers at the waveform level.
8. Loop-region lifecycle: follow selected section; clear on delete/deselect.

## Open questions

None.
