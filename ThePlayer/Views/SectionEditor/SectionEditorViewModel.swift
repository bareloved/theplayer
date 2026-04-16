import SwiftUI
import Observation

@Observable
final class SectionEditorViewModel {
    enum ReorderDirection { case left, right }

    private(set) var sections: [AudioSection]
    private(set) var manualColorOverrides: Set<UUID> = []  // session-only

    let beats: [Float]
    let duration: Float

    /// Called whenever sections mutate; consumer persists.
    var onChange: (([AudioSection]) -> Void)?

    let undoManager = UndoManager()

    init(sections: [AudioSection], beats: [Float], duration: Float) {
        self.sections = sections
        self.beats = beats
        self.duration = duration
    }

    // MARK: - Mutations

    func rename(sectionId: UUID, to newLabel: String) {
        guard let idx = sections.firstIndex(where: { $0.stableId == sectionId }) else { return }
        let prev = sections[idx]
        applyChange(undoLabel: "Rename Section") {
            self.sections[idx].label = newLabel
            // Auto-update color if label is known AND user hasn't manually picked a color
            if !self.manualColorOverrides.contains(sectionId),
               let defaultColor = SectionLabelPresets.defaultColorIndex(for: newLabel) {
                self.sections[idx].colorIndex = defaultColor
            }
        } undo: {
            self.sections[idx] = prev
        }
    }

    func recolor(sectionId: UUID, colorIndex: Int) {
        guard let idx = sections.firstIndex(where: { $0.stableId == sectionId }) else { return }
        let prev = sections[idx].colorIndex
        let prevManual = manualColorOverrides.contains(sectionId)
        applyChange(undoLabel: "Change Section Color") {
            self.sections[idx].colorIndex = colorIndex
            self.manualColorOverrides.insert(sectionId)
        } undo: {
            self.sections[idx].colorIndex = prev
            if !prevManual { self.manualColorOverrides.remove(sectionId) }
        }
    }

    func moveBoundary(beforeSectionId: UUID, toTime requested: Float, snapToBeat: Bool) {
        guard let idx = sections.firstIndex(where: { $0.stableId == beforeSectionId }), idx > 0 else { return }
        let leftPrev = sections[idx - 1]
        let rightPrev = sections[idx]

        let snapped = snapToBeat ? Self.snapToNearestBeat(time: requested, beats: beats) : requested
        // Constraints: at least 1 beat (or 0.5s fallback) on each side
        let minLen: Float = beats.count >= 2 ? Float(beats[1] - beats[0]) : 0.5
        let lowerBound = leftPrev.startTime + minLen
        let upperBound = rightPrev.endTime - minLen
        let clamped = max(lowerBound, min(upperBound, snapped))

        applyChange(undoLabel: "Move Boundary") {
            self.sections[idx - 1].endTime = clamped
            self.sections[idx].startTime = clamped
            self.recomputeBeatsForRange(idx - 1 ... idx)
        } undo: {
            self.sections[idx - 1] = leftPrev
            self.sections[idx] = rightPrev
        }
    }

    func addSplit(inSectionId: UUID, atTime requested: Float, snapToBeat: Bool) {
        guard let idx = sections.firstIndex(where: { $0.stableId == inSectionId }) else { return }
        let original = sections[idx]
        let snapped = snapToBeat ? Self.snapToNearestBeat(time: requested, beats: beats) : requested
        let minLen: Float = beats.count >= 2 ? Float(beats[1] - beats[0]) : 0.5
        let lower = original.startTime + minLen
        let upper = original.endTime - minLen
        guard upper > lower else { return }
        let cut = max(lower, min(upper, snapped))

        let newRight = AudioSection(
            label: "Section",
            startTime: cut,
            endTime: original.endTime,
            startBeat: original.startBeat,
            endBeat: original.endBeat,
            colorIndex: 0
        )

        applyChange(undoLabel: "Add Section") {
            var leftEdited = original
            leftEdited.endTime = cut
            self.sections[idx] = leftEdited
            self.sections.insert(newRight, at: idx + 1)
            self.recomputeBeatsForRange(idx ... idx + 1)
        } undo: {
            self.sections.remove(at: idx + 1)
            self.sections[idx] = original
        }
    }

    func delete(sectionId: UUID) {
        guard sections.count > 1,
              let idx = sections.firstIndex(where: { $0.stableId == sectionId }) else { return }
        let removed = sections[idx]
        if idx > 0 {
            let neighbor = sections[idx - 1]
            applyChange(undoLabel: "Delete Section") {
                self.sections[idx - 1].endTime = removed.endTime
                self.sections.remove(at: idx)
                self.recomputeBeatsForRange((idx - 1) ... (idx - 1))
            } undo: {
                self.sections[idx - 1] = neighbor
                self.sections.insert(removed, at: idx)
            }
        } else {
            let neighbor = sections[idx + 1]
            applyChange(undoLabel: "Delete Section") {
                self.sections[idx + 1].startTime = removed.startTime
                self.sections.remove(at: idx)
                self.recomputeBeatsForRange(idx ... idx)
            } undo: {
                self.sections[idx + 1] = neighbor
                self.sections.insert(removed, at: idx)
            }
        }
    }

    func reorder(sectionId: UUID, direction: ReorderDirection) {
        guard let idx = sections.firstIndex(where: { $0.stableId == sectionId }) else { return }
        let other: Int
        switch direction {
        case .left:  other = idx - 1
        case .right: other = idx + 1
        }
        guard sections.indices.contains(other) else { return }

        let aPrev = sections[idx]
        let bPrev = sections[other]

        applyChange(undoLabel: "Reorder Section") {
            // Swap label + colorIndex (and stableId where appropriate). Keep time ranges in place.
            self.sections[idx].label = bPrev.label
            self.sections[idx].colorIndex = bPrev.colorIndex
            self.sections[other].label = aPrev.label
            self.sections[other].colorIndex = aPrev.colorIndex
        } undo: {
            self.sections[idx] = aPrev
            self.sections[other] = bPrev
        }
    }

    func replaceAll(with newSections: [AudioSection]) {
        let prev = sections
        applyChange(undoLabel: "Reset Sections") {
            self.sections = newSections
            self.manualColorOverrides.removeAll()
        } undo: {
            self.sections = prev
        }
    }

    // MARK: - Helpers

    static func snapToNearestBeat(time: Float, beats: [Float]) -> Float {
        guard !beats.isEmpty else { return time }
        return beats.min(by: { abs($0 - time) < abs($1 - time) }) ?? time
    }

    private func recomputeBeatsForRange(_ range: ClosedRange<Int>) {
        for i in range where sections.indices.contains(i) {
            let s = sections[i]
            var startBeat = 0
            var endBeat = 0
            for (b, t) in beats.enumerated() {
                if t <= s.startTime + 0.05 { startBeat = b }
                if t <= s.endTime + 0.05 { endBeat = b }
            }
            sections[i].startBeat = startBeat
            sections[i].endBeat = endBeat
        }
    }

    private func applyChange(undoLabel: String, _ action: @escaping () -> Void, undo: @escaping () -> Void) {
        action()
        onChange?(sections)
        undoManager.registerUndo(withTarget: self) { vm in
            undo()
            vm.onChange?(vm.sections)
            // Register redo so subsequent redo replays this action
            vm.applyChange(undoLabel: undoLabel, action, undo: undo)
        }
        undoManager.setActionName(undoLabel)
    }
}
