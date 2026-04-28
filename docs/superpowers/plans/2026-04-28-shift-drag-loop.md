# Shift+Drag Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two-click "A-B" loop flow with a shift+drag gesture on the waveform plus an Ableton-style on/off loop toggle button.

**Architecture:** Add an `isLoopEnabled` state in `ContentView` that gates whether `loopRegion` is sent to the audio engine. Add a parallel shift-modified `simultaneousGesture` in `WaveformView` (mirroring the existing option-modified section-creation drag) that commits a new region. Replace the A-B button in `TransportBar` with a toggle bound to `isLoopEnabled`. Then delete the now-dead two-click flow (`isSettingLoop`, `pendingLoopStart`, `handleLoopPoint`, `pendingLoopMarker`).

**Tech Stack:** SwiftUI, AppKit (`NSEvent.modifierFlags`), Swift 6, macOS app target.

**Spec:** `docs/superpowers/specs/2026-04-28-shift-drag-loop-design.md`

**A note on tests:** This work is almost entirely SwiftUI gesture/state plumbing. The existing `ThePlayerTests/LoopRegionTests.swift` covers the model. The new gesture's snap/min-length logic lives inside a `DragGesture.onEnded` closure and is not a target for new XCTests; verification is done by running the app. Do not invent a wrapper just to have something to unit-test.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `ThePlayer/Views/ContentView.swift` | Modify | Add `isLoopEnabled` state, gate `audioEngine.setLoop` by it, wire shift-drag callback, remove dead state. |
| `ThePlayer/Views/TransportBar.swift` | Modify | Replace A-B button with Loop on/off toggle; remove `isSettingLoop` binding; add hint when no region exists. |
| `ThePlayer/Views/WaveformView.swift` | Modify | Add shift+drag gesture with live preview + commit callback; remove `isSettingLoop`/`pendingLoopStart`/`onLoopPointSet` props, the click-branch for loop, the `pendingLoopMarker`, and the orange overlay border. |

No new files. No model changes. `LoopRegion` and `AudioEngine.setLoop`/`playLoop` are unchanged.

---

## Task 1: Add `isLoopEnabled` toggle state and gate audio-engine wiring

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift:8-12, 137-142, 405-409`

This is purely additive. Default `true`, so all existing flows that set `loopRegion` continue to loop. The toggle does nothing user-visible yet (no button); we'll add it in Task 3.

- [ ] **Step 1: Add the new state variable**

In `ContentView.swift`, near the existing loop state (around line 8), add `isLoopEnabled`:

```swift
    @State private var loopRegion: LoopRegion?
    @State private var isLoopEnabled: Bool = true
    @State private var isTargeted = false
    @State private var isSettingLoop = false
    @State private var pendingLoopStart: Float?
```

- [ ] **Step 2: Gate the existing `onChange(of: loopRegion)` block by `isLoopEnabled`**

Replace the block at `ContentView.swift:137-142`:

```swift
        .onChange(of: loopRegion) { _, newLoop in
            audioEngine.setLoop(newLoop)
            if newLoop != nil {
                audioEngine.playLoop()
            }
        }
```

with this version that consults the toggle:

```swift
        .onChange(of: loopRegion) { _, newLoop in
            let effective = isLoopEnabled ? newLoop : nil
            audioEngine.setLoop(effective)
            if effective != nil {
                audioEngine.playLoop()
            }
        }
```

- [ ] **Step 3: Add an `onChange(of: isLoopEnabled)` to apply the toggle live**

Immediately after the `onChange(of: loopRegion)` block, add:

```swift
        .onChange(of: isLoopEnabled) { _, enabled in
            if enabled, let region = loopRegion {
                audioEngine.setLoop(region)
                audioEngine.playLoop()
            } else {
                audioEngine.setLoop(nil)
            }
        }
```

- [ ] **Step 4: Build to confirm no regressions**

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`. App behavior should be unchanged at runtime — `isLoopEnabled` defaults to `true`, so loop creation paths still loop.

- [ ] **Step 5: Run existing tests**

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test
```

Expected: all existing tests pass (LoopRegionTests, AudioEngineTests, etc.).

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Views/ContentView.swift
git commit -m "feat(loop): add isLoopEnabled state gating audio-engine setLoop"
```

---

## Task 2: Add shift+drag gesture and live preview to `WaveformView`

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift` (add props, state, gesture, preview overlay)
- Modify: `ThePlayer/Views/ContentView.swift:233-271` (pass new callback)

We mirror the existing option+drag-for-sections pattern: `simultaneousGesture` with `minimumDistance: 8`, modifier check inside `onChanged`, floor/ceil snapping, commit on `onEnded`.

- [ ] **Step 1: Add new state + a commit callback prop in `WaveformView`**

In `WaveformView.swift`, near the section-drag state (around line 39-42), add three new state vars:

```swift
    @State private var sectionDragActive: Bool = false
    @State private var sectionDragStartTime: Float?
    @State private var sectionDragCurrentTime: Float?
    @State private var loopDragActive: Bool = false
    @State private var loopDragStartTime: Float?
    @State private var loopDragCurrentTime: Float?
```

In the `WaveformView` property list (top of the struct, around line 18), add a new commit callback after `onLoopPointSet`:

```swift
    let onLoopPointSet: (Float) -> Void
    let onLoopRegionSet: (LoopRegion) -> Void
```

- [ ] **Step 2: Render the live drag preview**

In the body, add a preview overlay that mirrors the section-drag preview. Insert this block right after the existing section-drag preview (around line 97-115), inside the same `ZStack(alignment: .leading)`:

```swift
                        if loopDragActive,
                           let s = loopDragStartTime,
                           let e = loopDragCurrentTime {
                            let lo = min(s, e)
                            let hi = max(s, e)
                            let snappedLo: Float = snapToGrid ? gridFloor(lo) : lo
                            let snappedHi: Float = snapToGrid ? gridCeil(hi) : hi
                            let leftX = max(0, CGFloat(snappedLo / duration) * totalWidth)
                            let rightX = min(totalWidth, CGFloat(snappedHi / duration) * totalWidth)
                            let width = max(0, rightX - leftX)
                            Rectangle()
                                .fill(Color.blue.opacity(0.18))
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                )
                                .frame(width: width, height: waveHeight)
                                .offset(x: leftX)
                        }
```

- [ ] **Step 3: Add the shift+drag `simultaneousGesture`**

Locate the existing section-drag `simultaneousGesture` (starts at `WaveformView.swift:206`). Immediately after its closing `)`, add a parallel gesture for shift+drag:

```swift
                    .simultaneousGesture(
                        // minimumDistance: 8 keeps stationary clicks from triggering this
                        // gesture so plain-click seek still works.
                        DragGesture(minimumDistance: 8, coordinateSpace: .local)
                            .onChanged { value in
                                guard totalWidth > 0, duration > 0 else { return }
                                if !loopDragActive {
                                    guard NSEvent.modifierFlags.contains(.shift) else { return }
                                    // Don't compete with the section drag (option) or the
                                    // align drag (command).
                                    if NSEvent.modifierFlags.contains(.option) { return }
                                    if NSEvent.modifierFlags.contains(.command) { return }
                                    loopDragActive = true
                                    loopDragStartTime = Float(value.startLocation.x / totalWidth) * duration
                                    NSCursor.crosshair.set()
                                }
                                loopDragCurrentTime = Float(value.location.x / totalWidth) * duration
                            }
                            .onEnded { value in
                                defer {
                                    loopDragActive = false
                                    loopDragStartTime = nil
                                    loopDragCurrentTime = nil
                                    NSCursor.arrow.set()
                                }
                                guard loopDragActive,
                                      let startT = loopDragStartTime else { return }
                                let dx = value.location.x - value.startLocation.x
                                guard abs(dx) >= 8 else { return }
                                let rawEnd = Float(value.location.x / totalWidth) * duration
                                let lo = min(startT, rawEnd)
                                let hi = max(startT, rawEnd)
                                let snappedLo = snapToGrid ? gridFloor(lo) : lo
                                let snappedHi = snapToGrid ? gridCeil(hi) : hi
                                guard snappedHi - snappedLo > 0.1 else { return }
                                onLoopRegionSet(LoopRegion(startTime: snappedLo, endTime: snappedHi))
                            }
                    )
                    .simultaneousGesture(
                        // ... existing section drag stays unchanged below
```

(The "..." comment is illustrative — leave the existing section gesture as it was; just insert the new one above it.)

- [ ] **Step 4: Wire the new callback in `ContentView`'s `WaveformView(...)` call site**

In `ContentView.swift` around line 247, add `onLoopRegionSet` to the existing `WaveformView(...)` arguments. Replace:

```swift
                    onSeek: { time in audioEngine.seek(to: time) },
                    onLoopPointSet: { time in handleLoopPoint(time) },
```

with:

```swift
                    onSeek: { time in audioEngine.seek(to: time) },
                    onLoopPointSet: { time in handleLoopPoint(time) },
                    onLoopRegionSet: { region in
                        loopRegion = region
                        isLoopEnabled = true
                    },
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Manual verification**

Run the app. Load a song.

- Hold Shift, drag across two bars on the waveform. Expect: blue dashed preview rectangle while dragging; on release, a loop region appears and playback loops it.
- Release with a sub-8px drag. Expect: nothing happens (no zero-length loop).
- Without Shift, drag → no loop preview appears (existing behaviors unaffected).
- With Option, drag → existing section-creation behavior unchanged.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift ThePlayer/Views/ContentView.swift
git commit -m "feat(loop): shift+drag waveform creates loop region"
```

---

## Task 3: Replace A-B button with Loop on/off toggle in `TransportBar`

**Files:**
- Modify: `ThePlayer/Views/TransportBar.swift:5-7, 22-30, 122-129`
- Modify: `ThePlayer/Views/ContentView.swift:294-298` (call-site bindings)

- [ ] **Step 1: Update `TransportBar` bindings**

Replace lines 5-7:

```swift
    @Binding var loopRegion: LoopRegion?
    @Binding var isSettingLoop: Bool
    @Binding var snapToGrid: Bool
```

with:

```swift
    @Binding var loopRegion: LoopRegion?
    @Binding var isLoopEnabled: Bool
    @Binding var snapToGrid: Bool
```

- [ ] **Step 2: Add a transient-hint state**

Inside the `TransportBar` struct, add a state for the empty-region hint:

```swift
struct TransportBar: View {
    @Bindable var audioEngine: AudioEngine
    @Binding var loopRegion: LoopRegion?
    @Binding var isLoopEnabled: Bool
    @Binding var snapToGrid: Bool
    @Binding var snapDivision: SnapDivision
    let isInSetlist: Bool
    let onNextInSetlist: () -> Void
    let timingControls: AnyView?

    @State private var showEmptyHint: Bool = false
```

- [ ] **Step 3: Replace the A-B button with the Loop toggle**

Replace the button block at lines 25-30:

```swift
            Button(action: toggleLoopMode) {
                Label(isSettingLoop ? "Click waveform..." : "A-B", systemImage: "repeat")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(isSettingLoop ? .orange : (loopRegion != nil ? .blue : .secondary))
```

with:

```swift
            Button(action: toggleLoopEnabled) {
                Label("Loop", systemImage: "repeat")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(loopRegion != nil && isLoopEnabled ? .blue : .secondary)
            .help("Shift+drag waveform to set loop")
            .popover(isPresented: $showEmptyHint, arrowEdge: .top) {
                Text("Shift+drag the waveform to set a loop")
                    .font(.caption)
                    .padding(8)
            }
```

- [ ] **Step 4: Replace `toggleLoopMode` with `toggleLoopEnabled`**

Replace the helper at lines 122-129:

```swift
    private func toggleLoopMode() {
        if loopRegion != nil {
            loopRegion = nil
            isSettingLoop = false
        } else {
            isSettingLoop = true
        }
    }
```

with:

```swift
    private func toggleLoopEnabled() {
        if loopRegion == nil {
            // No region yet — show a transient hint and auto-dismiss after 2s.
            showEmptyHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showEmptyHint = false
            }
            return
        }
        isLoopEnabled.toggle()
    }
```

- [ ] **Step 5: Update the `TransportBar(...)` call site in `ContentView`**

Replace lines 294-298:

```swift
            TransportBar(
                audioEngine: audioEngine,
                loopRegion: $loopRegion,
                isSettingLoop: $isSettingLoop,
                snapToGrid: $snapToGrid,
                snapDivision: $snapDivision,
```

with:

```swift
            TransportBar(
                audioEngine: audioEngine,
                loopRegion: $loopRegion,
                isLoopEnabled: $isLoopEnabled,
                snapToGrid: $snapToGrid,
                snapDivision: $snapDivision,
```

- [ ] **Step 6: Build**

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`. (The old `isSettingLoop` state in `ContentView` is still present but unused by `TransportBar` now — it's still consumed by `WaveformView`; we'll remove it in Task 4.)

- [ ] **Step 7: Manual verification**

- Click the Loop button with no region: popover hint appears for 2s; nothing else changes.
- Shift+drag a region: button turns blue automatically (auto-enable from Task 2).
- Click the Loop button while looping: button turns muted/secondary; playback flows past the region without looping; region overlay stays drawn.
- Click again: button turns blue; playback re-loops the region.

- [ ] **Step 8: Commit**

```bash
git add ThePlayer/Views/TransportBar.swift ThePlayer/Views/ContentView.swift
git commit -m "feat(loop): replace A-B button with on/off toggle bound to isLoopEnabled"
```

---

## Task 4: Remove dead two-click loop flow

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift` (drop `isSettingLoop`, `pendingLoopStart`, `handleLoopPoint`, Esc resets)
- Modify: `ThePlayer/Views/WaveformView.swift` (drop props, the `isSettingLoop` click branch, the orange border overlay, the `pendingLoopMarker`)

After this task, the only paths to set `loopRegion` are: shift+drag, section-click, and the persisted-loop restore in `loadSongFromLibrary`.

- [ ] **Step 1: Remove `isSettingLoop` and `pendingLoopStart` state in `ContentView`**

Replace the state block:

```swift
    @State private var loopRegion: LoopRegion?
    @State private var isLoopEnabled: Bool = true
    @State private var isTargeted = false
    @State private var isSettingLoop = false
    @State private var pendingLoopStart: Float?
```

with:

```swift
    @State private var loopRegion: LoopRegion?
    @State private var isLoopEnabled: Bool = true
    @State private var isTargeted = false
```

- [ ] **Step 2: Delete `handleLoopPoint`**

Remove lines 465-476 entirely from `ContentView.swift`:

```swift
    private func handleLoopPoint(_ time: Float) {
        if let start = pendingLoopStart {
            let loopStart = min(start, time)
            let loopEnd = max(start, time)
            guard loopEnd - loopStart > 0.1 else { return } // minimum loop length
            pendingLoopStart = nil
            isSettingLoop = false
            loopRegion = LoopRegion(startTime: loopStart, endTime: loopEnd)
        } else {
            pendingLoopStart = time
        }
    }
```

- [ ] **Step 3: Remove `isSettingLoop`/`pendingLoopStart`/`onLoopPointSet` from `WaveformView` call site**

In `ContentView.swift` around lines 244-247, remove three arguments from the `WaveformView(...)` call. Replace:

```swift
                    loopRegion: loopRegion,
                    isSettingLoop: isSettingLoop,
                    pendingLoopStart: pendingLoopStart,
                    onSeek: { time in audioEngine.seek(to: time) },
                    onLoopPointSet: { time in handleLoopPoint(time) },
                    onLoopRegionSet: { region in
                        loopRegion = region
                        isLoopEnabled = true
                    },
```

with:

```swift
                    loopRegion: loopRegion,
                    onSeek: { time in audioEngine.seek(to: time) },
                    onLoopRegionSet: { region in
                        loopRegion = region
                        isLoopEnabled = true
                    },
```

- [ ] **Step 4: Update Esc keyboard handler**

In `handleKeyEvent` (around line 558-563), replace:

```swift
        case 53: // Escape
            loopRegion = nil
            selectedSectionId = nil
            pendingLoopStart = nil
            isSettingLoop = false
            return true
```

with:

```swift
        case 53: // Escape
            loopRegion = nil
            selectedSectionId = nil
            return true
```

(The `L` key handler at case 37 already just clears `loopRegion`; it stays as-is.)

- [ ] **Step 5: Remove the three props from `WaveformView`**

In `WaveformView.swift` around lines 14-18, replace:

```swift
    let loopRegion: LoopRegion?
    let isSettingLoop: Bool
    let pendingLoopStart: Float?
    let onSeek: (Float) -> Void
    let onLoopPointSet: (Float) -> Void
    let onLoopRegionSet: (LoopRegion) -> Void
```

with:

```swift
    let loopRegion: LoopRegion?
    let onSeek: (Float) -> Void
    let onLoopRegionSet: (LoopRegion) -> Void
```

- [ ] **Step 6: Remove the `pendingLoopMarker` rendering**

In `WaveformView.swift` around lines 136-139, delete:

```swift
                        if let start = pendingLoopStart {
                            pendingLoopMarker(start: start, width: totalWidth, height: waveHeight)
                                .offset(x: waveformDragOffset)
                        }
```

- [ ] **Step 7: Simplify the tap-gesture to remove the `isSettingLoop` branch**

In `WaveformView.swift` around lines 251-265, replace:

```swift
                    .onTapGesture { location in
                        let fraction = Float(location.x / totalWidth)
                        let time = fraction * duration
                        if isSettingLoop {
                            // Snap loop endpoints to the visible bar grid (the
                            // same grid the user sees), nearest boundary. Beat
                            // snap landed mid-bar; floor/ceil jumped a full bar
                            // ahead/behind the clicked one.
                            let snapped = snapToGrid ? nearestGridTime(to: time) : time
                            onLoopPointSet(snapped)
                        } else {
                            let snapped = snapToGrid ? nearestBeatTime(to: time) : time
                            onSeek(snapped)
                        }
                    }
```

with:

```swift
                    .onTapGesture { location in
                        let fraction = Float(location.x / totalWidth)
                        let time = fraction * duration
                        let snapped = snapToGrid ? nearestBeatTime(to: time) : time
                        onSeek(snapped)
                    }
```

- [ ] **Step 8: Remove the orange `isSettingLoop` border overlay**

In `WaveformView.swift` around lines 340-346, delete:

```swift
        .overlay {
            if isSettingLoop {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.orange, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
```

- [ ] **Step 9: Delete the `pendingLoopMarker` helper function**

Delete the function at `WaveformView.swift:681-698`:

```swift
    private func pendingLoopMarker(start: Float, width: CGFloat, height: CGFloat) -> some View {
        let x = duration > 0 ? CGFloat(start / duration) * width : 0
        // Anchor on the 2px line; overlay the "A" label so the line stays
        // pixel-aligned with `x`. A wrapping VStack would center the line
        // inside the wider text frame and shift it a few px off-grid.
        return Rectangle()
            .fill(.orange)
            .frame(width: 2, height: height)
            .overlay(alignment: .top) {
                Text("A")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                    .fixedSize()
                    .offset(y: -12)
            }
            .offset(x: x)
            .allowsHitTesting(false)
    }
```

- [ ] **Step 10: Build**

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`. Compiler will catch any references to removed symbols. If the build fails, fix the referenced site by deleting that usage (do not reintroduce the symbol).

- [ ] **Step 11: Run tests**

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test
```

Expected: all tests pass. `LoopRegionTests` is unaffected; the other suites do not exercise `isSettingLoop`.

- [ ] **Step 12: Commit**

```bash
git add ThePlayer/Views/ContentView.swift ThePlayer/Views/WaveformView.swift
git commit -m "refactor(loop): remove two-click flow now superseded by shift+drag"
```

---

## Task 5: End-to-end manual verification

**Files:** none (verification only)

- [ ] **Step 1: Launch the app and load a song with sections**

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build
open build/Debug/ThePlayer.app 2>/dev/null || true
```

(Or run from Xcode.)

- [ ] **Step 2: Walk the verification checklist**

Confirm each:

1. **Shift+drag creates loop, auto-enables toggle**
   - Shift+drag from bar 2 to bar 5. Region appears spanning bars 2-5 (Snap on). Loop button turns blue. Audio loops the region.
2. **Shift+drag replaces existing loop**
   - Shift+drag a different region. Old region is replaced; new region loops; toggle stays on.
3. **Loop toggle disables looping but keeps region drawn**
   - Click Loop button while looping. Button turns muted (secondary). Playhead plays through the region without wrapping. Region overlay still visible.
4. **Loop toggle re-enables**
   - Click again. Button turns blue. Playback re-loops on next pass.
5. **Empty-region click shows hint**
   - Clear loop (Esc), then click Loop button. Popover hint "Shift+drag the waveform to set a loop" appears for ~2s.
6. **Section-click respects toggle (Q5 = B)**
   - With toggle OFF, click a section. Region updates to section bounds, but audio plays through (no loop).
   - Click toggle ON. Audio now loops the section.
7. **Esc clears region**
   - Press Esc. Region overlay disappears. Toggle stays in its current on/off state (no effect with no region).
8. **L key clears region** (existing behavior preserved)
9. **Sub-bar shift+drag does nothing**
   - Tiny shift+drag (under 8px). No region created.
10. **Existing option+drag for sections still works**
    - Option+drag creates a section as before. No interference from shift gesture.
11. **Existing command+drag (align downbeat) still works**
12. **Persisted loop on song reload**
    - Set a loop, switch songs, switch back. Loop is restored. Toggle is on (default).

- [ ] **Step 3: If everything passes, no commit needed (no code changes in this task)**

If any check fails, return to the relevant task and fix.

---

## Self-Review (against spec)

| Spec section | Where covered |
|---|---|
| Remove A-B button + orange mode | Task 3 (replace button), Task 4 (remove `isSettingLoop` border, two-click flow) |
| Shift+drag creates loop | Task 2 |
| Live preview while dragging | Task 2 step 2 |
| Floor/ceil to bars snap | Task 2 step 3 (`gridFloor` / `gridCeil`) |
| Min length > 0.1s | Task 2 step 3 (`guard snappedHi - snappedLo > 0.1`) |
| Shift+drag replaces existing | Task 2 step 4 (callback unconditionally assigns `loopRegion = region`) |
| Auto-enable toggle on creation | Task 2 step 4 (`isLoopEnabled = true`) |
| Loop toggle button (on/off, accent vs muted) | Task 3 step 3 |
| Empty-region click hint | Task 3 steps 2-4 |
| Section-click respects toggle | Task 1 step 2 (gate `setLoop` by `isLoopEnabled`); section-click code in `ContentView` already only mutates `loopRegion`, never `isLoopEnabled` |
| No explicit clear; replace + toggle-off; clear on song change | Task 4 (no clear UI added); existing `loadSong`/`openFile` already clears `loopRegion` |
| Persistence: lastLoopStart/End unchanged | No change to `saveCurrentPracticeState` (lines 444-456) — still works off `loopRegion` |
| Toggle state per-session, not persisted | Default `true` via `@State`, never written to library — Task 1 step 1 |

No placeholders, no TBDs. Type names checked: `isLoopEnabled` used consistently, `onLoopRegionSet` callback name used consistently, `LoopRegion(startTime:endTime:)` initializer matches the model.
