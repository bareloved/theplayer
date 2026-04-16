import Foundation

struct LoopRegion: Equatable {
    var startTime: Float
    var endTime: Float

    var duration: Float { endTime - startTime }

    func contains(time: Float) -> Bool {
        time >= startTime && time < endTime
    }

    static func snapToNearestBeat(time: Float, beats: [Float]) -> Float {
        guard !beats.isEmpty else { return time }
        return beats.min(by: { abs($0 - time) < abs($1 - time) }) ?? time
    }

    static func from(section: AudioSection) -> LoopRegion {
        LoopRegion(startTime: section.startTime, endTime: section.endTime)
    }
}
