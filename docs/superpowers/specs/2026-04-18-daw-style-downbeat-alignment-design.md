# DAW-Style Downbeat Alignment

## Goal

Replace the draggable red triangle with a DAW-style alignment model: the grid is fixed, the waveform moves. The user grabs the waveform body and drags left/right to align the audio's actual downbeat to bar 1 of the fixed grid.

Solves two problems with the current implementation:

1. **Reliability** — the red "bar-1" line in the waveform grid is painted by matching computed grid positions to `firstDownbeatTime`. That match can fail, producing a visible drift between the triangle in the ruler and the red line in the waveform.
2. **Mental model** — users think in DAW terms ("slide the audio onto the grid"), not "move the downbeat marker."

## Scope

Changes are confined to the waveform view layer and associated math. No changes to analysis, persistence, or the meaning of `firstDownbeatTime` (still = audio time at which bar 1 occurs).

- Modified: [WaveformView.swift](ThePlayer/Views/WaveformView.swift), [WaveformRulerBand.swift](ThePlayer/Views/WaveformRulerBand.swift).
- Possibly deleted: `DownbeatArrowHandle` (red triangle) — folded into a dedicated bar-1 overlay.
- `UserEditsStore` persistence path unchanged. Only `firstDownbeatTime` is persisted; no new state.

## Coordinate model

Content x-axis continues to represent **audio time**. No axis flip. The DAW feel is achieved by scroll-offset compensation during drag (see Interaction).

- Content width = `duration * pxPerSec` (unchanged).
- Bar 1 at content x = `firstDownbeatTime * pxPerSec`. Pre-bar-1 audio naturally sits at x = `[0, firstDownbeatTime * pxPerSec)`.
- `firstDownbeatTime` is clamped to `[0, duration]`. The lower bound prevents the nonsensical case of bar 1 happening before audio exists.

## Interaction

### Click on waveform body
Seek (existing behavior, unchanged).

### Drag on waveform body
Distinguished from click by ≥ 2pt movement threshold. Enters **alignment mode**:

- Cursor: `closedHand` while dragging.
- On each drag frame with horizontal delta `Δpx`:
  - `firstDownbeatTime -= Δpx / pxPerSec` (clamped to `[0, duration]`).
  - `scrollOriginX -= Δpx` (clamped to `[0, totalWidth - geoWidth]`).
  - Net visual effect: grid lines and ruler labels stay at the same screen position; waveform and playhead slide with the cursor.
- On release: call existing `onSetDownbeat(firstDownbeatTime)` to persist via `UserEditsStore`.

Hitting either clamp (drag past audio start or past audio end) causes the waveform to stop sliding — the cursor may continue, but the visual state is pinned. This is acceptable: the extremes represent unusable configurations.

### Other gestures that share the waveform body
- **Section boundary handles** — keep their own `DragGesture`; SwiftUI child-gesture priority wins.
- **Tap-to-seek** — naturally distinguished from drag by movement threshold.
- **Pending-loop / set-downbeat modes** — `isSettingDownbeat` mode is no longer needed for downbeat setting, since the drag does it directly. Keep the mode for now (some UI still toggles it) but treat a tap in that mode as setting `firstDownbeatTime = tappedAudioTime` (current behavior). Drag still works in that mode too.

### Ruler band (unchanged)
- Horizontal drag pans (existing behavior).
- Vertical drag zooms (existing behavior).
- Tap seeks (not part of this change, noted as a separate nice-to-have).

## The red bar-1 indicator

The current red line inside `barLines` is removed (the fragile grid-position match goes away). Replaced by a single dedicated overlay:

- A full-height vertical red line drawn at content x = `firstDownbeatTime * pxPerSec`.
- Spans the waveform body from top to bottom. Does not extend into the ruler band (the ruler's "1" label already marks it there).
- Rendered as a sibling in the waveform ZStack after the playhead. Non-interactive (`allowsHitTesting(false)`).
- Uses the same formula as the ruler's bar-1 tick — one source of truth, no possible drift.

The red triangle (`DownbeatArrowHandle`) and the 12pt `downbeatStrip` between the ruler and waveform are deleted. The VStack collapses to `[ruler, waveform]`.

## Non-goals (v1)

- No snap-to-beat. The whole point is to override the analyzer's grid when it's wrong.
- No keyboard nudge ("← / →" to shift by a small increment). Future.
- No "reset to analyzer value" button. Future.
- No negative `firstDownbeatTime` (bar 1 before audio). Clamped at 0.
- No modifier-click gestures on the waveform body (fine-tune, etc.). Future.

## Testing

Manual checks:
1. Song with correct analyzer downbeat: drag waveform left/right, watch grid stay pinned, waveform slide. Release — red line matches bar-1 tick exactly.
2. Song with wrong downbeat: drag waveform until the real downbeat is under bar 1. Play. Metronome hits with the beat.
3. Song that starts on the 1 (`firstDownbeatTime ≈ 0`): waveform occupies full content; no blank space left of bar 1.
4. Drag past the left limit: waveform stops sliding at `firstDownbeatTime = 0`. No crash, no visual glitch.
5. Drag while zoomed in (x50+): alignment precision feels good — small mouse movement = small audio shift.
6. Click on waveform (no drag) still seeks.
7. Section boundary handle drag still works and doesn't conflict with alignment drag.
8. Reload the app: persisted `firstDownbeatTime` matches what was set. Red line and bar-1 tick agree on reload.
