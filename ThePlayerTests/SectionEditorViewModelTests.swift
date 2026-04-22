import XCTest
@testable import ThePlayer

final class SectionEditorViewModelTests: XCTestCase {

    private func makeSections() -> [AudioSection] {
        [
            AudioSection(label: "Intro",  startTime: 0,  endTime: 10, startBeat: 0,  endBeat: 16, colorIndex: 0),
            AudioSection(label: "Verse",  startTime: 10, endTime: 30, startBeat: 16, endBeat: 48, colorIndex: 1),
            AudioSection(label: "Chorus", startTime: 30, endTime: 50, startBeat: 48, endBeat: 80, colorIndex: 2),
        ]
    }

    private func makeBeats() -> [Float] {
        // 0.5s spacing: 100 beats covering 0..50s
        (0..<100).map { Float($0) * 0.5 }
    }

    private func makeVM() -> SectionsViewModel {
        SectionsViewModel(
            sections: makeSections(),
            beats: makeBeats(),
            duration: 50
        )
    }

    func testRenameUpdatesLabel() {
        let vm = makeVM()
        vm.rename(sectionId: vm.sections[1].stableId, to: "Pre-Chorus")
        XCTAssertEqual(vm.sections[1].label, "Pre-Chorus")
    }

    func testMoveBoundarySnapsToBeatAndUpdatesAdjacentSections() {
        let vm = makeVM()
        // Boundary between section 0 and 1 is at 10s. Move to ~12.3s → snaps to 12.5s (a beat).
        vm.moveBoundary(beforeSectionId: vm.sections[1].stableId, toTime: 12.3, snapToBeat: true)
        XCTAssertEqual(vm.sections[0].endTime, 12.5)
        XCTAssertEqual(vm.sections[1].startTime, 12.5)
    }

    func testMoveBoundaryRespectsMinimumOneBeatLength() {
        let vm = makeVM()
        // Try to drag boundary past adjacent boundary — should clamp to leave >= 1 beat (0.5s)
        vm.moveBoundary(beforeSectionId: vm.sections[1].stableId, toTime: 100, snapToBeat: false)
        XCTAssertLessThan(vm.sections[0].endTime, vm.sections[1].endTime)
        XCTAssertGreaterThanOrEqual(vm.sections[1].endTime - vm.sections[1].startTime, 0.5)
    }

    func testCannotMoveOuterEdges() {
        let vm = makeVM()
        let firstId = vm.sections[0].stableId
        // Attempt to move boundary "before" the first section is a no-op
        vm.moveBoundary(beforeSectionId: firstId, toTime: 5, snapToBeat: false)
        XCTAssertEqual(vm.sections[0].startTime, 0)
    }

    func testAddSplitsSectionAtTime() {
        let vm = makeVM()
        // Split Verse (10..30) at t=20 → Verse (10..20), "Section" (20..30)
        vm.addSplit(inSectionId: vm.sections[1].stableId, atTime: 20, snapToBeat: true)
        XCTAssertEqual(vm.sections.count, 4)
        XCTAssertEqual(vm.sections[1].endTime, 20)
        XCTAssertEqual(vm.sections[2].startTime, 20)
        XCTAssertEqual(vm.sections[2].label, "Section")
        // Total coverage preserved
        XCTAssertEqual(vm.sections.first?.startTime, 0)
        XCTAssertEqual(vm.sections.last?.endTime, 50)
    }

    func testDeleteMergesIntoPreviousNeighbor() {
        let vm = makeVM()
        let chorusId = vm.sections[2].stableId
        vm.delete(sectionId: chorusId)
        XCTAssertEqual(vm.sections.count, 2)
        XCTAssertEqual(vm.sections[1].label, "Verse")
        XCTAssertEqual(vm.sections[1].endTime, 50) // absorbed Chorus range
    }

    func testDeleteFirstMergesIntoNext() {
        let vm = makeVM()
        let introId = vm.sections[0].stableId
        vm.delete(sectionId: introId)
        XCTAssertEqual(vm.sections.count, 2)
        XCTAssertEqual(vm.sections[0].label, "Verse")
        XCTAssertEqual(vm.sections[0].startTime, 0)
    }

    func testCannotDeleteLastRemainingSection() {
        let vm = SectionsViewModel(
            sections: [AudioSection(label: "Only", startTime: 0, endTime: 50, startBeat: 0, endBeat: 80, colorIndex: 0)],
            beats: makeBeats(),
            duration: 50
        )
        vm.delete(sectionId: vm.sections[0].stableId)
        XCTAssertEqual(vm.sections.count, 1)
    }

    func testRecolorUpdatesColorIndex() {
        let vm = makeVM()
        vm.recolor(sectionId: vm.sections[0].stableId, colorIndex: 5)
        XCTAssertEqual(vm.sections[0].colorIndex, 5)
    }

    func testRenameToKnownLabelAutoUpdatesColorWhenNotUserOverridden() {
        let vm = makeVM()
        let id = vm.sections[1].stableId  // Verse, colorIndex 1
        vm.rename(sectionId: id, to: "Chorus")
        XCTAssertEqual(vm.sections[1].colorIndex, 2)  // Chorus → red(2)
    }

    func testRenameDoesNotOverrideManualColorThisSession() {
        let vm = makeVM()
        let id = vm.sections[1].stableId
        vm.recolor(sectionId: id, colorIndex: 7)
        vm.rename(sectionId: id, to: "Chorus")
        XCTAssertEqual(vm.sections[1].colorIndex, 7)
    }

    func testUndoRevertsRename() {
        let vm = makeVM()
        let id = vm.sections[1].stableId
        let originalLabel = vm.sections[1].label
        vm.rename(sectionId: id, to: "Pre-Chorus")
        vm.undoManager.undo()
        XCTAssertEqual(vm.sections[1].label, originalLabel)
    }

    func testRedoReappliesRename() {
        let vm = makeVM()
        let id = vm.sections[1].stableId
        vm.rename(sectionId: id, to: "Pre-Chorus")
        vm.undoManager.undo()
        vm.undoManager.redo()
        XCTAssertEqual(vm.sections[1].label, "Pre-Chorus")
    }

    func testUndoRevertsDelete() {
        let vm = makeVM()
        let id = vm.sections[2].stableId
        vm.delete(sectionId: id)
        XCTAssertEqual(vm.sections.count, 2)
        vm.undoManager.undo()
        XCTAssertEqual(vm.sections.count, 3)
        XCTAssertEqual(vm.sections[2].label, "Chorus")
    }

    func testOnChangeFiresAfterMutationAndUndo() {
        let vm = makeVM()
        var fireCount = 0
        vm.onChange = { _ in fireCount += 1 }
        vm.rename(sectionId: vm.sections[0].stableId, to: "X")
        vm.undoManager.undo()
        XCTAssertEqual(fireCount, 2)
    }

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

    func testCreateSectionStartsAtLeftEdgeEndsInside() {
        // Fixture: Intro 0..10, Verse 10..30, Chorus 30..50.
        // createSection(10, 20) — left edge coincides with Verse.startTime, ends inside Verse.
        // Expected carve: Intro 0..10, NEW 10..20, Verse-remainder 20..30, Chorus 30..50.
        let vm = makeVM()
        vm.createSection(startTime: 10, endTime: 20, snapToBeat: false)
        XCTAssertEqual(vm.sections.count, 4)
        XCTAssertEqual(vm.sections[0].endTime, 10)
        XCTAssertEqual(vm.sections[1].startTime, 10)
        XCTAssertEqual(vm.sections[1].endTime, 20)
        XCTAssertEqual(vm.sections[1].label, "")
        XCTAssertEqual(vm.sections[2].startTime, 20)
        XCTAssertEqual(vm.sections[2].endTime, 30)
        XCTAssertEqual(vm.sections[2].label, "Verse")
        XCTAssertEqual(vm.sections[3].label, "Chorus")
    }

    func testCreateSectionStartsInsideEndsAtRightEdge() {
        // createSection(20, 30) — starts inside Verse, right edge coincides with Verse.endTime.
        // Expected: Intro 0..10, Verse-remainder 10..20, NEW 20..30, Chorus 30..50.
        let vm = makeVM()
        vm.createSection(startTime: 20, endTime: 30, snapToBeat: false)
        XCTAssertEqual(vm.sections.count, 4)
        XCTAssertEqual(vm.sections[0].label, "Intro")
        XCTAssertEqual(vm.sections[1].startTime, 10)
        XCTAssertEqual(vm.sections[1].endTime, 20)
        XCTAssertEqual(vm.sections[1].label, "Verse")
        XCTAssertEqual(vm.sections[2].startTime, 20)
        XCTAssertEqual(vm.sections[2].endTime, 30)
        XCTAssertEqual(vm.sections[2].label, "")
        XCTAssertEqual(vm.sections[3].label, "Chorus")
    }

    func testCreateSectionExactlyMatchesExistingBoundaries() {
        // createSection(10, 30) — exactly the Verse range. Verse is engulfed and replaced.
        let vm = makeVM()
        vm.createSection(startTime: 10, endTime: 30, snapToBeat: false)
        XCTAssertEqual(vm.sections.count, 3)
        XCTAssertEqual(vm.sections[0].label, "Intro")
        XCTAssertEqual(vm.sections[1].startTime, 10)
        XCTAssertEqual(vm.sections[1].endTime, 30)
        XCTAssertEqual(vm.sections[1].label, "")
        XCTAssertEqual(vm.sections[2].label, "Chorus")
    }

    func testCreateSectionAtTrackStart() {
        // createSection(0, 15) — engulfs Intro and trims left edge of Verse.
        let vm = makeVM()
        vm.createSection(startTime: 0, endTime: 15, snapToBeat: false)
        XCTAssertEqual(vm.sections.count, 3)
        XCTAssertEqual(vm.sections[0].startTime, 0)
        XCTAssertEqual(vm.sections[0].endTime, 15)
        XCTAssertEqual(vm.sections[0].label, "")
        XCTAssertEqual(vm.sections[1].startTime, 15)
        XCTAssertEqual(vm.sections[1].endTime, 30)
        XCTAssertEqual(vm.sections[1].label, "Verse")
        XCTAssertEqual(vm.sections[2].label, "Chorus")
    }

    func testCreateSectionAtTrackEndClampsToDuration() {
        // Fixture duration = 50. Request (45, 999) → clamps end to 50.
        let vm = makeVM()
        vm.createSection(startTime: 45, endTime: 999, snapToBeat: false)
        XCTAssertEqual(vm.sections.last?.startTime, 45)
        XCTAssertEqual(vm.sections.last?.endTime, 50)
        XCTAssertEqual(vm.sections.last?.label, "")
    }

    /// Asserts the partition still tiles [0, duration] with no gaps or overlaps.
    /// Call at the end of any mutation test.
    private func assertPartitionInvariant(_ sections: [AudioSection], duration: Float,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(sections.isEmpty, file: file, line: line)
        guard let first = sections.first, let last = sections.last else { return }
        XCTAssertEqual(first.startTime, 0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(last.endTime, duration, accuracy: 0.0001, file: file, line: line)
        for i in 1..<sections.count {
            XCTAssertEqual(sections[i].startTime, sections[i - 1].endTime,
                           accuracy: 0.0001,
                           "Gap/overlap between section \(i - 1) and \(i)",
                           file: file, line: line)
        }
    }

    func testPartitionInvariantHoldsAcrossCarveVariants() {
        // Sanity: run several carves and verify the partition invariant after each.
        let carves: [(Float, Float)] = [
            (5, 15),      // partial-left + partial-right
            (10, 20),     // left edge coincident
            (20, 30),     // right edge coincident
            (10, 30),     // exact engulf
            (5, 35),      // span-three
            (0, 15),      // track start
            (45, 50),     // track end
            (15, 25),     // inside-one split
        ]
        for (s, e) in carves {
            let vm = makeVM()
            vm.createSection(startTime: s, endTime: e, snapToBeat: false)
            assertPartitionInvariant(vm.sections, duration: 50)
        }
    }

    func testCreateSectionSplitPreservesBeforeIdAndAssignsNewAfterId() {
        // Fixture Verse stableId = X. Split Verse(10..30) with createSection(15, 25).
        // Expected: Verse-before (10..15) keeps stableId X; Verse-after (25..30) has a new id.
        let vm = makeVM()
        let originalVerseId = vm.sections[1].stableId
        vm.createSection(startTime: 15, endTime: 25, snapToBeat: false)
        XCTAssertEqual(vm.sections[1].stableId, originalVerseId, "Before-half should keep original id")
        XCTAssertNotEqual(vm.sections[3].stableId, originalVerseId, "After-half should have a new id")
        // All four remaining ids must be unique.
        let ids = Set(vm.sections.map { $0.stableId })
        XCTAssertEqual(ids.count, vm.sections.count)
    }

    func testCreateSectionAbsorbsSubMinLenAfterResidue() {
        // Fixture beats are 0.5s apart → minLen = 0.5.
        // Split Verse(10..30) with carve (15, 29.8) — after-residue is 0.2s < minLen(0.5),
        // so the new section should absorb it: new becomes 15..30 (no after-slice).
        let vm = makeVM()
        vm.createSection(startTime: 15, endTime: 29.8, snapToBeat: false)
        // Sections: Intro(0..10), Verse-before(10..15), new(15..30), Chorus(30..50) → 4 sections.
        XCTAssertEqual(vm.sections.count, 4)
        XCTAssertEqual(vm.sections[2].startTime, 15, accuracy: 0.0001)
        XCTAssertEqual(vm.sections[2].endTime, 30, accuracy: 0.0001)
    }

    func testCreateSectionAbsorbsSubMinLenBeforeResidue() {
        // carve (10.2, 25) — before-residue (10..10.2) is 0.2s < minLen(0.5).
        // new should absorb it → new becomes 10..25.
        let vm = makeVM()
        vm.createSection(startTime: 10.2, endTime: 25, snapToBeat: false)
        // Sections: Intro(0..10), new(10..25), Verse-after(25..30), Chorus(30..50) → 4 sections.
        XCTAssertEqual(vm.sections.count, 4)
        XCTAssertEqual(vm.sections[1].startTime, 10, accuracy: 0.0001)
        XCTAssertEqual(vm.sections[1].endTime, 25, accuracy: 0.0001)
    }
}
