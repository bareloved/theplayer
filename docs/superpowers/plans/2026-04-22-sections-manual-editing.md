# Manual Section Editing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the analyzer-produced sections with ambient, modifier-gated manual editing (Option+drag to create, click label badge to select+loop), and collapse the old editor-mode UI.

**Architecture:** Sections remain a full `[0, duration]` partition driven by a single `SectionsViewModel`. The analyzer no longer produces sections; `TrackAnalysis.sections` is always empty. `UserEdits.sections` is the sole persisted source; when empty, the UI synthesizes a default "Untitled" section. All editing is gesture-driven on the waveform surface.

**Tech Stack:** Swift / SwiftUI / AppKit (macOS). XCTest.

**Spec:** `docs/superpowers/specs/2026-04-22-sections-manual-editing-design.md`

---

## File Map

**Modify:**
- `ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift` — add `createSection`, remove `reorder`, rename type + file to `SectionsViewModel`.
- `ThePlayer/Analysis/AnalysisService.swift` — strip section production in `EssentiaAnalyzerSwift`; always use `edits.sections` (never `analysis.sections`) in `mergeCachedAnalysis`.
- `ThePlayer/Analysis/MockAnalyzer.swift` — empty section output.
- `ThePlayer/Views/WaveformView.swift` — Option+drag gesture (create), boundary handles always visible, label badges rendered, section select via badge, context menu on band.
- `ThePlayer/Views/ContentView.swift` — always own `SectionsViewModel`; synthesize default Untitled when edits empty; remove editor-mode toggle wiring; wire loop lifecycle; keyboard handlers.
- `ThePlayer/Views/TransportBar.swift` — remove `onToggleSectionEditor` / `isSectionEditing` props and the button that uses them.
- `ThePlayer/Views/SidebarView.swift` — consume the live VM partition instead of `analysis.sections` (if it currently reads from analysis).
- `ThePlayerTests/SectionEditorViewModelTests.swift` — add `createSection` cases, drop `reorder` tests.
- `ThePlayerTests/AnalysisServiceMergeTests.swift` — rewrite section-merge cases for empty analyzer sections.

**Create:**
- `ThePlayer/Views/SectionEditor/SectionLabelBadge.swift` — pill UI + hit handling.

**Delete:**
- `ThePlayer/Views/SectionEditor/SectionEditorToolbar.swift`
- `ThePlayer/Views/SectionEditor/SectionInspector.swift`

---

## Task 1: Add `createSection` with tests

**Files:**
- Modify: `ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift`
- Modify: `ThePlayerTests/SectionEditorViewModelTests.swift`

- [ ] **Step 1: Add first failing test — range inside one section produces 3-way split**

In `SectionEditorViewModelTests.swift`, append:

```swift
func testCreateSectionInsideOneProducesThreeWaySplit() {
    let vm = makeVM()
    // Verse is 10..30. Create inside: [15, 25]
    let newId = vm.createSection(startTime: 15, endTime: 25, snapToBeat: false)
    XCTAssertNotNil(newId)
    XCTAssertEqual(vm.sections.count, 5)
    XCTAssertEqual(vm.sections[0].label, "Intro")     // 0..10
    XCTAssertEqual(vm.sections[1].startTime, 10)      // Verse-before 10..15
    XCTAssertEqual(vm.sections[1].endTime, 15)
    XCTAssertEqual(vm.sections[2].startTime, 15)      // new 15..25
    XCTAssertEqual(vm.sections[2].endTime, 25)
    XCTAssertEqual(vm.sections[2].label, "")
    XCTAssertEqual(vm.sections[3].startTime, 25)      // Verse-after 25..30
    XCTAssertEqual(vm.sections[3].endTime, 30)
    XCTAssertEqual(vm.sections[4].label, "Chorus")    // 30..50
}
```

- [ ] **Step 2: Run the test — expect compile failure (`createSection` not defined)**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/SectionEditorViewModelTests/testCreateSectionInsideOneProducesThreeWaySplit 2>&1 | tail -30`

Expected: build failure, "value of type 'SectionEditorViewModel' has no member 'createSection'".

- [ ] **Step 3: Add `createSection` implementation in the VM**

In `SectionEditorViewModel.swift`, add these two methods inside the class (after `replaceAll`):

```swift
// MARK: - Creation

@discardableResult
func createSection(startTime requestedStart: Float, endTime requestedEnd: Float, snapToBeat: Bool) -> UUID? {
    var s = min(requestedStart, requestedEnd)
    var e = max(requestedStart, requestedEnd)
    s = max(0, min(duration, s))
    e = max(0, min(duration, e))
    if snapToBeat {
        s = Self.snapToNearestBeat(time: s, beats: beats)
        e = Self.snapToNearestBeat(time: e, beats: beats)
    }
    let minLen: Float = beats.count >= 2 ? Float(beats[1] - beats[0]) : 0.5
    guard e - s >= minLen else { return nil }

    let prev = sections
    let colorIndex = nextColorIndex(avoidingNeighborsOf: s, in: prev)
    let newSection = AudioSection(
        label: "",
        startTime: s,
        endTime: e,
        startBeat: 0,
        endBeat: 0,
        colorIndex: colorIndex
    )
    let newId = newSection.stableId

    applyChange(undoLabel: "Add Section") {
        self.sections = Self.rebuildPartition(inserting: newSection, into: prev, minLen: minLen)
        self.recomputeBeatsForRange(0 ... self.sections.count - 1)
    } undo: {
        self.sections = prev
    }
    return newId
}

private static func rebuildPartition(
    inserting new: AudioSection,
    into existing: [AudioSection],
    minLen: Float
) -> [AudioSection] {
    var result: [AudioSection] = []
    var inserted = false
    let s = new.startTime
    let e = new.endTime
    for section in existing {
        let fullyEngulfed = section.startTime >= s && section.endTime <= e
        let partialLeft  = section.startTime < s && section.endTime > s && section.endTime <= e
        let partialRight = section.startTime >= s && section.startTime < e && section.endTime > e
        let contains     = section.startTime < s && section.endTime > e

        if fullyEngulfed {
            continue
        } else if partialLeft {
            var trimmed = section
            trimmed.endTime = s
            if trimmed.endTime - trimmed.startTime >= minLen { result.append(trimmed) }
        } else if partialRight {
            var trimmed = section
            trimmed.startTime = e
            if trimmed.endTime - trimmed.startTime >= minLen { result.append(trimmed) }
        } else if contains {
            var before = section
            before.endTime = s
            var after = section
            after.stableId = UUID() // keep `before` stable; give `after` a new id
            after.startTime = e
            // Extend `new` into pieces too short to stand on their own.
            var effectiveNew = new
            if before.endTime - before.startTime >= minLen { result.append(before) }
            else { effectiveNew.startTime = before.startTime }
            result.append(effectiveNew)
            inserted = true
            if after.endTime - after.startTime >= minLen { result.append(after) }
            else { result[result.count - 1].endTime = after.endTime }
            continue
        } else {
            result.append(section)
        }

        if !inserted && section.endTime <= s {
            // defer; not our turn
        }
    }
    if !inserted {
        // Find insertion point by startTime.
        let insertIdx = result.firstIndex(where: { $0.startTime >= e }) ?? result.count
        result.insert(new, at: insertIdx)
    }
    return result
}

private func nextColorIndex(avoidingNeighborsOf s: Float, in existing: [AudioSection]) -> Int {
    let paletteSize = 8
    let usedByNeighbors = Set(existing
        .filter { abs($0.endTime - s) < 0.001 || abs($0.startTime - s) < 0.001 }
        .map { $0.colorIndex })
    for offset in 0..<paletteSize {
        let idx = (existing.count + offset) % paletteSize
        if !usedByNeighbors.contains(idx) { return idx }
    }
    return 0
}
```

Also, since `AudioSection.stableId` is currently `let`, change it to `var` so the splits above can assign a fresh UUID to the right half:

Open `ThePlayer/Models/AudioSection.swift`, change:

```swift
let stableId: UUID
```

to:

```swift
var stableId: UUID
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/SectionEditorViewModelTests/testCreateSectionInsideOneProducesThreeWaySplit 2>&1 | tail -20`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Add coverage tests for all overlap cases**

Append to `SectionEditorViewModelTests.swift`:

```swift
func testCreateSectionPartialLeftOverlapTrimsExisting() {
    let vm = makeVM()
    // Intro 0..10, Verse 10..30. Create 5..15 → trims Intro to 0..5, engulfs nothing, trims Verse's left to 15..30.
    vm.createSection(startTime: 5, endTime: 15, snapToBeat: false)
    XCTAssertEqual(vm.sections.count, 4)
    XCTAssertEqual(vm.sections[0].endTime, 5)
    XCTAssertEqual(vm.sections[1].startTime, 5)
    XCTAssertEqual(vm.sections[1].endTime, 15)
    XCTAssertEqual(vm.sections[2].startTime, 15)
}

func testCreateSectionSpanningMultipleEngulfsMiddle() {
    let vm = makeVM()
    // Intro 0..10, Verse 10..30, Chorus 30..50. Create 5..35.
    vm.createSection(startTime: 5, endTime: 35, snapToBeat: false)
    XCTAssertEqual(vm.sections.count, 3)
    XCTAssertEqual(vm.sections[0].endTime, 5)      // Intro 0..5
    XCTAssertEqual(vm.sections[1].startTime, 5)    // new 5..35
    XCTAssertEqual(vm.sections[1].endTime, 35)
    XCTAssertEqual(vm.sections[2].startTime, 35)   // Chorus 35..50
}

func testCreateSectionDegenerateRangeReturnsNil() {
    let vm = makeVM()
    XCTAssertNil(vm.createSection(startTime: 20, endTime: 20, snapToBeat: false))
    XCTAssertEqual(vm.sections.count, 3)
}

func testCreateSectionSnapsEndpointsToBeats() {
    let vm = makeVM()
    // Beats are at 0.0, 0.5, 1.0 ... Request 14.2..25.8, expect 14.0..26.0 (nearest beats).
    vm.createSection(startTime: 14.2, endTime: 25.8, snapToBeat: true)
    XCTAssertEqual(vm.sections[1].endTime, 14.0)
    XCTAssertEqual(vm.sections[2].startTime, 14.0)
    XCTAssertEqual(vm.sections[2].endTime, 26.0)
    XCTAssertEqual(vm.sections[3].startTime, 26.0)
}

func testCreateSectionSwapsReversedInput() {
    let vm = makeVM()
    vm.createSection(startTime: 25, endTime: 15, snapToBeat: false)
    XCTAssertEqual(vm.sections[2].startTime, 15)
    XCTAssertEqual(vm.sections[2].endTime, 25)
}

func testCreateSectionUndoRestoresPartition() {
    let vm = makeVM()
    let before = vm.sections
    vm.createSection(startTime: 15, endTime: 25, snapToBeat: false)
    vm.undoManager.undo()
    XCTAssertEqual(vm.sections.count, before.count)
    XCTAssertEqual(vm.sections[0].stableId, before[0].stableId)
    XCTAssertEqual(vm.sections[1].stableId, before[1].stableId)
    XCTAssertEqual(vm.sections[2].stableId, before[2].stableId)
}
```

- [ ] **Step 6: Run all VM tests — expect all PASS**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/SectionEditorViewModelTests 2>&1 | tail -20`

Expected: all existing + new tests pass.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift \
        ThePlayer/Models/AudioSection.swift \
        ThePlayerTests/SectionEditorViewModelTests.swift
git commit -m "feat(sections): add createSection with carve-out overlap semantics"
```

---

## Task 2: Remove `reorder`

**Files:**
- Modify: `ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift`
- Modify: `ThePlayerTests/SectionEditorViewModelTests.swift`

- [ ] **Step 1: Delete `reorder(sectionId:direction:)` and the `ReorderDirection` enum**

In `SectionEditorViewModel.swift`, remove:

```swift
enum ReorderDirection { case left, right }
```
and the entire `func reorder(sectionId:direction:)` block.

- [ ] **Step 2: Remove reorder tests from `SectionEditorViewModelTests.swift`**

Delete any test methods referencing `vm.reorder(...)`.

- [ ] **Step 3: Run tests — expect PASS**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/SectionEditorViewModelTests 2>&1 | tail -20`

Expected: all tests pass; build green.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift \
        ThePlayerTests/SectionEditorViewModelTests.swift
git commit -m "refactor(sections): drop reorder mutation"
```

---

## Task 3: Rename `SectionEditorViewModel` → `SectionsViewModel`

**Files:**
- Rename: `ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift` → `ThePlayer/Views/SectionEditor/SectionsViewModel.swift`
- Modify: every call site referencing the type.

- [ ] **Step 1: Rename the file and the type**

```bash
git mv ThePlayer/Views/SectionEditor/SectionEditorViewModel.swift \
       ThePlayer/Views/SectionEditor/SectionsViewModel.swift
```

In the moved file, change the class name:

```swift
final class SectionEditorViewModel {
```
to:

```swift
final class SectionsViewModel {
```

- [ ] **Step 2: Update all references with a single find-and-replace**

Run to list call sites:
```bash
grep -rn "SectionEditorViewModel" ThePlayer ThePlayerTests
```

Expected sites (update each occurrence to `SectionsViewModel`):
- `ThePlayer/Views/WaveformView.swift` (property + function parameter)
- `ThePlayer/Views/ContentView.swift` (State property + constructor + helpers)
- `ThePlayer/Views/SectionEditor/SectionEditorToolbar.swift` (bindable param — will be deleted later but update for now)
- `ThePlayer/Views/SectionEditor/SectionInspector.swift` (bindable param — will be deleted later)
- `ThePlayerTests/SectionEditorViewModelTests.swift` (test class-internal references)

Update each.

- [ ] **Step 3: Build and run all tests — expect PASS**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test 2>&1 | tail -20`

Expected: build succeeds, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(sections): rename SectionEditorViewModel to SectionsViewModel"
```

---

## Task 4: Strip analyzer section production

**Files:**
- Modify: `ThePlayer/Analysis/AnalysisService.swift`
- Modify: `ThePlayer/Analysis/MockAnalyzer.swift`

- [ ] **Step 1: Empty out sections in `EssentiaAnalyzerSwift`**

In `AnalysisService.swift`, replace the `let sections = result.sections.enumerated().map ...` block with:

```swift
let sections: [AudioSection] = []
```

(Leave the rest of `analyze` intact: beats, peaks, onsets, bpm, downbeatOffset all still produced.)

- [ ] **Step 2: Empty out sections in `MockAnalyzer.swift`**

Replace the `sections: [ ... ]` array literal in the returned `TrackAnalysis` with:

```swift
sections: [],
```

- [ ] **Step 3: Build — expect SUCCESS**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -10`

Expected: build succeeds.

- [ ] **Step 4: Run `AnalysisServiceMergeTests` — expect FAILURES**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/AnalysisServiceMergeTests 2>&1 | tail -30`

Expected: the section-merge tests that expected analyzer sections to flow through will now fail. Note which ones.

- [ ] **Step 5: Rewrite `AnalysisServiceMergeTests` section-merge cases**

Open `ThePlayerTests/AnalysisServiceMergeTests.swift`. For every test that asserts `mergedAnalysis.sections` contains analyzer sections when user edits are empty, change the assertion to `XCTAssertTrue(merged.sections.isEmpty)`. For tests that assert user-edit sections win, keep them.

Concrete rule to apply inline: wherever a test passes an analysis containing sections plus `UserEdits(sections: [])` and expected the analyzer's sections, change the expected section-count to 0.

- [ ] **Step 6: Run tests — expect PASS**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/AnalysisServiceMergeTests 2>&1 | tail -20`

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Analysis/AnalysisService.swift \
        ThePlayer/Analysis/MockAnalyzer.swift \
        ThePlayerTests/AnalysisServiceMergeTests.swift
git commit -m "refactor(analyzer): stop producing auto-sections"
```

---

## Task 5: `mergeCachedAnalysis` stops reading `analysis.sections`

**Files:**
- Modify: `ThePlayer/Analysis/AnalysisService.swift`
- Modify: `ThePlayerTests/AnalysisServiceMergeTests.swift`

- [ ] **Step 1: Update `mergeCachedAnalysis` to ignore analyzer sections entirely**

Change the line:

```swift
let mergedSections = edits.sections.isEmpty ? analysis.sections : edits.sections
```

to:

```swift
// Analyzer sections are never consulted; user edits are the only source.
let mergedSections = edits.sections
```

- [ ] **Step 2: Add a regression test**

Append to `AnalysisServiceMergeTests.swift`:

```swift
func testMergeIgnoresAnalyzerSectionsEvenWhenUserEditsEmpty() {
    let base = TrackAnalysis(
        bpm: 120,
        beats: [],
        sections: [
            AudioSection(label: "Stale", startTime: 0, endTime: 30, startBeat: 0, endBeat: 60, colorIndex: 0)
        ],
        waveformPeaks: [],
        onsets: []
    )
    let merged = AnalysisService.mergeCachedAnalysis(base, userEdits: UserEdits(sections: []))
    XCTAssertTrue(merged.sections.isEmpty)
}
```

- [ ] **Step 3: Run tests — expect PASS**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test -only-testing:ThePlayerTests/AnalysisServiceMergeTests 2>&1 | tail -20`

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Analysis/AnalysisService.swift \
        ThePlayerTests/AnalysisServiceMergeTests.swift
git commit -m "refactor(analyzer): mergeCachedAnalysis ignores analyzer sections"
```

---

## Task 6: ContentView always owns a `SectionsViewModel`; synthesize default Untitled

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Replace the optional `sectionEditor` state with an always-on VM tied to track load**

In `ContentView.swift`:

Replace:
```swift
@State private var sectionEditor: SectionEditorViewModel?
@State private var selectedSectionForEdit: UUID?
@State private var showResetConfirm = false
```

with:

```swift
@State private var sectionsVM: SectionsViewModel?
@State private var selectedSectionId: UUID?
```

- [ ] **Step 2: Add a factory that builds the VM with a synthesized Untitled when edits empty**

Add a private helper inside `ContentView`:

```swift
private func buildSectionsVM(from analysis: TrackAnalysis) -> SectionsViewModel {
    let persisted = analysis.sections
    let seed: [AudioSection]
    if persisted.isEmpty {
        seed = [AudioSection(
            label: "Untitled",
            startTime: 0,
            endTime: Float(audioEngine.duration),
            startBeat: 0,
            endBeat: max(0, analysis.beats.count - 1),
            colorIndex: 0
        )]
    } else {
        seed = persisted
    }
    let vm = SectionsViewModel(
        sections: seed,
        beats: analysis.beats,
        duration: Float(audioEngine.duration)
    )
    vm.onChange = { [weak analysisService] sections in
        // Never persist the synthetic single-Untitled default; only real edits.
        let isDefault = sections.count == 1 && sections[0].label == "Untitled"
        if isDefault {
            // No-op: keep sidecar empty until the user actually edits.
            return
        }
        try? analysisService?.saveUserEdits(sections)
    }
    return vm
}
```

- [ ] **Step 3: Rebuild the VM whenever a new analysis is available**

In `ContentView.body`, add at an appropriate modifier position (alongside existing `.onChange` handlers):

```swift
.onChange(of: analysisService.lastAnalysis?.beats.count) { _, _ in
    if let analysis = analysisService.lastAnalysis {
        sectionsVM = buildSectionsVM(from: analysis)
        selectedSectionId = nil
    }
}
```

And ensure `sectionsVM` is built at least once on initial analysis arrival (the `onChange` above fires on non-nil transitions).

- [ ] **Step 4: Remove the `enterSectionEditor`/`exitSectionEditor` helpers**

Delete both functions. Remove any call sites (the transport toggle and the `exitSectionEditor` path inside Reset's confirmation dialog).

- [ ] **Step 5: Update the waveform parameter passing**

In `WaveformView(...)` call inside `ContentView`, replace:

```swift
editorViewModel: sectionEditor,
selectedSectionId: selectedSectionForEdit,
onSelectSection: { selectedSectionForEdit = $0 }
```

with:

```swift
sectionsVM: sectionsVM,
selectedSectionId: selectedSectionId,
onSelectSection: { selectedSectionId = $0 }
```

(We'll update the matching parameter names inside `WaveformView` in Task 8.)

Also replace the `sections:` argument:

```swift
sections: analysisService.lastAnalysis?.sections ?? [],
```
with:
```swift
sections: sectionsVM?.sections ?? [],
```

- [ ] **Step 6: Update the sidebar to read from the VM, not the analysis**

In the same file where `SidebarView(sections: analysisService.lastAnalysis?.sections ?? [], ...)` is constructed, replace with:

```swift
sections: sectionsVM?.sections ?? [],
```

- [ ] **Step 7: Build — expect build failures (editor-mode wiring still present elsewhere)**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -30`

Expected failures in `TransportBar`, the `if let vm = sectionEditor` ZStack block, and the Reset confirmation dialog. We'll fix those in Task 7.

- [ ] **Step 8: Commit (partial)**

```bash
git add ThePlayer/Views/ContentView.swift
git commit -m "wip(sections): ContentView owns SectionsViewModel, synthesizes Untitled default"
```

---

## Task 7: Remove editor-mode UI (toolbar, inspector, reset, transport toggle)

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`
- Modify: `ThePlayer/Views/TransportBar.swift`
- Delete: `ThePlayer/Views/SectionEditor/SectionEditorToolbar.swift`
- Delete: `ThePlayer/Views/SectionEditor/SectionInspector.swift`

- [ ] **Step 1: Remove the `if let vm = sectionEditor { ... }` overlay block in `ContentView`**

Delete the entire `if let vm = sectionEditor { VStack { SectionEditorToolbar(...) ; SectionInspector(...) } ... }` block from `ContentView.body`.

- [ ] **Step 2: Remove the Reset confirmation dialog**

Delete the `.confirmationDialog("Reset all section edits?", ...)` modifier and its body.

- [ ] **Step 3: Remove editor-toggle props from `TransportBar`**

In `TransportBar.swift`, delete:

```swift
let onToggleSectionEditor: () -> Void
let isSectionEditing: Bool
```

and the `Button(action: onToggleSectionEditor) { ... }` that uses them.

- [ ] **Step 4: Remove the matching arguments from the `TransportBar(...)` call in `ContentView`**

Delete the `onToggleSectionEditor: ...` and `isSectionEditing: ...` arguments.

- [ ] **Step 5: Delete the now-unused view files**

```bash
git rm ThePlayer/Views/SectionEditor/SectionEditorToolbar.swift
git rm ThePlayer/Views/SectionEditor/SectionInspector.swift
```

- [ ] **Step 6: Build and test — expect SUCCESS**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test 2>&1 | tail -30`

Expected: build succeeds, tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(sections): drop editor mode, inspector, toolbar, reset"
```

---

## Task 8: Option+drag gesture in `WaveformView`

**Files:**
- Modify: `ThePlayer/Views/WaveformView.swift`

- [ ] **Step 1: Rename params and always show boundary handles**

In `WaveformView.swift`, replace:

```swift
let editorViewModel: SectionEditorViewModel?
let selectedSectionId: UUID?
let onSelectSection: ((UUID?) -> Void)?
```

with:

```swift
let sectionsVM: SectionsViewModel?
let selectedSectionId: UUID?
let onSelectSection: ((UUID?) -> Void)?
```

Update references to `editorViewModel` → `sectionsVM` inside the view body (notably the `if let vm = editorViewModel` in the boundary-handles overlay — change to `if let vm = sectionsVM`).

- [ ] **Step 2: Add gesture state for Option+drag**

Add near the other `@State` properties:

```swift
@State private var sectionDragActive: Bool = false
@State private var sectionDragStartTime: Float?
@State private var sectionDragCurrentTime: Float?
@State private var pendingSectionRenameId: UUID?
```

- [ ] **Step 3: Add the Option+drag gesture alongside the existing Cmd-drag gesture**

Locate the existing `.gesture(DragGesture(minimumDistance: 2, coordinateSpace: .local).onChanged { value in ... })`. Add a simultaneous second gesture using `.simultaneousGesture`:

```swift
.simultaneousGesture(
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { value in
            guard totalWidth > 0, duration > 0, let vm = sectionsVM else { return }
            if !sectionDragActive {
                guard NSEvent.modifierFlags.contains(.option) else { return }
                sectionDragActive = true
                sectionDragStartTime = Float(value.startLocation.x / totalWidth) * duration
                NSCursor.crosshair.set()
            }
            sectionDragCurrentTime = Float(value.location.x / totalWidth) * duration
            _ = vm // silence unused warning until commit
        }
        .onEnded { value in
            defer {
                sectionDragActive = false
                sectionDragStartTime = nil
                sectionDragCurrentTime = nil
                NSCursor.arrow.set()
            }
            guard sectionDragActive,
                  let vm = sectionsVM,
                  let startT = sectionDragStartTime else { return }
            let dx = value.location.x - value.startLocation.x
            guard abs(dx) >= 8 else { return } // min drag distance
            let endT = Float(value.location.x / totalWidth) * duration
            if let newId = vm.createSection(
                startTime: startT,
                endTime: endT,
                snapToBeat: snapToGrid
            ) {
                onSelectSection?(newId)
                pendingSectionRenameId = newId
            }
        }
)
```

- [ ] **Step 4: Render the in-flight preview band**

Inside the `ZStack(alignment: .leading) { ... }` where `sectionBands` is rendered, add after `sectionBands` and before `waveformBars`:

```swift
if sectionDragActive,
   let s = sectionDragStartTime,
   let e = sectionDragCurrentTime {
    let lo = min(s, e)
    let hi = max(s, e)
    let snappedLo: Float = snapToGrid ? SectionsViewModel.snapToNearestBeat(time: lo, beats: beats) : lo
    let snappedHi: Float = snapToGrid ? SectionsViewModel.snapToNearestBeat(time: hi, beats: beats) : hi
    let leftX = CGFloat(snappedLo / duration) * totalWidth
    let rightX = CGFloat(snappedHi / duration) * totalWidth
    let width = max(0, rightX - leftX)
    Rectangle()
        .fill(Color.accentColor.opacity(0.18))
        .overlay(
            Rectangle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .frame(width: width, height: waveHeight)
        .offset(x: leftX)
}
```

- [ ] **Step 5: Guard the Cmd-drag gesture against firing simultaneously**

In the existing Cmd-drag `onChanged` handler (the one that activates `alignDragActive`), add an early bail:

```swift
guard !sectionDragActive else { return }
```

right after the `guard totalWidth > 0, duration > 0 else { return }`.

- [ ] **Step 6: Build and launch — manually verify Option+drag creates a section**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -10`

Then launch the app (`open` the built .app or run from Xcode) and test:
- Load a track.
- Option+drag across the waveform — a dashed preview appears, releases into a new colored band.
- Plain drag does nothing.
- Cmd+drag still aligns downbeat (regression check).
- Release with < 8 px travel — nothing created.
- With snap on: endpoints snap; snap off: exact.

- [ ] **Step 7: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift
git commit -m "feat(sections): option+drag on waveform creates a section"
```

---

## Task 9: `SectionLabelBadge` view + click/double-click/right-click

**Files:**
- Create: `ThePlayer/Views/SectionEditor/SectionLabelBadge.swift`
- Modify: `ThePlayer/Views/WaveformView.swift`

- [ ] **Step 1: Create the badge view**

Create `ThePlayer/Views/SectionEditor/SectionLabelBadge.swift`:

```swift
import SwiftUI

struct SectionLabelBadge: View {
    let label: String
    let color: Color
    let isSelected: Bool
    @Binding var isRenaming: Bool
    let onCommitRename: (String) -> Void
    let onTap: () -> Void
    let onContextMenu: () -> AnyView

    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                TextField("Label", text: $draft, onCommit: {
                    onCommitRename(draft)
                    isRenaming = false
                })
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .frame(minWidth: 60, maxWidth: 140)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.6), in: Capsule())
                .foregroundStyle(textColor)
                .onAppear {
                    draft = label
                    DispatchQueue.main.async { fieldFocused = true }
                }
                .onExitCommand { isRenaming = false }
            } else {
                Text(label.isEmpty ? "Untitled" : label)
                    .font(.caption).bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.6), in: Capsule())
                    .foregroundStyle(textColor)
                    .overlay(
                        Capsule().strokeBorder(color, lineWidth: isSelected ? 2 : 0)
                    )
                    .onTapGesture(count: 2) { isRenaming = true }
                    .onTapGesture(count: 1) { onTap() }
                    .contextMenu { onContextMenu() }
            }
        }
    }

    private var textColor: Color {
        // Cheap contrast: dark text on yellow/cyan, white otherwise.
        switch color {
        case .yellow, .cyan: return .black
        default:             return .white
        }
    }
}
```

- [ ] **Step 2: Expose a static color-for-index helper on `AudioSection` (needed by the badge context menu)**

In `AudioSection.swift`, replace the private palette with public access:

```swift
static let palette: [Color] = [
    .blue, .green, .red, .yellow, .purple, .orange, .cyan, .pink
]

static func color(forIndex idx: Int) -> Color {
    palette[idx % palette.count]
}
```

(Change `private static let palette` to `static let palette`.)

- [ ] **Step 3: Render a badge per section inside `sectionBands`**

In `WaveformView.swift`, replace the body of `sectionBands(width:height:)` with a version that overlays a badge at the band's top-left:

```swift
private func sectionBands(width: CGFloat, height: CGFloat) -> some View {
    ZStack(alignment: .leading) {
        ForEach(sections) { section in
            let sectionX = CGFloat(section.startTime / duration) * width
            let sectionWidth = CGFloat((section.endTime - section.startTime) / duration) * width
            let isSelected = section.stableId == selectedSectionId
            Rectangle()
                .fill(section.color.opacity(isSelected ? 0.25 : 0.1))
                .overlay(
                    Rectangle()
                        .strokeBorder(section.color, lineWidth: isSelected ? 2 : 0)
                )
                .frame(width: sectionWidth, height: height)
                .offset(x: sectionX)

            if sectionWidth >= 20 {
                SectionLabelBadge(
                    label: section.label,
                    color: section.color,
                    isSelected: isSelected,
                    isRenaming: Binding(
                        get: { pendingSectionRenameId == section.stableId },
                        set: { if !$0 { pendingSectionRenameId = nil } }
                    ),
                    onCommitRename: { newLabel in
                        sectionsVM?.rename(sectionId: section.stableId, to: newLabel)
                    },
                    onTap: { onSelectSection?(section.stableId) },
                    onContextMenu: {
                        AnyView(
                            Group {
                                Button("Rename") { pendingSectionRenameId = section.stableId }
                                Menu("Change Color") {
                                    ForEach(0..<8, id: \.self) { idx in
                                        Button(action: {
                                            sectionsVM?.recolor(sectionId: section.stableId, colorIndex: idx)
                                        }) {
                                            Text("•").foregroundColor(AudioSection.color(forIndex: idx))
                                        }
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    sectionsVM?.delete(sectionId: section.stableId)
                                    if selectedSectionId == section.stableId {
                                        onSelectSection?(nil)
                                    }
                                }
                            }
                        )
                    }
                )
                .padding(.leading, 4)
                .padding(.top, 3)
                .offset(x: sectionX, y: -height / 2 + 12)
            }
        }
    }
}
```

- [ ] **Step 4: Remove the `onTapGesture` that selected sections on band tap**

In `WaveformView.swift`, in the existing `.onTapGesture { location in ... }` handler, delete the block:

```swift
if let onSelectSection = onSelectSection, editorViewModel != nil {
    let hit = sections.first(where: { time >= $0.startTime && time < $0.endTime })
    onSelectSection(hit?.stableId)
    return
}
```

Selection now happens exclusively via the badge; a plain waveform tap always seeks.

- [ ] **Step 5: Build and launch — verify badges render, click selects, double-click renames, right-click menu works**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -10`

Manual checks:
- Each section has a pill at its top-left with its label.
- Click a pill → section becomes selected (outline).
- Double-click a pill → text field appears focused.
- Right-click → Rename / Change Color / Delete menu.
- Creating a section via Option+drag auto-opens the rename field on the new badge.

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Views/SectionEditor/SectionLabelBadge.swift \
        ThePlayer/Views/WaveformView.swift \
        ThePlayer/Models/AudioSection.swift
git commit -m "feat(sections): label badge with click/rename/context-menu"
```

---

## Task 10: Loop lifecycle — badge click toggles loop; boundary move updates loop; delete/deselect clears

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Turn badge-select into a toggle that drives `loopRegion`**

In `ContentView.swift`, replace the waveform's `onSelectSection` handler:

```swift
onSelectSection: { selectedSectionId = $0 }
```

with:

```swift
onSelectSection: { [weak audioEngine] newId in
    guard let vm = sectionsVM else { return }
    if let id = newId,
       let section = vm.sections.first(where: { $0.stableId == id }) {
        if selectedSectionId == id {
            // Toggle off
            selectedSectionId = nil
            loopRegion = nil
            audioEngine?.setLoop(nil)
        } else {
            selectedSectionId = id
            let loop = LoopRegion.from(section: section)
            loopRegion = loop
            audioEngine?.setLoop(loop)
        }
    } else {
        selectedSectionId = nil
        loopRegion = nil
        audioEngine?.setLoop(nil)
    }
}
```

- [ ] **Step 2: Update loop region when the selected section's bounds change**

Add an `.onChange` modifier on `sectionsVM?.sections` in `ContentView.body`:

```swift
.onChange(of: sectionsVM?.sections) { _, newSections in
    guard let id = selectedSectionId,
          let newSections,
          let section = newSections.first(where: { $0.stableId == id }) else {
        // Section no longer exists — clear loop & selection.
        if selectedSectionId != nil {
            selectedSectionId = nil
            loopRegion = nil
            audioEngine.setLoop(nil)
        }
        return
    }
    let loop = LoopRegion.from(section: section)
    if loopRegion != loop {
        loopRegion = loop
        audioEngine.setLoop(loop)
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -10`

Manual checks:
- Click a badge → loop arms over that section, playback loops.
- Click the same badge again → loop clears, selection clears.
- Drag a boundary of the selected section → loop endpoint updates live.
- Delete the selected section via context menu → loop clears.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/ContentView.swift
git commit -m "feat(sections): badge click toggles loop; loop follows section bounds"
```

---

## Task 11: Keyboard — ⌫ delete, Esc deselect, ⌘Z/⇧⌘Z undo/redo

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Extend the existing `keyMonitor` (NSEvent local key handler) to cover ⌫ and Esc when a section is selected**

Locate the existing `NSEvent.addLocalMonitorForEvents` block in `ContentView`. Add handlers for ⌫ (keyCode 51) and Esc (keyCode 53):

```swift
// inside the existing monitor closure, near other keyCode branches:
if let id = selectedSectionId, event.type == .keyDown {
    switch event.keyCode {
    case 51: // delete/backspace
        sectionsVM?.delete(sectionId: id)
        // onChange handler above will clear loop & selection when section disappears.
        return nil
    case 53: // escape
        selectedSectionId = nil
        loopRegion = nil
        audioEngine.setLoop(nil)
        return nil
    default: break
    }
}
```

If no `keyMonitor` exists yet for these events, add one in `.onAppear` and tear down in `.onDisappear`:

```swift
.onAppear {
    if keyMonitor == nil {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ... handler from above ...
            return event
        }
    }
}
.onDisappear {
    if let m = keyMonitor {
        NSEvent.removeMonitor(m)
        keyMonitor = nil
    }
}
```

- [ ] **Step 2: Route ⌘Z / ⇧⌘Z to the VM undoManager**

Add a commands modifier on the top-level app (or on `ContentView` if that's how the app is structured). Inspect `ThePlayerApp.swift` first:

```bash
grep -n "Scene\|WindowGroup\|commands" ThePlayer/ThePlayerApp.swift
```

On the `WindowGroup { ContentView(...) }`, chain:

```swift
.commands {
    CommandGroup(replacing: .undoRedo) {
        Button("Undo") {
            NotificationCenter.default.post(name: .sectionsUndoRequested, object: nil)
        }.keyboardShortcut("z", modifiers: .command)
        Button("Redo") {
            NotificationCenter.default.post(name: .sectionsRedoRequested, object: nil)
        }.keyboardShortcut("z", modifiers: [.command, .shift])
    }
}
```

And in `ContentView`, observe both notifications:

```swift
.onReceive(NotificationCenter.default.publisher(for: .sectionsUndoRequested)) { _ in
    sectionsVM?.undoManager.undo()
}
.onReceive(NotificationCenter.default.publisher(for: .sectionsRedoRequested)) { _ in
    sectionsVM?.undoManager.redo()
}
```

Add the notification names in a small extension (e.g., at the bottom of `ContentView.swift`):

```swift
extension Notification.Name {
    static let sectionsUndoRequested = Notification.Name("sectionsUndoRequested")
    static let sectionsRedoRequested = Notification.Name("sectionsRedoRequested")
}
```

- [ ] **Step 3: Build and verify manually**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -10`

Manual checks:
- Select a section via badge, press ⌫ → section deleted, loop cleared.
- Select, press Esc → selection and loop cleared.
- After Option+drag creates a section, press ⌘Z → section removed; ⇧⌘Z → re-added.

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/ContentView.swift ThePlayer/ThePlayerApp.swift
git commit -m "feat(sections): keyboard shortcuts (delete, esc, undo/redo)"
```

---

## Task 12: Final pass — verify spec coverage, run full test suite, remove dead code

**Files:**
- Review all modified files.

- [ ] **Step 1: Full test suite green**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' test 2>&1 | tail -20`

Expected: all tests pass.

- [ ] **Step 2: Spec coverage checklist (inspect, don't re-implement)**

For each spec row, confirm the corresponding behavior in code:
- Option+drag creates section → Task 8.
- Label-click toggles select+loop → Task 9 + 10.
- Double-click rename → Task 9.
- Context menu (Rename / Change color / Delete) → Task 9.
- Boundary handles always visible → Task 8 Step 1.
- ⌫ / Esc / ⌘Z / ⇧⌘Z → Task 11.
- Analyzer no longer produces sections → Task 4.
- `mergeCachedAnalysis` ignores analyzer sections → Task 5.
- Default Untitled synthesized when edits empty → Task 6.
- No editor mode / inspector / reset / toolbar → Task 7.
- Loop follows section bounds; cleared on delete/deselect → Task 10.

- [ ] **Step 3: Dead-code sweep**

```bash
grep -rn "SectionEditorToolbar\|SectionInspector\|sectionEditor\|enterSectionEditor\|exitSectionEditor\|selectedSectionForEdit\|showResetConfirm\|onToggleSectionEditor\|isSectionEditing\|ReorderDirection" ThePlayer ThePlayerTests
```

Expected: no matches (all references removed).

- [ ] **Step 4: Manual smoke test on a real track**

Launch app, load an existing song from the library:
- Section badges show one "Untitled" covering the full duration (for tracks with no prior edits).
- Option+drag creates sections, names prompt appears.
- Clicking a section badge starts a loop over that section.
- Pressing play → loops within the selected section.
- Everything undo-able with ⌘Z.

- [ ] **Step 5: Commit final cleanup if any tweaks**

```bash
git add -A && git diff --cached --quiet || git commit -m "chore(sections): final cleanup after manual verification"
```

---

## Done

Once all tasks pass, open a PR summary referencing the spec and listing the headline gestures:

- **Option+drag** on the waveform → create a section.
- **Click** a section's label badge → select + loop that section (click again to clear).
- **Double-click** → rename.
- **Right-click** → rename / change color / delete.
- **⌫** → delete selected. **Esc** → deselect. **⌘Z / ⇧⌘Z** → undo / redo.
