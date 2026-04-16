import Foundation

struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]
}
