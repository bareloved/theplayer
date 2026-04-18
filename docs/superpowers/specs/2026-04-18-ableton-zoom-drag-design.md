# Ableton-style Zoom Drag on Waveform Ruler

## Goal

Add a vertical drag-to-zoom gesture on the waveform, matching Ableton's behavior: grab the ruler strip and drag down to zoom in, drag up to zoom out. The bar under the cursor at mouse-down stays visually pinned during the zoom.

## Scope

- Affects `ThePlayer/Views/WaveformView.swift` only.
- Does **not** change the existing zoom entry points (magnify gesture, ⌘-scroll wheel, +/- buttons). They continue to work; they just won't share the anchor-preservation logic of the new gesture.
- No new state exposed to parents.

## Design

### Ruler strip

Add an invisible hit zone along the top of the waveform content (inside the `ZStack`), height ~18pt, full content width. It sits above the existing overlays but **below** the `DownbeatArrowHandle` (which continues to own its own hit target near y=0..24 for its triangle). Child gestures win in SwiftUI, so the downbeat drag is unaffected.

Cursor: `NSCursor.resizeUpDown` on hover over the strip.

### Gesture

`DragGesture(minimumDistance: 2)` on the strip.

On drag begin (first `onChanged` with `dragStartZoom == nil`):
- Capture `dragStartZoom = zoomLevel`.
- Capture `anchorFraction = location.x / totalWidth` — the content-space fraction under the cursor at mouse-down. `totalWidth` at that instant = `geoWidth * dragStartZoom`.

On drag change:
- `newZoom = clamp(dragStartZoom * exp(translation.height * k), 1.0, 20.0)` with `k = 0.005` (drag-down positive → zoom-in; exponential so the gain feels uniform across the 1x–20x range).
- Set `zoomLevel = newZoom`.
- Scroll so the anchor bar stays under the cursor:
  - New content width: `newTotalWidth = geoWidth * newZoom`
  - Target x of anchor in content space: `anchorFraction * newTotalWidth`
  - Desired `contentView.bounds.origin.x = anchorFraction * newTotalWidth - cursorXInViewport`, where `cursorXInViewport` is the location passed into the gesture (DragGesture location is in the gesture's coordinate space — we'll attach the gesture in the scroll-viewport coordinate space so this is the on-screen cursor x).

On drag end: clear `dragStartZoom` and `anchorFraction`.

### Scroll container

Replace the outer `ScrollView(.horizontal, showsIndicators: true)` with a small `NSViewRepresentable` wrapping `NSScrollView`, so we can:
- Set `contentView.scroll(to:)` mid-drag for anchor preservation.
- Host the existing `ScrollWheelHandler` logic natively (⌘-scroll → zoom) on the documentView instead of a sibling background view.

The wrapper accepts the ZStack content via `@ViewBuilder` and a binding-like callback for scroll-wheel zoom. Horizontal scroll with wheel/trackpad continues to work through `NSScrollView`'s default behavior.

### State

Two new `@State` fields on `WaveformView`:
- `dragStartZoom: CGFloat?`
- `anchorFraction: CGFloat?`

### Constants

- `rulerHeight: CGFloat = 18`
- `zoomDragSensitivity: CGFloat = 0.005` (exp-per-pixel)
- Zoom clamp unchanged: `[1.0, 20.0]`

## Non-goals

- No horizontal-drag-on-ruler scroll (Ableton also allows this; out of scope here).
- No ruler tick marks / time labels on the strip itself — it's invisible. Adding visible ruler graphics is a separate task.
- No change to pinch-to-zoom or +/- buttons' anchor behavior (they remain centered).

## Testing

Manual checks:
1. Drag down on top strip → zoom increases; bar under cursor stays put.
2. Drag up → zoom decreases; same anchor behavior.
3. Drag near left/right edges clamps naturally to valid scroll range.
4. Downbeat triangle still drags horizontally without triggering zoom.
5. ⌘-scroll still zooms; magnify gesture still zooms; buttons still work.
6. Tap on waveform (non-strip) still seeks/selects as before.
