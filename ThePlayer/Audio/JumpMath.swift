// ThePlayer/Audio/JumpMath.swift
import Foundation

enum JumpDirection {
    case forward
    case backward
}

/// Move `currentTime` by `seconds` in the chosen direction, clamped to `[0, duration]`.
/// Used when Snap is OFF; works without analysis.
func nextSecondTime(
    from currentTime: Float,
    direction: JumpDirection,
    seconds: Float,
    duration: Float
) -> Float {
    let delta: Float = direction == .forward ? seconds : -seconds
    return min(max(currentTime + delta, 0), duration)
}
