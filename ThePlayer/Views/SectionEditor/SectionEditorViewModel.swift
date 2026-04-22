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
        self.undoManager.groupsByEvent = false
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
        }
        if !inserted {
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
        undoManager.beginUndoGrouping()
        registerReverse(undoLabel: undoLabel, forward: action, reverse: undo)
        undoManager.endUndoGrouping()
    }

    /// Registers `reverse` as the next undo (or redo, if we're currently
    /// inside an undo pass). When it fires, it runs `reverse`, notifies
    /// `onChange`, and then re-registers `forward` so the operation can be
    /// re-applied in the opposite direction.
    private func registerReverse(undoLabel: String, forward: @escaping () -> Void, reverse: @escaping () -> Void) {
        undoManager.registerUndo(withTarget: self) { vm in
            reverse()
            vm.onChange?(vm.sections)
            vm.registerReverse(undoLabel: undoLabel, forward: reverse, reverse: forward)
        }
        undoManager.setActionName(undoLabel)
    }
}
