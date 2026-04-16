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

    private func makeVM() -> SectionEditorViewModel {
        SectionEditorViewModel(
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
        let vm = SectionEditorViewModel(
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

    func testReorderSwapsLabelAndColorOnly() {
        let vm = makeVM()
        let aId = vm.sections[1].stableId
        vm.reorder(sectionId: aId, direction: .right)
        // Label/color of original sections[1] now at index 2; times unchanged for both.
        XCTAssertEqual(vm.sections[1].label, "Chorus")
        XCTAssertEqual(vm.sections[2].label, "Verse")
        XCTAssertEqual(vm.sections[1].startTime, 10)
        XCTAssertEqual(vm.sections[2].startTime, 30)
    }
}
