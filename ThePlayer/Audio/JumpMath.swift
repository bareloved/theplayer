// ThePlayer/Audio/JumpMath.swift
import Foundation

enum JumpDirection {
    case forward
    case backward
}

enum JumpMath {
    /// Move `currentTime` by `seconds` in the chosen direction, clamped to `[0, duration]`.
    /// Used when Snap is OFF; works without analysis.
    static func nextSecondTime(
        from currentTime: Float,
        direction: JumpDirection,
        seconds: Float,
        duration: Float
    ) -> Float {
        let delta: Float = direction == .forward ? seconds : -seconds
        return min(max(currentTime + delta, 0), duration)
    }

    /// Move `currentTime` to the N-th bar line strictly after / before, clamped to `[0, duration]`.
    /// Returns `nil` when the analysis-derived inputs are invalid; callers should consume the keypress
    /// as a noop in that case (Snap-ON requires analysis).
    static func nextBarTime(
        from currentTime: Float,
        direction: JumpDirection,
        bars: Int,
        bpm: Float,
        beatsPerBar: Int,
        firstBeatTime: Float,
        duration: Float
    ) -> Float? {
        guard bpm > 0, beatsPerBar > 0, bars > 0 else { return nil }
        let barWidth: Float = 60.0 / bpm * Float(beatsPerBar)
        guard barWidth > 0 else { return nil }

        let offset = (currentTime - firstBeatTime) / barWidth
        let target: Float
        switch direction {
        case .forward:
            // Smallest integer k strictly greater than offset = floor(offset) + 1.
            let k0 = floor(offset) + 1
            target = firstBeatTime + (k0 + Float(bars - 1)) * barWidth
        case .backward:
            // Largest integer k strictly less than offset = ceil(offset) - 1.
            let k0 = ceil(offset) - 1
            target = firstBeatTime + (k0 - Float(bars - 1)) * barWidth
        }
        return min(max(target, 0), duration)
    }
}
