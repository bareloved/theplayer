# DAW-Style Downbeat Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the draggable downbeat triangle with a DAW-style "drag the waveform, grid stays fixed" interaction; ensure the red bar-1 indicator can never visually drift from the ruler's bar-1 tick.

**Architecture:** Keep content x = audio time. During a waveform-body drag, mutate `firstDownbeatTime` AND compensate `scrollOriginX` by the same pixel delta so the grid stays visually pinned while the waveform slides. Remove the fragile red-line-match-in-barLines logic in favor of a single dedicated overlay computed from `firstDownbeatTime` alone.

**Tech Stack:** SwiftUI, AppKit (`NSScrollView`, `NSCursor`), XCTest.

Spec: [docs/superpowers/specs/2026-04-18-daw-style-downbeat-alignment-design.md](../specs/2026-04-18-daw-style-downbeat-alignment-design.md).

---

## File Structure

Only three files change. No new files.

- **Modify:** [ThePlayer/Views/WaveformView.swift](../../../ThePlayer/Views/WaveformView.swift) — layout collapses to `[ruler, waveform]`; red indicator becomes a dedicated overlay; waveform body gets a drag gesture.
- **Modify:** [ThePlayer/Views/WaveformRulerBand.swift](../../../ThePlayer/Views/WaveformRulerBand.swift) — no behavioral change; only remove a now-unused `onSetDownbeat` param if present. (It was already removed in an earlier change; verify in Task 0.)
- **Delete (inline):** `DownbeatArrowHandle` struct (currently at the bottom of `WaveformRulerBand.swift`).

---

### Task 0: Baseline check

- [ ] **Step 1: Confirm current state**

Run: `git status && git log --oneline -5`
Expected: clean working tree, most recent commit is the DAW-alignment spec.

- [ ] **Step 2: Baseline build**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

---

### Task 1: Remove the fragile red-line match in `barLines`

**Files:**
- Modify: [ThePlayer/Views/WaveformView.swift](../../../ThePlayer/Views/WaveformView.swift) around the `barLines` function (~line 214).

- [ ] **Step 1: Replace the body of `barLines`**

Find the current implementation (matches on `isDownbeatAnchor` and paints red). Replace the whole method with this simpler version that draws only white ticks:

```swift
    private func barLines(width: CGFloat, height: CGFloat) -> some View {
        TiledCanvas(totalWidth: width, height: height) { context, size, xRange in
            guard duration > 0 else { return }
            let pad: CGFloat = 2

            for gridTime in gridPositions {
                let x = CGFloat(gridTime / duration) * size.width
                if x < xRange.lowerBound - pad || x > xRange.upperBound + pad { continue }
                let rounded = (gridTime * 100).rounded() / 100
                let isBar = barPositions.contains(rounded)

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))

                let opacity: CGFloat = isBar ? 0.45 : 0.2
                let lw: CGFloat = isBar ? 1.5 : 0.75
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lw)
            }
        }
        .allowsHitTesting(false)
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift
git commit -m "refactor(waveform): remove red-line match in barLines (replaced by dedicated overlay next)"
```

---

### Task 2: Add the dedicated red bar-1 indicator

**Files:**
- Modify: [ThePlayer/Views/WaveformView.swift](../../../ThePlayer/Views/WaveformView.swift).

- [ ] **Step 1: Add the overlay method**

Add this private method to `WaveformView`, alongside the other view builders (e.g., just before `playhead`):

```swift
    @ViewBuilder
    private func downbeatIndicator(width: CGFloat, height: CGFloat) -> some View {
        if duration > 0 {
            let x = CGFloat(max(0, min(firstDownbeatTime, duration)) / duration) * width
            Rectangle()
                .fill(Color.red.opacity(0.75))
                .frame(width: 1.5, height: height)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }
```

- [ ] **Step 2: Insert it in the waveform ZStack**

In `WaveformView.body` inside the inner `ZStack(alignment: .leading) { … }`, add a call to `downbeatIndicator` just after `playhead(...)`:

```swift
                        playhead(width: totalWidth, height: waveHeight)
                        downbeatIndicator(width: totalWidth, height: waveHeight)
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift
git commit -m "feat(waveform): dedicated red bar-1 overlay computed from firstDownbeatTime"
```

---

### Task 3: Delete the downbeat strip and the draggable triangle

**Files:**
- Modify: [ThePlayer/Views/WaveformView.swift](../../../ThePlayer/Views/WaveformView.swift) — remove the strip from the VStack, remove the `downbeatStrip` method, remove `DownbeatArrowHandle`.

Note: `DownbeatArrowHandle` currently lives at the bottom of `WaveformRulerBand.swift` (moved there earlier). Verify with grep before deleting. If it lives in `WaveformView.swift`, delete it there instead.

- [ ] **Step 1: Find where DownbeatArrowHandle is declared**

Run: `grep -n "struct DownbeatArrowHandle" ThePlayer/Views/*.swift`

- [ ] **Step 2: Remove the strip call from the VStack in `WaveformView.body`**

Find this block:

```swift
                    WaveformRulerBand( ... )

                    downbeatStrip(width: totalWidth, height: downbeatStripHeight)

                    ZStack(alignment: .leading) {
```

Replace with (removing the strip entirely):

```swift
                    WaveformRulerBand( ... )

                    ZStack(alignment: .leading) {
```

- [ ] **Step 3: Remove the `downbeatStripHeight` local and adjust `waveHeight`**

Find:

```swift
            let bandHeight = WaveformZoomMath.rulerHeight
            let downbeatStripHeight: CGFloat = 12
            let waveHeight = max(0, height - bandHeight - downbeatStripHeight)
```

Replace with:

```swift
            let bandHeight = WaveformZoomMath.rulerHeight
            let waveHeight = max(0, height - bandHeight)
```

- [ ] **Step 4: Remove the `downbeatStrip` method**

Delete the entire `downbeatStrip(width:height:)` function (the `@ViewBuilder` that builds a `Rectangle().fill(Color.black.opacity(0.15))` with a `DownbeatArrowHandle` inside it). It no longer has any callers.

- [ ] **Step 5: Delete `DownbeatArrowHandle`**

Delete the entire `struct DownbeatArrowHandle: View { … }` declaration from whichever file Step 1 found it in (expected: `WaveformRulerBand.swift`). No references remain after Step 4.

- [ ] **Step 6: Build**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift ThePlayer/Views/WaveformRulerBand.swift
git commit -m "refactor(waveform): remove downbeat strip and draggable triangle"
```

---

### Task 4: Waveform-body drag = slide audio + compensate scroll

**Files:**
- Modify: [ThePlayer/Views/WaveformView.swift](../../../ThePlayer/Views/WaveformView.swift).

Behavior: drag horizontally on the waveform body with ≥ 2pt movement → update `firstDownbeatTime` and move the scroll offset by the same pixel amount so the grid stays visually pinned. Click (no movement threshold reached) still seeks.

- [ ] **Step 1: Add drag state**

Near the other `@State` declarations in `WaveformView`, add:

```swift
    @State private var alignDragStartFDT: Float?
    @State private var alignDragStartScrollX: CGFloat?
    @State private var alignDragActive: Bool = false
```

- [ ] **Step 2: Extend the ZStack with the drag gesture**

Find the waveform ZStack modifier chain in `WaveformView.body`:

```swift
                    .frame(width: totalWidth, height: waveHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        ...
                    }
                    .onContinuousHover { phase in
                        ...
                    }
```

Add the `.gesture` BETWEEN `.contentShape(Rectangle())` and `.onTapGesture`. The DragGesture's `minimumDistance: 2` means a click with no drag still reaches the `onTapGesture`; only sustained movement activates alignment.

```swift
                    .frame(width: totalWidth, height: waveHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .local)
                            .onChanged { value in
                                guard totalWidth > 0, duration > 0 else { return }
                                if !alignDragActive {
                                    alignDragActive = true
                                    alignDragStartFDT = firstDownbeatTime
                                    alignDragStartScrollX = scrollController.scrollOriginX
                                    NSCursor.closedHand.set()
                                }
                                guard
                                    let startFDT = alignDragStartFDT,
                                    let startScroll = alignDragStartScrollX
                                else { return }
                                let pxPerSec = totalWidth / CGFloat(duration)
                                // Drag right (positive Δx) → audio moves right → bar-1 audio time is EARLIER.
                                let deltaSec = Float(value.translation.width / pxPerSec)
                                let newFDT = max(0, min(Float(duration), startFDT - deltaSec))
                                onSetDownbeat?(newFDT)
                                let maxOrigin = max(0, totalWidth - geo.size.width)
                                let newScroll = min(max(startScroll - value.translation.width, 0), maxOrigin)
                                scrollController.setScrollOriginX(newScroll)
                            }
                            .onEnded { _ in
                                alignDragActive = false
                                alignDragStartFDT = nil
                                alignDragStartScrollX = nil
                                NSCursor.arrow.set()
                            }
                    )
                    .onTapGesture { location in
```

Note: `geo.size.width` is in scope because this ZStack is inside the outer `GeometryReader { geo in ... }`. Confirm by inspecting the surrounding code; if the ZStack isn't inside that closure any more, thread `geoWidth` through.

- [ ] **Step 3: Build**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the test suite**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test 2>&1 | tail -6`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift
git commit -m "feat(waveform): drag waveform to align audio to fixed grid (DAW-style)

Drag horizontally on the waveform body to slide the audio under a
fixed grid. Under the hood, mutates firstDownbeatTime and compensates
the scroll origin so the grid stays visually pinned while the
waveform moves with the cursor. Clamps firstDownbeatTime to [0, duration]."
```

---

### Task 5: Smoke test + final sanity

- [ ] **Step 1: Final build + tests**

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test 2>&1 | tail -6
```
Expected: `** TEST SUCCEEDED **` and no warnings beyond pre-existing ones.

- [ ] **Step 2: Record a manual-verification checklist in the commit trailer**

No code change. The user will run the app and check:
1. Drag waveform left/right: grid stays pinned, waveform + playhead slide with cursor.
2. Click waveform (no drag): seek.
3. Release drag at edges: clamped; no glitch.
4. Red line in waveform matches bar-1 tick in ruler exactly at rest.
5. Section-boundary handles still drag (child-gesture priority).
6. Ruler pan/zoom still works.

---

## Self-Review Notes

- **Spec coverage:**
  - Coordinate model unchanged, clamp `[0, duration]` ✓ (Task 4 Step 2).
  - Click = seek, drag = align ✓ (Task 4).
  - Grid stays pinned via scroll compensation ✓ (Task 4).
  - Persist via `onSetDownbeat` ✓ (Task 4 fires on every change; persistence layer already debounces).
  - Red bar-1 overlay from single source of truth ✓ (Task 2).
  - Remove triangle + strip ✓ (Task 3).
  - Remove fragile barLines match ✓ (Task 1).
  - Non-goals respected (no snap, no keyboard nudge, no reset button, no negative fDT).
- **Placeholders:** none.
- **Type consistency:** `scrollController.scrollOriginX`, `setScrollOriginX`, `onSetDownbeat`, `firstDownbeatTime`, `totalWidth`, `geo.size.width` — all match existing code.
