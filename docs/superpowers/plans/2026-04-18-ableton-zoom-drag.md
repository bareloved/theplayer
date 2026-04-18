# Ableton-Style Zoom Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Ableton-style vertical-drag-to-zoom gesture on a top ruler strip of the waveform, with the bar under the cursor staying pinned during zoom.

**Architecture:** Extract pure zoom-math helpers (testable). Replace outer `ScrollView(.horizontal)` inside `WaveformView` with an `NSScrollView`-backed `NSViewRepresentable` so we can scroll programmatically mid-gesture. Add an invisible ruler strip along the top of the content that owns a `DragGesture` computing new zoom + scroll offset via the helpers.

**Tech Stack:** SwiftUI, AppKit (`NSScrollView`, `NSCursor`), Xcode XCTest.

Spec: `docs/superpowers/specs/2026-04-18-ableton-zoom-drag-design.md`.

---

## File Structure

- **Create:** `ThePlayer/Views/WaveformZoomMath.swift` — pure functions (`zoomFromDrag`, `scrollOriginForAnchor`) + constants.
- **Create:** `ThePlayer/Views/HorizontalNSScrollView.swift` — `NSViewRepresentable` wrapper around `NSScrollView` that hosts the ZStack content, exposes programmatic scroll via a coordinator, and handles ⌘-scroll-wheel zoom.
- **Modify:** `ThePlayer/Views/WaveformView.swift` — replace `ScrollView(.horizontal)` with the new wrapper, remove the sibling `ScrollWheelHandler` (its logic moves into the wrapper), add the ruler strip + drag gesture.
- **Create:** `ThePlayerTests/WaveformZoomMathTests.swift` — unit tests for the pure helpers.
- **Modify:** `project.yml` — register the new source files if the project uses XcodeGen (verify in Task 0).

Note on testing strategy: the gesture itself is visual/interactive and has no meaningful unit-test surface under XCTest — it's coordinator + NSScrollView behavior. So the plan puts TDD pressure on the **pure math** (where it matters and regressions would be silent), and uses a manual verification checklist for the gesture itself.

---

### Task 0: Verify project file layout

**Files:**
- Read: `project.yml`
- Read: `ThePlayer.xcodeproj/project.pbxproj` (only to confirm source-inclusion pattern)

- [ ] **Step 1: Determine how new Swift files get into the target**

Run: `head -40 project.yml`

If `project.yml` exists and contains `sources:` with folder globs like `ThePlayer` and `ThePlayerTests`, new files under those folders are auto-included by XcodeGen — no manual pbxproj edits needed. This is the expected case.

If `project.yml` uses explicit file lists, you will need to append the new files in later tasks. Record which is the case before proceeding.

- [ ] **Step 2: Confirm clean build baseline**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

---

### Task 1: Pure zoom-math helpers — failing tests

**Files:**
- Create: `ThePlayerTests/WaveformZoomMathTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ThePlayer

final class WaveformZoomMathTests: XCTestCase {
    func testZoomFromDragDownZoomsIn() {
        // Drag down (+translation.height) zooms in.
        let z = WaveformZoomMath.zoomFromDrag(startZoom: 2.0, translationY: 100)
        XCTAssertGreaterThan(z, 2.0)
    }

    func testZoomFromDragUpZoomsOut() {
        let z = WaveformZoomMath.zoomFromDrag(startZoom: 2.0, translationY: -100)
        XCTAssertLessThan(z, 2.0)
    }

    func testZoomFromDragIsExponentialAndSymmetric() {
        // +100 then -100 should return to (approximately) the starting zoom.
        let up = WaveformZoomMath.zoomFromDrag(startZoom: 4.0, translationY: 100)
        let back = WaveformZoomMath.zoomFromDrag(startZoom: up, translationY: -100)
        XCTAssertEqual(back, 4.0, accuracy: 0.0001)
    }

    func testZoomFromDragClampsLow() {
        let z = WaveformZoomMath.zoomFromDrag(startZoom: 1.0, translationY: -10000)
        XCTAssertEqual(z, 1.0, accuracy: 0.0001)
    }

    func testZoomFromDragClampsHigh() {
        let z = WaveformZoomMath.zoomFromDrag(startZoom: 20.0, translationY: 10000)
        XCTAssertEqual(z, 20.0, accuracy: 0.0001)
    }

    func testScrollOriginForAnchorKeepsCursorBarFixed() {
        // geoWidth=1000, startZoom=2 -> oldTotal=2000. Anchor at content x=800 => fraction=0.4.
        // Cursor is at viewport x=300 at mouse-down => scrollOriginX at start = 800 - 300 = 500.
        // After zoom to 4x: newTotal=4000, new anchor content x = 0.4*4000 = 1600.
        // To keep cursor x=300 on the same bar: newOriginX = 1600 - 300 = 1300.
        let origin = WaveformZoomMath.scrollOriginForAnchor(
            anchorFraction: 0.4,
            cursorXInViewport: 300,
            geoWidth: 1000,
            newZoom: 4.0
        )
        XCTAssertEqual(origin, 1300, accuracy: 0.0001)
    }

    func testScrollOriginForAnchorClampsToValidRange() {
        // newTotal=1000, viewport=1000 => max scroll = 0. Origin must clamp >= 0.
        let origin = WaveformZoomMath.scrollOriginForAnchor(
            anchorFraction: 0.0,
            cursorXInViewport: 500,
            geoWidth: 1000,
            newZoom: 1.0
        )
        XCTAssertEqual(origin, 0, accuracy: 0.0001)
    }

    func testScrollOriginForAnchorClampsToMax() {
        // newTotal=2000, viewport=1000 => max scroll = 1000. Extreme right anchor can't exceed.
        let origin = WaveformZoomMath.scrollOriginForAnchor(
            anchorFraction: 1.0,
            cursorXInViewport: 0,
            geoWidth: 1000,
            newZoom: 2.0
        )
        XCTAssertEqual(origin, 1000, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/WaveformZoomMathTests 2>&1 | tail -30`
Expected: build fails with `cannot find 'WaveformZoomMath' in scope`.

---

### Task 2: Pure zoom-math helpers — implementation

**Files:**
- Create: `ThePlayer/Views/WaveformZoomMath.swift`

- [ ] **Step 1: Implement the helpers**

```swift
import CoreGraphics
import Foundation

enum WaveformZoomMath {
    static let minZoom: CGFloat = 1.0
    static let maxZoom: CGFloat = 20.0
    /// Exponential gain per pixel of vertical drag. Drag-down (positive translation.height)
    /// zooms in. `exp(100 * 0.005) ≈ 1.65x` per 100pt, which matches Ableton's feel.
    static let dragSensitivity: CGFloat = 0.005

    /// Height of the invisible ruler strip that owns the zoom-drag gesture.
    static let rulerHeight: CGFloat = 18

    /// Compute new zoom level from a drag translation, clamped to [minZoom, maxZoom].
    static func zoomFromDrag(startZoom: CGFloat, translationY: CGFloat) -> CGFloat {
        let raw = startZoom * exp(translationY * dragSensitivity)
        return min(max(raw, minZoom), maxZoom)
    }

    /// Horizontal scroll origin that keeps the content-space bar at `anchorFraction`
    /// under the viewport x `cursorXInViewport` after zooming to `newZoom`.
    /// Clamped to the valid scroll range [0, newTotal - geoWidth].
    static func scrollOriginForAnchor(
        anchorFraction: CGFloat,
        cursorXInViewport: CGFloat,
        geoWidth: CGFloat,
        newZoom: CGFloat
    ) -> CGFloat {
        let newTotal = geoWidth * newZoom
        let desired = anchorFraction * newTotal - cursorXInViewport
        let maxOrigin = max(0, newTotal - geoWidth)
        return min(max(desired, 0), maxOrigin)
    }
}
```

- [ ] **Step 2: Run tests — expect pass**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/WaveformZoomMathTests 2>&1 | tail -20`
Expected: `Test Suite 'WaveformZoomMathTests' passed`.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/WaveformZoomMath.swift ThePlayerTests/WaveformZoomMathTests.swift
git commit -m "feat(waveform): pure zoom-math helpers with anchor-preserving scroll"
```

---

### Task 3: NSScrollView wrapper — skeleton compiling in isolation

**Files:**
- Create: `ThePlayer/Views/HorizontalNSScrollView.swift`

- [ ] **Step 1: Write the wrapper**

```swift
import AppKit
import SwiftUI

/// Horizontal `NSScrollView` host for SwiftUI content. Gives us:
///   - programmatic scroll (`setScrollOriginX`) for anchor-preserving zoom
///   - ⌘-scroll-wheel zoom hook (onCommandScroll)
/// The `content` closure is hosted via `NSHostingView` inside the documentView.
struct HorizontalNSScrollView<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let onCommandScroll: (CGFloat) -> Void
    let controller: ScrollController
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.onCommandScroll = onCommandScroll

        let hosting = NSHostingView(rootView: AnyView(content()))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        scroll.documentView = hosting

        controller.scrollView = scroll
        context.coordinator.hosting = hosting
        return scroll
    }

    func updateNSView(_ nsView: ZoomScrollView, context: Context) {
        nsView.onCommandScroll = onCommandScroll
        controller.scrollView = nsView
        if let hosting = context.coordinator.hosting as? NSHostingView<AnyView> {
            hosting.rootView = AnyView(content())
            let newSize = NSSize(width: contentWidth, height: contentHeight)
            if hosting.frame.size != newSize {
                hosting.setFrameSize(newSize)
            }
        }
    }

    final class Coordinator {
        var hosting: NSView?
    }
}

/// Exposed handle the SwiftUI view holds as `@StateObject` so it can push scroll-origin
/// changes to the underlying NSScrollView during a drag.
final class ScrollController: ObservableObject {
    weak var scrollView: NSScrollView?

    func setScrollOriginX(_ x: CGFloat) {
        guard let clip = scrollView?.contentView else { return }
        var origin = clip.bounds.origin
        origin.x = x
        clip.setBoundsOrigin(origin)
        scrollView?.reflectScrolledClipView(clip)
    }

    var scrollOriginX: CGFloat {
        scrollView?.contentView.bounds.origin.x ?? 0
    }
}

/// NSScrollView subclass that reports ⌘-scroll vertical deltas to a closure
/// (mirrors the previous `ScrollWheelHandler` behaviour).
final class ZoomScrollView: NSScrollView {
    var onCommandScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command)
            && abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            onCommandScroll?(event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
```

- [ ] **Step 2: Build — expect success, wrapper unused**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`. `HorizontalNSScrollView` will be unused until Task 4; Swift emits no warning for that.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/HorizontalNSScrollView.swift
git commit -m "feat(waveform): NSScrollView wrapper with programmatic scroll + ⌘-scroll hook"
```

---

### Task 4: Swap WaveformView's ScrollView for the wrapper

This is a behavior-preserving refactor: no new gesture yet, just replace the container.

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift` (lines 26–105 area)

- [ ] **Step 1: Add a `ScrollController` state object**

Near the other `@State` declarations (around line 26–29), add:

```swift
    @StateObject private var scrollController = ScrollController()
```

- [ ] **Step 2: Replace the `ScrollView` + `ScrollWheelHandler` block**

Replace the current body inside `GeometryReader { geo in ... }` (lines 32–104) with:

```swift
        GeometryReader { geo in
            let totalWidth = geo.size.width * zoomLevel
            let height = geo.size.height

            HorizontalNSScrollView(
                contentWidth: totalWidth,
                contentHeight: height,
                onCommandScroll: { delta in
                    let factor: CGFloat = delta > 0 ? 1.15 : 1.0 / 1.15
                    zoomLevel = max(WaveformZoomMath.minZoom,
                                    min(zoomLevel * factor, WaveformZoomMath.maxZoom))
                },
                controller: scrollController
            ) {
                ZStack(alignment: .leading) {
                    sectionBands(width: totalWidth, height: height)
                    if snapToGrid {
                        barLines(width: totalWidth, height: height)
                    }
                    waveformBars(width: totalWidth, height: height)

                    if let loop = loopRegion {
                        loopOverlay(loop: loop, width: totalWidth, height: height)
                    }

                    playhead(width: totalWidth, height: height)

                    if let vm = editorViewModel {
                        boundaryHandles(viewModel: vm, width: totalWidth, height: height)
                    }

                    if let start = pendingLoopStart {
                        pendingLoopMarker(start: start, width: totalWidth, height: height)
                    }

                    downbeatArrows(width: totalWidth, height: height)

                    if let time = hoverTime, let loc = hoverLocation {
                        hoverTooltip(time: time, location: loc)
                    }
                }
                .frame(width: totalWidth, height: height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let fraction = Float(location.x / totalWidth)
                    let time = fraction * duration
                    if isSettingDownbeat, let onSetDownbeat {
                        onSetDownbeat(time)
                        return
                    }
                    if let onSelectSection = onSelectSection, editorViewModel != nil {
                        let hit = sections.first(where: { time >= $0.startTime && time < $0.endTime })
                        onSelectSection(hit?.stableId)
                        return
                    }
                    if isSettingLoop {
                        onLoopPointSet(time)
                    } else {
                        onSeek(time)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let fraction = Float(location.x / totalWidth)
                        hoverTime = fraction * duration
                        hoverLocation = location
                    case .ended:
                        hoverTime = nil
                        hoverLocation = nil
                    }
                }
            }
            .gesture(MagnifyGesture().onChanged { value in
                zoomLevel = max(WaveformZoomMath.minZoom,
                                min(zoomLevel * value.magnification, WaveformZoomMath.maxZoom))
            })
        }
```

- [ ] **Step 3: Delete the now-unused `ScrollWheelHandler` / `ScrollWheelNSView` types**

Delete lines 390–414 (the `private struct ScrollWheelHandler: NSViewRepresentable` block and the `private class ScrollWheelNSView: NSView` block). The ⌘-scroll hook now lives inside `ZoomScrollView`.

- [ ] **Step 4: Update the hardcoded zoom clamp in the +/- buttons**

Replace the two button actions (currently at lines 118 and 131) with versions that use the constants:

```swift
                    Button(action: {
                        zoomLevel = max(WaveformZoomMath.minZoom, zoomLevel / 1.5)
                    }) {
```

```swift
                    Button(action: {
                        zoomLevel = min(WaveformZoomMath.maxZoom, zoomLevel * 1.5)
                    }) {
```

And their `disabled` / `foregroundStyle` checks:

```swift
                    .foregroundStyle(zoomLevel > WaveformZoomMath.minZoom ? .primary : .tertiary)
                    .disabled(zoomLevel <= WaveformZoomMath.minZoom)
```

```swift
                    .foregroundStyle(zoomLevel < WaveformZoomMath.maxZoom ? .primary : .tertiary)
                    .disabled(zoomLevel >= WaveformZoomMath.maxZoom)
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual smoke test**

Run the app. Load a song. Verify:
- Waveform renders.
- Horizontal scroll via trackpad/two-finger works.
- ⌘-scroll still zooms.
- Pinch magnify still zooms.
- +/- buttons still zoom.
- Seek by click still works.
- Downbeat triangle still drags.

If any regression, fix before proceeding.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift
git commit -m "refactor(waveform): host content in NSScrollView wrapper"
```

---

### Task 5: Add the ruler-strip drag gesture

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift`

- [ ] **Step 1: Add drag state**

Add alongside the other `@State` fields:

```swift
    @State private var dragStartZoom: CGFloat?
    @State private var dragAnchorFraction: CGFloat?
    @State private var dragCursorXInViewport: CGFloat?
```

- [ ] **Step 2: Add the ruler strip inside the ZStack**

Inside the `ZStack(alignment: .leading)` from Task 4, add this as the **last** child so it sits above other overlays (but the downbeat handle will still win via child-gesture priority since it has its own `.gesture` and smaller hit target):

```swift
                    zoomRulerStrip(width: totalWidth, geoWidth: geo.size.width)
```

- [ ] **Step 3: Implement `zoomRulerStrip`**

Add this method alongside the other private view builders in `WaveformView`:

```swift
    @ViewBuilder
    private func zoomRulerStrip(width: CGFloat, geoWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: width, height: WaveformZoomMath.rulerHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        if dragStartZoom == nil {
                            dragStartZoom = zoomLevel
                            // Anchor the content-space fraction under the cursor at mouse-down.
                            let startContentX = value.startLocation.x
                            let totalAtStart = geoWidth * zoomLevel
                            dragAnchorFraction = totalAtStart > 0 ? startContentX / totalAtStart : 0
                            // Cursor x in the viewport = content-space x minus current scroll origin.
                            dragCursorXInViewport = startContentX - scrollController.scrollOriginX
                        }
                        guard
                            let startZoom = dragStartZoom,
                            let anchor = dragAnchorFraction,
                            let cursorX = dragCursorXInViewport,
                            geoWidth > 0
                        else { return }

                        let newZoom = WaveformZoomMath.zoomFromDrag(
                            startZoom: startZoom,
                            translationY: value.translation.height
                        )
                        zoomLevel = newZoom

                        let newOrigin = WaveformZoomMath.scrollOriginForAnchor(
                            anchorFraction: anchor,
                            cursorXInViewport: cursorX,
                            geoWidth: geoWidth,
                            newZoom: newZoom
                        )
                        // Defer scroll so the NSScrollView sees the new documentView size from this frame.
                        DispatchQueue.main.async {
                            scrollController.setScrollOriginX(newOrigin)
                        }
                    }
                    .onEnded { _ in
                        dragStartZoom = nil
                        dragAnchorFraction = nil
                        dragCursorXInViewport = nil
                    }
            )
            .allowsHitTesting(true)
    }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual gesture test**

Run the app. Load a song. Verify each case:

1. Hover over the top ~18pt of the waveform → cursor becomes vertical resize.
2. Click-drag down → zoom increases; the bar under the cursor stays under the cursor.
3. Click-drag up → zoom decreases; same anchor behavior.
4. Drag all the way down → zoom clamps at 20x, no crash, no scroll jitter.
5. Drag all the way up → zoom clamps at 1x, scroll returns to 0.
6. Downbeat triangle (top) still drags horizontally — it should take priority within its hit rect.
7. Click in the waveform body (below top 18pt) still seeks.
8. ⌘-scroll still zooms. +/- buttons still zoom. Pinch still zooms.

If the anchor drifts noticeably, revisit the `cursorXInViewport` calculation in Step 3 — the most common cause is measuring `startLocation` in a different coordinate space than the scroll origin.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift
git commit -m "feat(waveform): Ableton-style vertical-drag zoom on top ruler strip"
```

---

### Task 6: Cleanup and spec sign-off

- [ ] **Step 1: Re-read the spec and check each non-goal**

Confirm we did not drift into: horizontal-drag ruler scroll, visible ruler ticks, changing pinch/buttons anchor behavior. If anything crept in, remove it.

- [ ] **Step 2: Run the full test suite**

Run: `xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: all tests pass, including `WaveformZoomMathTests`.

- [ ] **Step 3: Final commit if any cleanup changes**

```bash
git status
# If anything is pending:
git add -A
git commit -m "chore(waveform): cleanup after zoom-drag feature"
```

---

## Self-Review Notes

- **Spec coverage:** ruler strip (Task 5), gesture semantics (Task 5 step 3 + Task 2 math), anchor preservation (Task 2 + Task 5), NSScrollView swap (Tasks 3–4), cursor (Task 5 step 3), `rulerHeight` / sensitivity constants (Task 2). Testing checklist from the spec is the manual steps in Task 5 step 5.
- **Placeholders:** none — all steps contain runnable commands or full code.
- **Type consistency:** `WaveformZoomMath.zoomFromDrag`, `scrollOriginForAnchor`, `minZoom`, `maxZoom`, `dragSensitivity`, `rulerHeight`, `ScrollController.setScrollOriginX`, `ScrollController.scrollOriginX`, `HorizontalNSScrollView`, `ZoomScrollView.onCommandScroll` — all names match across tasks.
