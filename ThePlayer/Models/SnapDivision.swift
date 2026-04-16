import Foundation

enum SnapDivision: Int, CaseIterable, Identifiable {
    case quarterBeat = 1   // 1/4 — every quarter beat (sixteenth note grid)
    case halfBeat = 2      // 1/2 — every half beat (eighth note grid)
    case oneBeat = 4       // 1/1 — every beat (quarter note grid)
    case twoBeats = 8      // 2/1 — every 2 beats (half bar)
    case fourBeats = 16    // 4/1 — every 4 beats (full bar)

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .quarterBeat: "1/4"
        case .halfBeat: "1/2"
        case .oneBeat: "1/1"
        case .twoBeats: "2/1"
        case .fourBeats: "4/1"
        }
    }

    /// How many beats between each grid line
    var beatsPerSnap: Float {
        switch self {
        case .quarterBeat: 0.25
        case .halfBeat: 0.5
        case .oneBeat: 1.0
        case .twoBeats: 2.0
        case .fourBeats: 4.0
        }
    }

    /// Generate snap positions from a beat array and BPM
    func snapPositions(beats: [Float], bpm: Float, duration: Float) -> [Float] {
        guard !beats.isEmpty, bpm > 0 else { return [] }

        switch self {
        case .fourBeats:
            // Every 4 beats
            return stride(from: 0, to: beats.count, by: 4).map { beats[$0] }
        case .twoBeats:
            // Every 2 beats
            return stride(from: 0, to: beats.count, by: 2).map { beats[$0] }
        case .oneBeat:
            // Every beat
            return beats
        case .halfBeat:
            // Interpolate halfway between each beat
            var positions: [Float] = []
            for i in 0..<beats.count {
                positions.append(beats[i])
                if i + 1 < beats.count {
                    positions.append((beats[i] + beats[i + 1]) / 2.0)
                }
            }
            return positions
        case .quarterBeat:
            // Interpolate quarter points between each beat
            var positions: [Float] = []
            for i in 0..<beats.count {
                let current = beats[i]
                let next = i + 1 < beats.count ? beats[i + 1] : current + (60.0 / bpm)
                let step = (next - current) / 4.0
                positions.append(current)
                positions.append(current + step)
                positions.append(current + step * 2)
                positions.append(current + step * 3)
            }
            return positions.filter { $0 <= duration }
        }
    }
}
