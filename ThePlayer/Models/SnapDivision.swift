import Foundation

/// Snap grid size in number of bars.
enum SnapDivision: Int, CaseIterable, Identifiable {
    case oneBar = 1
    case twoBars = 2
    case fourBars = 4
    case eightBars = 8
    case sixteenBars = 16

    var id: Int { rawValue }

    var label: String {
        "\(rawValue) bar\(rawValue == 1 ? "" : "s")"
    }

    var shortLabel: String { "\(rawValue)" }

    /// Generate snap positions — every N bars, given beats-per-bar from the time signature.
    func snapPositions(beats: [Float], bpm: Float, duration: Float, beatsPerBar: Int) -> [Float] {
        guard beats.count >= beatsPerBar, beatsPerBar > 0 else { return [] }
        let beatsPerSnap = rawValue * beatsPerBar
        return stride(from: 0, to: beats.count, by: beatsPerSnap).map { beats[$0] }
    }
}
