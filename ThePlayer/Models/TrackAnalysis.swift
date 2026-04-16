import Foundation

struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]

    func with(sections: [AudioSection]) -> TrackAnalysis {
        TrackAnalysis(bpm: bpm, beats: beats, sections: sections, waveformPeaks: waveformPeaks)
    }
}
