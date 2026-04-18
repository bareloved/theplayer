import Foundation

struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]
    let downbeatOffset: Int
    let firstDownbeatTime: Float
    let timeSignature: TimeSignature
    let onsets: [Float]

    init(
        bpm: Float,
        beats: [Float],
        sections: [AudioSection],
        waveformPeaks: [Float],
        downbeatOffset: Int = 0,
        firstDownbeatTime: Float? = nil,
        timeSignature: TimeSignature = .fourFour,
        onsets: [Float] = []
    ) {
        self.bpm = bpm
        self.beats = beats
        self.sections = sections
        self.waveformPeaks = waveformPeaks
        self.downbeatOffset = downbeatOffset
        if let t = firstDownbeatTime {
            self.firstDownbeatTime = t
        } else if !beats.isEmpty {
            let idx = max(0, min(downbeatOffset, beats.count - 1))
            self.firstDownbeatTime = beats[idx]
        } else {
            self.firstDownbeatTime = 0
        }
        self.timeSignature = timeSignature
        self.onsets = onsets
    }

    func with(sections: [AudioSection]) -> TrackAnalysis {
        TrackAnalysis(
            bpm: bpm, beats: beats, sections: sections, waveformPeaks: waveformPeaks,
            downbeatOffset: downbeatOffset, firstDownbeatTime: firstDownbeatTime,
            timeSignature: timeSignature, onsets: onsets
        )
    }

    /// Copy replacing just `firstDownbeatTime` (used by merge).
    func with(firstDownbeatTime: Float) -> TrackAnalysis {
        TrackAnalysis(
            bpm: bpm, beats: beats, sections: sections, waveformPeaks: waveformPeaks,
            downbeatOffset: downbeatOffset, firstDownbeatTime: firstDownbeatTime,
            timeSignature: timeSignature, onsets: onsets
        )
    }

    enum CodingKeys: String, CodingKey {
        case bpm, beats, sections, waveformPeaks, downbeatOffset, firstDownbeatTime, timeSignature, onsets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bpm = try c.decode(Float.self, forKey: .bpm)
        self.beats = try c.decode([Float].self, forKey: .beats)
        self.sections = try c.decode([AudioSection].self, forKey: .sections)
        self.waveformPeaks = try c.decode([Float].self, forKey: .waveformPeaks)
        self.downbeatOffset = try c.decodeIfPresent(Int.self, forKey: .downbeatOffset) ?? 0
        self.timeSignature = try c.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) ?? .fourFour
        self.onsets = try c.decodeIfPresent([Float].self, forKey: .onsets) ?? []
        if let t = try c.decodeIfPresent(Float.self, forKey: .firstDownbeatTime) {
            self.firstDownbeatTime = t
        } else if !beats.isEmpty {
            let idx = max(0, min(self.downbeatOffset, self.beats.count - 1))
            self.firstDownbeatTime = beats[idx]
        } else {
            self.firstDownbeatTime = 0
        }
    }
}
