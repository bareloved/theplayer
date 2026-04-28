# Shift+Drag Loop Creation

## Goal

Replace the current two-click "A-B" loop-setting flow with a direct shift+drag gesture on the waveform, plus an Ableton-style loop on/off toggle button.

## Current behavior (to be removed)

- `TransportBar` "A-B" button toggles `isSettingLoop`. Button turns orange and reads "Click waveform...".
- In that mode, two clicks on the waveform set start/end (`pendingLoopStart` then `onLoopPointSet`).
- Orange border overlays the waveform while in loop-setting mode.
- Clicking the A-B button when a loop exists clears it.

## New behavior

### Loop region creation

- **Shift+drag** on the waveform creates a loop region.
- Live preview overlay grows while dragging (same visual pattern as the existing option+drag for sections).
- Snap (when Snap is on): **floor/ceil to bars**. Any nonzero drag encloses at least one whole bar. Mirrors `WaveformView` section-drag snapping.
- Minimum length: >0.1s on release; otherwise discard.
- Shift+drag with an existing region **replaces** it.
- On successful creation, the loop toggle **auto-enables** and playback begins looping the new region.

### Loop toggle button (replaces A-B)

- Location: `TransportBar`, same slot the A-B button occupied.
- Icon: `repeat`. Label: "Loop".
- States:
  - **On** — accent (blue), playback loops the region.
  - **Off** — muted/secondary color, region remains drawn on the waveform but is not active for playback.
- Always clickable. When no region exists, clicking shows a transient hint *"Shift+drag waveform to set loop"* (~2s). The toggle's intended state is preserved.

### Section interaction

- Clicking a section still updates `loopRegion` to that section's range.
- **Respects** the current toggle state (no auto-enable). Off → audio plays through; On → loops the section.

### Region lifecycle

- No explicit clear UI.
- Replaced by the next shift+drag.
- Persists across toggle off/on toggles.
- Cleared automatically when the song changes (existing behavior in `ContentView.loadSong`).

## Code surface

**Removed**

- `isSettingLoop` state in `ContentView` and its `@Binding` propagation through `TransportBar` and `WaveformView`.
- `pendingLoopStart` state and `handleLoopPoint` two-click logic in `ContentView`.
- `onLoopPointSet` callback and `pendingLoopMarker` view in `WaveformView`.
- `isSettingLoop` orange border overlay in `WaveformView`.
- The A-B button branch in `TransportBar` (`toggleLoopMode`, "Click waveform..." label, orange tint).

**Added**

- New `@State var isLoopEnabled: Bool` in `ContentView` (the toggle state). Defaults to true so existing flows that set `loopRegion` keep looping.
- New shift+drag `simultaneousGesture` in `WaveformView` (parallel to the existing option+drag for sections), with its own preview state (`loopDragActive`, `loopDragStartTime`, `loopDragCurrentTime`).
- New loop toggle button in `TransportBar` bound to `isLoopEnabled` and `loopRegion`.
- Hint affordance for empty-region click on the toggle (transient overlay or popover).

**Audio engine wiring**

- `ContentView.onChange(of: loopRegion)` and a new `onChange(of: isLoopEnabled)` together decide what to send to `audioEngine`:
  - region present + enabled → `setLoop(region)` and `playLoop()`.
  - region present + disabled OR region nil → `setLoop(nil)`.
- Persistence: continue saving `lastLoopStart`/`lastLoopEnd` from the region. Toggle state is per-session (not persisted) for now; on song load we treat a restored region as enabled.

## Out of scope

- Persisting the toggle on/off state across launches.
- Right-click context menu actions on the loop overlay.
- Keyboard clear (Esc).
- Drag-edit of existing loop endpoints (resize handles).
