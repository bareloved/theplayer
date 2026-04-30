# Bar / Second Jump Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Bars" picker in the transport bar with arrow-key shortcuts that jump the playhead by 1/2/4/8/16 bars (Snap on) or 1/2/5/15/30 seconds (Snap off).

**Architecture:** Pure jump math lives in a new `JumpMath.swift` (free functions, fully unit-tested). A small `KeyboardJumpMonitor` wraps `NSEvent.addLocalMonitorForEvents` and is owned by `ContentView`. The existing `SnapDivision` enum is deleted; its grid math becomes a free `barSnapPositions(...)` function in `JumpMath.swift`.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSEvent`), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-04-28-bar-jump-shortcuts-design.md`

---

## File Map

- **Create:** `ThePlayer/Audio/JumpMath.swift` — `JumpDirection` enum + `nextSecondTime`, `nextBarTime`, `barSnapPositions`.
- **Create:** `ThePlayer/Audio/KeyboardJumpMonitor.swift` — `NSEvent` local key monitor.
- **Create:** `ThePlayerTests/JumpMathTests.swift` — XCTest cases for the three free functions.
- **Modify:** `ThePlayer/Views/WaveformView.swift` — drop `snapDivision` property, swap to `barSnapPositions(...)`.
- **Modify:** `ThePlayer/Views/ContentView.swift` — drop `@State snapDivision`, swap `getSnapPositions`, install monitor.
- **Modify:** `ThePlayer/Views/TransportBar.swift` — remove "Bars" `Picker`, drop `snapDivision` binding, expand Snap button tooltip.
- **Delete:** `ThePlayer/Models/SnapDivision.swift`.
- **Regenerate:** `ThePlayer.xcodeproj` (via `xcodegen generate`) any time files are added or removed.

---

## Task 1: Add `JumpMath.swift` with `JumpDirection` and `nextSecondTime` (TDD)

**Files:**
- Create: `ThePlayer/Audio/JumpMath.swift`
- Create: `ThePlayerTests/JumpMathTests.swift`

- [ ] **Step 1: Create `JumpMath.swift` with the enum and a stub**

```swift
// ThePlayer/Audio/JumpMath.swift
import Foundation

enum JumpDirection {
    case forward
    case backward
}

/// Move `currentTime` by `seconds` in the chosen direction, clamped to `[0, duration]`.
/// Used when Snap is OFF; works without analysis.
func nextSecondTime(
    from currentTime: Float,
    direction: JumpDirection,
    seconds: Float,
    duration: Float
) -> Float {
    return currentTime  // stub — to be replaced
}
```

- [ ] **Step 2: Create `JumpMathTests.swift` with full coverage for `nextSecondTime`**

```swift
// ThePlayerTests/JumpMathTests.swift
import XCTest
@testable import ThePlayer

final class JumpMathTests: XCTestCase {

    // MARK: - nextSecondTime

    func testNextSecondForward() {
        XCTAssertEqual(nextSecondTime(from: 10, direction: .forward, seconds: 5, duration: 100), 15, accuracy: 0.0001)
    }

    func testNextSecondBackward() {
        XCTAssertEqual(nextSecondTime(from: 10, direction: .backward, seconds: 5, duration: 100), 5, accuracy: 0.0001)
    }

    func testNextSecondClampStart() {
        XCTAssertEqual(nextSecondTime(from: 3, direction: .backward, seconds: 5, duration: 100), 0, accuracy: 0.0001)
    }

    func testNextSecondClampEnd() {
        XCTAssertEqual(nextSecondTime(from: 98, direction: .forward, seconds: 5, duration: 100), 100, accuracy: 0.0001)
    }

    func testNextSecondAllShortcutValues() {
        let t: Float = 50
        let dur: Float = 100
        XCTAssertEqual(nextSecondTime(from: t, direction: .forward, seconds: 1, duration: dur), 51, accuracy: 0.0001)
        XCTAssertEqual(nextSecondTime(from: t, direction: .forward, seconds: 2, duration: dur), 52, accuracy: 0.0001)
        XCTAssertEqual(nextSecondTime(from: t, direction: .forward, seconds: 5, duration: dur), 55, accuracy: 0.0001)
        XCTAssertEqual(nextSecondTime(from: t, direction: .forward, seconds: 15, duration: dur), 65, accuracy: 0.0001)
        XCTAssertEqual(nextSecondTime(from: t, direction: .forward, seconds: 30, duration: dur), 80, accuracy: 0.0001)
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project so the new files are included**

Run: `xcodegen generate`
Expected: prints `Created project at ThePlayer.xcodeproj`.

- [ ] **Step 4: Run the new tests, verify they fail**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/JumpMathTests
```
Expected: 5 failures in `JumpMathTests` (stub returns `currentTime`).

- [ ] **Step 5: Implement `nextSecondTime`**

Replace the stub body in `ThePlayer/Audio/JumpMath.swift`:

```swift
func nextSecondTime(
    from currentTime: Float,
    direction: JumpDirection,
    seconds: Float,
    duration: Float
) -> Float {
    let delta: Float = direction == .forward ? seconds : -seconds
    return min(max(currentTime + delta, 0), duration)
}
```

- [ ] **Step 6: Run the tests, verify they pass**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/JumpMathTests
```
Expected: all `JumpMathTests` pass.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Audio/JumpMath.swift ThePlayerTests/JumpMathTests.swift ThePlayer.xcodeproj
git commit -m "feat(audio): add JumpDirection and nextSecondTime"
```

---

## Task 2: Add `nextBarTime` to `JumpMath` (TDD)

**Files:**
- Modify: `ThePlayer/Audio/JumpMath.swift`
- Modify: `ThePlayerTests/JumpMathTests.swift`

The bar-jump rule (single rule, no on-grid / off-grid special case):

- **Forward target** = the **N-th bar line strictly after** `currentTime`, where N = `bars`.
- **Backward target** = the **N-th bar line strictly before** `currentTime`.

Bar lines are at `firstBeatTime + k * barWidth` for integer `k`, where `barWidth = 60 / bpm * beatsPerBar`. The result is clamped to `[0, duration]`. Returns `nil` if `bpm <= 0`, `beatsPerBar <= 0`, or `bars <= 0`.

- [ ] **Step 1: Add the test cases to `JumpMathTests.swift`**

Append inside `JumpMathTests`:

```swift
    // MARK: - nextBarTime
    // bpm=240, beatsPerBar=4, firstBeat=0  →  barWidth = 60/240 * 4 = 1.0 s.
    // Bar lines at 0, 1, 2, 3, ...

    private let bpmFixture: Float = 240
    private let bpbFixture: Int = 4

    func testBarForwardFromOnGridFourBars() {
        XCTAssertEqual(
            nextBarTime(from: 3.0, direction: .forward, bars: 4,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100),
            7.0, accuracy: 0.0001
        )
    }

    func testBarForwardFromMidBarFourBars() {
        XCTAssertEqual(
            nextBarTime(from: 3.4, direction: .forward, bars: 4,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100),
            7.0, accuracy: 0.0001
        )
    }

    func testBarBackwardFromOnGridFourBarsClamps() {
        // 3.0 - 4 bars = -1.0 → clamped to 0.
        XCTAssertEqual(
            nextBarTime(from: 3.0, direction: .backward, bars: 4,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100),
            0.0, accuracy: 0.0001
        )
    }

    func testBarBackwardFromMidBarFourBars() {
        XCTAssertEqual(
            nextBarTime(from: 3.4, direction: .backward, bars: 4,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100),
            0.0, accuracy: 0.0001
        )
    }

    func testBarForwardOneBarFromOnGridMoves() {
        // A press always moves you, even when on-grid.
        XCTAssertEqual(
            nextBarTime(from: 3.0, direction: .forward, bars: 1,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100),
            4.0, accuracy: 0.0001
        )
    }

    func testBarBackwardOneBarFromOnGridMoves() {
        XCTAssertEqual(
            nextBarTime(from: 3.0, direction: .backward, bars: 1,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100),
            2.0, accuracy: 0.0001
        )
    }

    func testBarReturnsNilWhenBpmInvalid() {
        XCTAssertNil(
            nextBarTime(from: 3.0, direction: .forward, bars: 1,
                        bpm: 0, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100)
        )
    }

    func testBarReturnsNilWhenBeatsPerBarInvalid() {
        XCTAssertNil(
            nextBarTime(from: 3.0, direction: .forward, bars: 1,
                        bpm: bpmFixture, beatsPerBar: 0,
                        firstBeatTime: 0, duration: 100)
        )
    }

    func testBarReturnsNilWhenBarsInvalid() {
        XCTAssertNil(
            nextBarTime(from: 3.0, direction: .forward, bars: 0,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100)
        )
    }

    func testBarClampsAtEndOfDuration() {
        XCTAssertEqual(
            nextBarTime(from: 95.0, direction: .forward, bars: 16,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0, duration: 100),
            100.0, accuracy: 0.0001
        )
    }

    func testBarAllShortcutValuesFromMidBar() {
        // From 10.4: forward bars=1 → 11, =2 → 12, =4 → 14, =8 → 18, =16 → 26.
        let cases: [(Int, Float)] = [(1, 11), (2, 12), (4, 14), (8, 18), (16, 26)]
        for (bars, expected) in cases {
            XCTAssertEqual(
                nextBarTime(from: 10.4, direction: .forward, bars: bars,
                            bpm: bpmFixture, beatsPerBar: bpbFixture,
                            firstBeatTime: 0, duration: 100),
                expected, accuracy: 0.0001,
                "bars=\(bars)"
            )
        }
    }

    func testBarRespectsNonZeroFirstBeat() {
        // firstBeat=0.25, bars at 0.25, 1.25, 2.25, 3.25...
        // From 1.5 forward bars=1 → 2.25.
        XCTAssertEqual(
            nextBarTime(from: 1.5, direction: .forward, bars: 1,
                        bpm: bpmFixture, beatsPerBar: bpbFixture,
                        firstBeatTime: 0.25, duration: 100),
            2.25, accuracy: 0.0001
        )
    }
```

- [ ] **Step 2: Add a stub implementation to `JumpMath.swift`**

Append to `ThePlayer/Audio/JumpMath.swift`:

```swift
/// Move `currentTime` to the N-th bar line strictly after / before, clamped to `[0, duration]`.
/// Returns `nil` when the analysis-derived inputs are invalid; callers should consume the keypress
/// as a noop in that case (Snap-ON requires analysis).
func nextBarTime(
    from currentTime: Float,
    direction: JumpDirection,
    bars: Int,
    bpm: Float,
    beatsPerBar: Int,
    firstBeatTime: Float,
    duration: Float
) -> Float? {
    return nil  // stub
}
```

- [ ] **Step 3: Run only the new tests, verify they fail**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/JumpMathTests
```
Expected: previous `nextSecondTime` tests still pass; the 12 new bar-time tests fail (stub returns `nil`, comparisons fail except the three "returns nil" ones — those will pass already).

- [ ] **Step 4: Implement `nextBarTime`**

Replace the stub body:

```swift
func nextBarTime(
    from currentTime: Float,
    direction: JumpDirection,
    bars: Int,
    bpm: Float,
    beatsPerBar: Int,
    firstBeatTime: Float,
    duration: Float
) -> Float? {
    guard bpm > 0, beatsPerBar > 0, bars > 0 else { return nil }
    let barWidth: Float = 60.0 / bpm * Float(beatsPerBar)
    guard barWidth > 0 else { return nil }

    let offset = (currentTime - firstBeatTime) / barWidth
    let target: Float
    switch direction {
    case .forward:
        // Smallest integer k strictly greater than offset = floor(offset) + 1.
        let k0 = floor(offset) + 1
        target = firstBeatTime + (k0 + Float(bars - 1)) * barWidth
    case .backward:
        // Largest integer k strictly less than offset = ceil(offset) - 1.
        let k0 = ceil(offset) - 1
        target = firstBeatTime + (k0 - Float(bars - 1)) * barWidth
    }
    return min(max(target, 0), duration)
}
```

- [ ] **Step 5: Run the tests, verify they pass**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/JumpMathTests
```
Expected: all `JumpMathTests` pass.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Audio/JumpMath.swift ThePlayerTests/JumpMathTests.swift
git commit -m "feat(audio): add nextBarTime for snap-on bar jumps"
```

---

## Task 3: Add `barSnapPositions` to `JumpMath` (TDD)

**Files:**
- Modify: `ThePlayer/Audio/JumpMath.swift`
- Modify: `ThePlayerTests/JumpMathTests.swift`

This replaces `SnapDivision.oneBar.snapPositions(...)` with a free function. Behavior is identical to the existing `SnapDivision` math when `rawValue = 1`.

- [ ] **Step 1: Add tests**

Append inside `JumpMathTests`:

```swift
    // MARK: - barSnapPositions

    func testBarSnapPositionsFromOrigin() {
        // bpm=240, bpb=4 → barWidth=1. Origin=0, duration=5 → [0,1,2,3,4].
        let positions = barSnapPositions(beats: [0], bpm: 240, duration: 5,
                                         beatsPerBar: 4, firstBeatTime: 0)
        XCTAssertEqual(positions.count, 5)
        XCTAssertEqual(positions[0], 0, accuracy: 0.0001)
        XCTAssertEqual(positions[1], 1, accuracy: 0.0001)
        XCTAssertEqual(positions[4], 4, accuracy: 0.0001)
    }

    func testBarSnapPositionsExtendsBackwardFromFirstBeat() {
        // firstBeat=2, barWidth=1, duration=5 → [0,1,2,3,4].
        let positions = barSnapPositions(beats: [], bpm: 240, duration: 5,
                                         beatsPerBar: 4, firstBeatTime: 2)
        XCTAssertEqual(positions.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(positions.last ?? -1, 4, accuracy: 0.0001)
    }

    func testBarSnapPositionsEmptyWhenInputsInvalid() {
        XCTAssertTrue(barSnapPositions(beats: [], bpm: 0, duration: 100,
                                       beatsPerBar: 4, firstBeatTime: 0).isEmpty)
        XCTAssertTrue(barSnapPositions(beats: [], bpm: 240, duration: 100,
                                       beatsPerBar: 0, firstBeatTime: 0).isEmpty)
        XCTAssertTrue(barSnapPositions(beats: [], bpm: 240, duration: 0,
                                       beatsPerBar: 4, firstBeatTime: 0).isEmpty)
    }

    func testBarSnapPositionsFallsBackToBeatsFirstWhenNoFirstBeat() {
        // No firstBeatTime; first element of `beats` is the origin.
        let positions = barSnapPositions(beats: [0.5], bpm: 240, duration: 3,
                                         beatsPerBar: 4, firstBeatTime: nil)
        XCTAssertEqual(positions.first ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(positions[1], 1.5, accuracy: 0.0001)
        XCTAssertEqual(positions.last ?? -1, 2.5, accuracy: 0.0001)
    }
```

- [ ] **Step 2: Add a stub to `JumpMath.swift`**

Append to `ThePlayer/Audio/JumpMath.swift`:

```swift
/// Bar-aligned snap positions across `[0, duration]`, regenerated from `firstBeatTime`
/// outward (forward AND backward), so a downbeat in the middle of the file produces
/// a fully-aligned grid. Returns `[]` when `bpm`, `beatsPerBar`, or `duration` is non-positive.
/// Drop-in replacement for the previous `SnapDivision.oneBar.snapPositions(...)`.
func barSnapPositions(
    beats: [Float],
    bpm: Float,
    duration: Float,
    beatsPerBar: Int,
    firstBeatTime: Float? = nil
) -> [Float] {
    return []  // stub
}
```

- [ ] **Step 3: Run tests, verify they fail**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/JumpMathTests
```
Expected: 4 new `barSnapPositions` tests fail (stub returns empty).

- [ ] **Step 4: Implement `barSnapPositions`**

Replace the stub body:

```swift
func barSnapPositions(
    beats: [Float],
    bpm: Float,
    duration: Float,
    beatsPerBar: Int,
    firstBeatTime: Float? = nil
) -> [Float] {
    guard bpm > 0, beatsPerBar > 0, duration > 0 else { return [] }
    let origin: Float = firstBeatTime ?? (beats.first ?? 0)
    let barWidth: Float = 60.0 / bpm * Float(beatsPerBar)
    guard barWidth > 0 else { return [] }

    var positions: [Float] = []
    var t = origin
    while t < duration {
        positions.append(t)
        t += barWidth
    }
    var tBack = origin - barWidth
    while tBack >= 0 {
        positions.insert(tBack, at: 0)
        tBack -= barWidth
    }
    return positions
}
```

- [ ] **Step 5: Run tests, verify they pass**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/JumpMathTests
```
Expected: all `JumpMathTests` pass.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Audio/JumpMath.swift ThePlayerTests/JumpMathTests.swift
git commit -m "feat(audio): add barSnapPositions free function"
```

---

## Task 4: Migrate `WaveformView` and `ContentView` from `SnapDivision` to `barSnapPositions`

After this task, `SnapDivision` is referenced only by `TransportBar` (the picker) and `ContentView` (the `@State` and the binding pass).

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift` — drop the `snapDivision` property, drop the `.onChange(of: snapDivision)` hook, swap `gridPositions` body.
- Modify: `ThePlayer/Views/ContentView.swift` — swap `getSnapPositions` body, drop `snapDivision:` argument from the `WaveformView` constructor call.

- [ ] **Step 1: Edit `WaveformView.swift` — remove the `snapDivision` property**

Open `ThePlayer/Views/WaveformView.swift`. Around line 11, delete the line:

```swift
    let snapDivision: SnapDivision
```

- [ ] **Step 2: Edit `WaveformView.swift` — remove the `onChange` hook**

Around line 406, delete:

```swift
        .onChange(of: snapDivision) { _, _ in recomputeGridCaches() }
```

- [ ] **Step 3: Edit `WaveformView.swift` — replace `gridPositions` body**

Around line 461, replace:

```swift
    /// Grid positions based on current snap division
    private var gridPositions: [Float] {
        snapDivision.snapPositions(
            beats: beats, bpm: bpm, duration: duration,
            beatsPerBar: timeSignature.beatsPerBar,
            firstBeatTime: firstDownbeatTime
        )
    }
```

with:

```swift
    /// Bar-line grid positions (always 1 bar — no longer user-configurable).
    private var gridPositions: [Float] {
        barSnapPositions(
            beats: beats, bpm: bpm, duration: duration,
            beatsPerBar: timeSignature.beatsPerBar,
            firstBeatTime: firstDownbeatTime
        )
    }
```

- [ ] **Step 4: Edit `ContentView.swift` — replace `getSnapPositions` body**

Around line 579, replace:

```swift
    private func getSnapPositions() -> [Float] {
        let analysis = analysisService.lastAnalysis
        let bpb = analysis?.timeSignature.beatsPerBar ?? 4
        let beats = analysis?.beats ?? []
        let firstBeatTime: Float? = analysis?.firstDownbeatTime
        return snapDivision.snapPositions(
            beats: beats,
            bpm: analysis?.bpm ?? 0,
            duration: audioEngine.duration,
            beatsPerBar: bpb,
            firstBeatTime: firstBeatTime
        )
    }
```

with:

```swift
    private func getSnapPositions() -> [Float] {
        let analysis = analysisService.lastAnalysis
        return barSnapPositions(
            beats: analysis?.beats ?? [],
            bpm: analysis?.bpm ?? 0,
            duration: audioEngine.duration,
            beatsPerBar: analysis?.timeSignature.beatsPerBar ?? 4,
            firstBeatTime: analysis?.firstDownbeatTime
        )
    }
```

- [ ] **Step 5: Edit `ContentView.swift` — remove the `snapDivision:` argument from the `WaveformView(...)` call**

Around line 250, delete the line:

```swift
                    snapDivision: snapDivision,
```

- [ ] **Step 6: Build and run tests to verify nothing regressed**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```
Expected: `BUILD SUCCEEDED`. No references to `snapDivision` should remain in `WaveformView.swift`.

Then:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift ThePlayer/Views/ContentView.swift
git commit -m "refactor(views): use barSnapPositions for grid; drop snapDivision from WaveformView"
```

---

## Task 5: Remove the "Bars" picker from `TransportBar` and update Snap tooltip

After this task, `SnapDivision` is no longer referenced anywhere (the file itself is deleted in Task 6).

**Files:**
- Modify: `ThePlayer/Views/TransportBar.swift`
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Edit `TransportBar.swift` — drop the `snapDivision` binding**

Around line 8, delete:

```swift
    @Binding var snapDivision: SnapDivision
```

- [ ] **Step 2: Edit `TransportBar.swift` — remove the Picker**

Around lines 46–56, delete the entire `Picker("Bars", selection: $snapDivision) { ... }` block including all view modifiers attached to it (`.pickerStyle`, `.fixedSize`, `.font`, `.opacity`, `.disabled`, `.allowsHitTesting`).

- [ ] **Step 3: Edit `TransportBar.swift` — add the shortcut tooltip to the Snap button**

Find the existing Snap button block (around line 39):

```swift
            Button(action: { snapToGrid.toggle() }) {
                Label("Snap", systemImage: "grid")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(snapToGrid ? .purple : .secondary)
```

Append a `.help(...)` modifier after `.tint(...)`:

```swift
            .help("""
                Snap on:  ←/→ 1 bar · ⇧ 2 · ⌥ 4 · ⌘ 8 · ⌘⇧ 16
                Snap off: ←/→ 1 s · ⇧ 2 s · ⌥ 5 s · ⌘ 15 s · ⌘⇧ 30 s
                """)
```

Also update the doc comment on `utilityRow` (line 23) from:

```swift
    /// Top row — utility controls (A-B, Snap, Bars picker). Centered.
```

to:

```swift
    /// Top row — utility controls (A-B, Snap). Centered.
```

- [ ] **Step 4: Edit `ContentView.swift` — remove `@State snapDivision`**

Around line 12, delete:

```swift
    @State private var snapDivision: SnapDivision = .oneBar
```

- [ ] **Step 5: Edit `ContentView.swift` — drop the binding pass to `TransportBar`**

Around line 314, delete the line:

```swift
                snapDivision: $snapDivision,
```

- [ ] **Step 6: Build and verify**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```
Expected: `BUILD SUCCEEDED`. No references to `SnapDivision` should remain outside `ThePlayer/Models/SnapDivision.swift` itself.

Sanity check:
```
grep -rn "SnapDivision\|snapDivision" ThePlayer ThePlayerTests
```
Expected: only matches in `ThePlayer/Models/SnapDivision.swift`.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/TransportBar.swift ThePlayer/Views/ContentView.swift
git commit -m "feat(transport): remove Bars picker; add shortcut cheatsheet to Snap tooltip"
```

---

## Task 6: Delete `SnapDivision.swift`

**Files:**
- Delete: `ThePlayer/Models/SnapDivision.swift`

- [ ] **Step 1: Delete the file**

Run: `rm ThePlayer/Models/SnapDivision.swift`

- [ ] **Step 2: Regenerate the Xcode project**

Run: `xcodegen generate`

- [ ] **Step 3: Build and run tests**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```
Expected: `BUILD SUCCEEDED`.

```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Models/SnapDivision.swift ThePlayer.xcodeproj
git commit -m "chore: delete SnapDivision (replaced by barSnapPositions)"
```

---

## Task 7: Add `KeyboardJumpMonitor.swift` (not yet wired)

The monitor is a small class that owns an `NSEvent` local key monitor. It is constructed with the `AudioEngine` plus a closure that produces a `JumpContext` (the live values it needs at keypress time: `snapToGrid`, the current `TrackAnalysis?`, and `duration`).

**Files:**
- Create: `ThePlayer/Audio/KeyboardJumpMonitor.swift`

- [ ] **Step 1: Create the file**

```swift
// ThePlayer/Audio/KeyboardJumpMonitor.swift
import AppKit
import Foundation

/// Snapshot of state needed to handle a keypress. Re-fetched on every event
/// (via the closure passed to `KeyboardJumpMonitor`), so the monitor never
/// holds stale snap / analysis values.
struct JumpContext {
    let snapToGrid: Bool
    let analysis: TrackAnalysis?
    let duration: Float
}

/// Owns an `NSEvent.addLocalMonitorForEvents` handler that translates
/// arrow-key presses (with optional modifiers) into seeks on `AudioEngine`.
/// Mapping (Snap on / off):
///
///     (none)      1 bar  / 1 s
///     shift       2 bars / 2 s
///     option      4 bars / 5 s
///     cmd         8 bars / 15 s
///     cmd+shift  16 bars / 30 s
///
/// Any other modifier combination is passed through untouched. Text-input
/// first responders (search fields, rename fields) are passed through too.
@MainActor
final class KeyboardJumpMonitor {
    private var token: Any?
    private let audioEngine: AudioEngine
    private let context: () -> JumpContext

    init(audioEngine: AudioEngine, context: @escaping () -> JumpContext) {
        self.audioEngine = audioEngine
        self.context = context
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    // MARK: - Private

    private static let keyCodeLeftArrow: UInt16 = 0x7B
    private static let keyCodeRightArrow: UInt16 = 0x7C

    private func handle(_ event: NSEvent) -> NSEvent? {
        let direction: JumpDirection
        switch event.keyCode {
        case Self.keyCodeLeftArrow:  direction = .backward
        case Self.keyCodeRightArrow: direction = .forward
        default: return event
        }

        // Pass through if a text input has focus.
        if let responder = NSApp.keyWindow?.firstResponder {
            if responder is NSText { return event }
        }

        // Only handle the five claimed modifier combos. Strip caps lock / numpad / fn.
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        let bars: Int
        let seconds: Float
        switch mods {
        case []:                  bars = 1;  seconds = 1
        case [.shift]:            bars = 2;  seconds = 2
        case [.option]:           bars = 4;  seconds = 5
        case [.command]:          bars = 8;  seconds = 15
        case [.command, .shift]:  bars = 16; seconds = 30
        default: return event
        }

        let ctx = context()
        let target: Float?
        if ctx.snapToGrid {
            guard let analysis = ctx.analysis else {
                // Snap-ON requires analysis. Consume the event so there is no beep,
                // but do not move the playhead.
                return nil
            }
            target = nextBarTime(
                from: audioEngine.currentTime,
                direction: direction,
                bars: bars,
                bpm: analysis.bpm,
                beatsPerBar: analysis.timeSignature.beatsPerBar,
                firstBeatTime: analysis.firstDownbeatTime,
                duration: ctx.duration
            )
        } else {
            target = nextSecondTime(
                from: audioEngine.currentTime,
                direction: direction,
                seconds: seconds,
                duration: ctx.duration
            )
        }

        if let t = target {
            audioEngine.seek(to: t)
        }
        return nil  // consume — no system beep
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate`
Then:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```
Expected: `BUILD SUCCEEDED`. The class is not yet referenced anywhere; this is intentional — Task 8 wires it.

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Audio/KeyboardJumpMonitor.swift ThePlayer.xcodeproj
git commit -m "feat(audio): add KeyboardJumpMonitor (not yet wired)"
```

---

## Task 8: Wire `KeyboardJumpMonitor` into `ContentView`

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Add a `@State` reference to the monitor**

Near the other `@State` declarations at the top of `ContentView`, add:

```swift
    @State private var keyboardMonitor: KeyboardJumpMonitor?
```

- [ ] **Step 2: Find the root view returned by `body`**

Locate the outermost view returned by `var body: some View`. It is the view that already contains the `WaveformView` + `TransportBar` layout.

- [ ] **Step 3: Add `.onAppear` and `.onDisappear` modifiers to the root view**

Append (after any existing modifiers on the root view):

```swift
        .onAppear {
            let monitor = KeyboardJumpMonitor(audioEngine: audioEngine) {
                JumpContext(
                    snapToGrid: snapToGrid,
                    analysis: analysisService.lastAnalysis,
                    duration: audioEngine.duration
                )
            }
            monitor.start()
            keyboardMonitor = monitor
        }
        .onDisappear {
            keyboardMonitor?.stop()
            keyboardMonitor = nil
        }
```

The closure is called fresh on each keypress, so toggling Snap or finishing analysis is reflected immediately.

- [ ] **Step 4: Build**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Run the full test suite**

Run:
```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Views/ContentView.swift
git commit -m "feat(views): install KeyboardJumpMonitor in ContentView"
```

---

## Task 9: Manual QA pass

The keyboard monitor crosses an AppKit boundary that XCTest cannot exercise. Run the app and verify each item.

- [ ] **Step 1: Launch the app and open a track with completed analysis**

```
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
open build/Debug/ThePlayer.app
```

(Or run via Xcode.) Open a music file and wait until analysis finishes.

- [ ] **Step 2: Verify the "Bars" picker is gone from the transport bar**

Expected: only Loop, Snap, (optional Next), and timing controls remain on the utility row.

- [ ] **Step 3: With Snap ON, exercise every modifier combo**

Tap each in sequence and confirm the playhead moves the right number of bars (read the bar number from the WaveformView ruler):

- `←` / `→` → 1 bar
- `⇧←` / `⇧→` → 2 bars
- `⌥←` / `⌥→` → 4 bars
- `⌘←` / `⌘→` → 8 bars
- `⌘⇧←` / `⌘⇧→` → 16 bars

- [ ] **Step 4: With Snap ON and playhead mid-bar, press `→`**

Drag the playhead to mid-bar. Press `→`. Expected: lands on the next bar line, not 1 bar past mid-bar.

- [ ] **Step 5: Toggle Snap OFF and exercise every modifier combo**

Expected jumps in seconds: 1, 2, 5, 15, 30.

- [ ] **Step 6: Click into a text input and confirm arrows do not hijack**

Click into the library search field (or any text field). Press `←` / `→`. Expected: the text caret moves; the playhead does not.

- [ ] **Step 7: Press `←` at playhead = 0 and `→` near end of track**

Expected: playhead clamps; no system beep.

- [ ] **Step 8: Hover the Snap button**

Expected: tooltip shows both shortcut tables (Snap on / Snap off lines).

- [ ] **Step 9: Load a track and press arrows BEFORE analysis completes**

- With Snap **OFF**: arrows seek by seconds (works without analysis).
- With Snap **ON**: arrows are silent noops (no beep, no movement).

- [ ] **Step 10: If everything passes, the feature is done**

No further commits needed. Push the branch when ready:

```bash
git push -u origin ui-ux
```
