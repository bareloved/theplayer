import Foundation

struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]
    let downbeatOffset: Int
    let timeSignature: TimeSignature

    init(
        bpm: Float,
        beats: [Float],
        sections: [AudioSection],
        waveformPeaks: [Float],
        downbeatOffset: Int = 0,
        timeSignature: TimeSignature = .fourFour
    ) {
        self.bpm = bpm
        self.beats = beats
        self.sections = sections
        self.waveformPeaks = waveformPeaks
        self.downbeatOffset = downbeatOffset
        self.timeSignature = timeSignature
    }

    func with(sections: [AudioSection]) -> TrackAnalysis {
        TrackAnalysis(
            bpm: bpm, beats: beats, sections: sections, waveformPeaks: waveformPeaks,
            downbeatOffset: downbeatOffset, timeSignature: timeSignature
        )
    }

    enum CodingKeys: String, CodingKey {
        case bpm, beats, sections, waveformPeaks, downbeatOffset, timeSignature
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bpm = try c.decode(Float.self, forKey: .bpm)
        self.beats = try c.decode([Float].self, forKey: .beats)
        self.sections = try c.decode([AudioSection].self, forKey: .sections)
        self.waveformPeaks = try c.decode([Float].self, forKey: .waveformPeaks)
        self.downbeatOffset = try c.decodeIfPresent(Int.self, forKey: .downbeatOffset) ?? 0
        self.timeSignature = try c.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) ?? .fourFour
    }
}
