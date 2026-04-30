# Bar / Second Jump Keyboard Shortcuts — Design

**Date:** 2026-04-28
**Branch:** `ui-ux`
**Status:** Spec

## Summary

Remove the "Bars" picker from the transport bar. Replace its purpose with arrow-key shortcuts that jump the playhead by a configurable amount, where the amount depends on the **Snap** toggle:

- **Snap ON** → arrows jump in bars (1 / 2 / 4 / 8 / 16 by modifier).
- **Snap OFF** → arrows jump in seconds (1 / 2 / 5 / 15 / 30 by modifier).

Snap-to-grid stays, but its resolution is fixed at 1 bar (no longer user-configurable).

## Motivation

The "Bars" picker is modal UI: it sets a single value the user has to change before each kind of jump. Replacing it with modifier-keyed shortcuts:

- Removes a dropdown from the transport bar (less visual clutter).
- Lets the user mix jump sizes without round-tripping through a picker.
- Adds useful seconds-based nudging when analysis hasn't completed (or for tracks where bar math doesn't apply).

## UI Changes

### `TransportBar.swift`

- Delete the `Picker("Bars", selection: $snapDivision)` block (lines 46–56) and the `@Binding var snapDivision: SnapDivision` property.
- Keep the **Snap** button. Update its tooltip via `.help(...)` to show the shortcut cheatsheet:

  ```
  Snap on:  ←/→ 1 bar · ⇧ 2 · ⌥ 4 · ⌘ 8 · ⌘⇧ 16
  Snap off: ←/→ 1 s · ⇧ 2 s · ⌥ 5 s · ⌘ 15 s · ⌘⇧ 30 s
  ```

### `ContentView.swift`

- Remove `@State private var snapDivision: SnapDivision = .oneBar`.
- Remove the `snapDivision:` argument passed to `WaveformView` and `TransportBar`.
- Install the keyboard monitor (see Implementation).

### `WaveformView.swift`

- Remove the `let snapDivision: SnapDivision` property.
- Remove `.onChange(of: snapDivision)` recomputation hook.
- Replace `snapDivision.snapPositions(...)` call with a free function `barSnapPositions(...)` (see Models).

## Model Changes

### Delete `SnapDivision`

`ThePlayer/Models/SnapDivision.swift` is removed. The single piece of math it carried — generating snap positions from the first downbeat outward — moves to a free function:

```swift
func barSnapPositions(
    beats: [Float],
    bpm: Float,
    duration: Float,
    beatsPerBar: Int,
    firstBeatTime: Float? = nil
) -> [Float]
```

Behavior is identical to `SnapDivision.oneBar.snapPositions(...)` — i.e. `beatsPerSnap = beatsPerBar`.

Call sites updated: `WaveformView.swift:462`, `ContentView.swift:584`.

## Keyboard Shortcut Behavior

### Mapping

| Modifier   | Snap ON | Snap OFF |
| ---------- | ------- | -------- |
| (none)     | 1 bar   | 1 s      |
| shift      | 2 bars  | 2 s      |
| option     | 4 bars  | 5 s      |
| cmd        | 8 bars  | 15 s     |
| cmd+shift  | 16 bars | 30 s     |

Any other modifier combination on `←` / `→` (e.g. `ctrl`, `cmd+option`, `cmd+option+shift`) is **not consumed** — the event passes through to the system. Only the five combos above are claimed.

### Snap ON — bar mode

Single rule, no on-grid / off-grid special case:

- **Forward** target = the **N-th bar line strictly after** `currentTime`, where N = `bars`.
- **Backward** target = the **N-th bar line strictly before** `currentTime`.

Worked examples (bar lines at integer bars 0, 1, 2, …):

- From 3.0 with bars=4 forward → 4.0, 5.0, 6.0, **7.0**.
- From 3.0 with bars=4 backward → 2.0, 1.0, 0.0, **−1.0 → clamped to 0**.
- From 3.4 with bars=4 forward → 4.0, 5.0, 6.0, **7.0**.
- From 3.4 with bars=4 backward → 3.0, 2.0, 1.0, **0.0**.
- From 3.0 with bars=1 forward → **4.0** (a press always moves you when on-grid).
- From 3.0 with bars=1 backward → **2.0**.

Bar-line origin is `analysis.beats[analysis.downbeatOffset]` (same origin used today by `WaveformView` / `barSnapPositions`). Bar width = `60 / bpm × beatsPerBar`.

Bar-line origin is `analysis.beats[analysis.downbeatOffset]` (same origin used today by `WaveformView` / `barSnapPositions`).

If `analysis == nil` or `bpm <= 0` or `beatsPerBar <= 0`, the keypress is consumed (no beep) but does nothing. Bar mode requires analysis.

### Snap OFF — seconds mode

Exact jump: `targetTime = clamp(currentTime ± N, 0, duration)`. No snapping. Works regardless of analysis state — only `duration` is needed.

### Math helpers

Two pure functions, both unit-testable without AppKit or audio:

```swift
func nextBarTime(
    from currentTime: Float,
    direction: JumpDirection, // .forward | .backward
    bars: Int,
    bpm: Float,
    beatsPerBar: Int,
    firstBeatTime: Float,
    duration: Float
) -> Float?  // nil if BPM/beatsPerBar invalid

func nextSecondTime(
    from currentTime: Float,
    direction: JumpDirection,
    seconds: Float,
    duration: Float
) -> Float
```

These live in `ThePlayer/Audio/JumpMath.swift` (new file).

## Implementation: Keyboard Monitor

Use `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed by a small helper attached to `ContentView`'s root view via `.onAppear` / `.onDisappear`. The monitor:

1. Returns the event unchanged if `event.keyCode` is not `.leftArrow` or `.rightArrow`.
2. Checks `NSApp.keyWindow?.firstResponder`. If it is an `NSText`, `NSTextView`, or any responder that conforms to text input, returns the event unchanged. This keeps text fields (search box, setlist rename, etc.) working.
3. Reads `event.modifierFlags.intersection(.deviceIndependentFlagsMask)` and matches against the five claimed combos. Anything else returns the event unchanged.
4. Computes the target time:
   - Snap on → `nextBarTime(...)`. If `nil`, consume the event and noop.
   - Snap off → `nextSecondTime(...)`.
5. Calls `audioEngine.seek(to: target)`.
6. Returns `nil` to consume the event (no system beep).

The monitor needs access to: `audioEngine`, `snapToGrid`, the current `TrackAnalysis?`, and `duration`. It is installed in `ContentView` where all of those are already in scope.

The monitor token is stored in `@State` on `ContentView` and removed in `.onDisappear` to avoid leaks if the window closes.

## Edge Cases

- **Multiple windows / no key window** — `NSApp.keyWindow == nil` means the app isn't focused; the local monitor only fires for our app, so this is fine. If `keyWindow` exists but isn't ours (e.g. About panel), the monitor still fires; first-responder bail handles it.
- **Loop region active** — jumps cross loop boundaries freely. The audio engine's loop wrap continues to fire on subsequent playback; no special handling needed.
- **Playhead at exactly 0 / duration** — clamping handles both directions cleanly.
- **Snap toggled while playing** — modifier mapping is read at keypress time, so toggling Snap takes effect immediately for the next press.
- **BPM changes (re-analysis, manual override)** — `firstBeatTime` and `bpm` are read fresh on each press from the live `analysis` object. No caching.

## Tests

New file `ThePlayerTests/JumpMathTests.swift`:

**Bar mode (`nextBarTime`):**
- Forward from mid-bar (e.g. 3.4, bars=4) → 7.0.
- Forward from exact bar boundary (3.0, bars=4) → 7.0.
- Backward from mid-bar (3.4, bars=4) → 0.0.
- Backward from exact bar boundary (3.0, bars=4) → 0.0 (clamped from −1.0).
- Forward bars=1 from on-grid (3.0) → 4.0 (a press always moves you).
- Backward bars=1 from on-grid (3.0) → 2.0.
- Clamps to `[0, duration]` at both ends.
- Returns `nil` when `bpm <= 0` or `beatsPerBar <= 0`.
- All five `bars` values (1, 2, 4, 8, 16) — single parameterized test.

**Seconds mode (`nextSecondTime`):**
- Forward / backward by exact seconds.
- Clamps to `[0, duration]`.
- All five values (1, 2, 5, 15, 30).

The keyboard monitor itself is not unit-tested (AppKit boundary). Manual smoke check in QA section.

## QA / Manual Test Plan

1. Load a track. Verify Bars picker is gone.
2. With analysis loaded and Snap **on**:
   - Tap `←` / `→` repeatedly — playhead lands on bar lines.
   - Try each modifier combo, watch the WaveformView ruler — bar count matches table.
   - Drag playhead to mid-bar, press `→` — lands on the next bar line, not 1 bar ahead of mid-bar.
3. Toggle Snap **off**:
   - `←` / `→` jumps exactly 1 second. Modifier combos match the seconds column.
4. Click into the search field, press arrows — text caret moves, playhead doesn't.
5. Press `←` while playhead is at 0 — no movement, no beep. Press `→` near end — clamps to duration.
6. Hover the Snap button — tooltip shows both shortcut tables.
7. Load a track before analysis completes:
   - Snap off + arrows → works (seconds mode).
   - Snap on + arrows → silent noop.

## Out of Scope

- Customizable shortcut bindings.
- Visible on-screen overlay of shortcuts (tooltip is enough).
- Changes to loop / setlist / transport buttons.
- Replacing the Snap toggle's existence (it stays).

## Files Touched

- **Edit:** `ThePlayer/Views/TransportBar.swift`, `ThePlayer/Views/ContentView.swift`, `ThePlayer/Views/WaveformView.swift`
- **Delete:** `ThePlayer/Models/SnapDivision.swift`, `ThePlayerTests/SnapDivisionTests.swift` (if present)
- **Add:** `ThePlayer/Audio/JumpMath.swift`, `ThePlayerTests/JumpMathTests.swift`
- **Regenerate:** `ThePlayer.xcodeproj` via `xcodegen generate`
