import Foundation

/// Snap grid size in number of bars (1 bar = 4 beats).
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

    /// Compact label for segmented picker
    var shortLabel: String { "\(rawValue)" }

    /// Generate snap positions — every N bars, where 1 bar = 4 beats
    func snapPositions(beats: [Float], bpm: Float, duration: Float) -> [Float] {
        guard beats.count >= 4 else { return [] }
        let beatsPerSnap = rawValue * 4
        return stride(from: 0, to: beats.count, by: beatsPerSnap).map { beats[$0] }
    }
}
