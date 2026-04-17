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

    /// Generate snap positions regularly from the first beat using BPM (so bars stay aligned with a fixed BPM).
    /// `firstBeatTime` should be the time of the first downbeat-1 (i.e., beats[downbeatOffset]).
    /// If callers pass the full beats array, the first element is used as a fallback origin when firstBeatTime is nil.
    func snapPositions(beats: [Float], bpm: Float, duration: Float, beatsPerBar: Int, firstBeatTime: Float? = nil) -> [Float] {
        guard bpm > 0, beatsPerBar > 0, duration > 0 else { return [] }
        let origin: Float = firstBeatTime ?? (beats.first ?? 0)
        let beatsPerSnap = rawValue * beatsPerBar
        let snapDuration: Float = Float(60.0) / bpm * Float(beatsPerSnap)
        guard snapDuration > 0 else { return [] }
        var positions: [Float] = []
        var t = origin
        while t < duration {
            positions.append(t)
            t += snapDuration
        }
        var tBack = origin - snapDuration
        while tBack >= 0 {
            positions.insert(tBack, at: 0)
            tBack -= snapDuration
        }
        return positions
    }
}
