import Foundation

struct MockAnalyzer: TrackAnalyzerProtocol {
    func analyze(fileURL: URL, progress: @escaping (Float) -> Void) async throws -> TrackAnalysis {
        // Simulate analysis time
        for i in 1...10 {
            try await Task.sleep(for: .milliseconds(50))
            progress(Float(i) / 10.0)
        }

        return TrackAnalysis(
            bpm: 120.0,
            beats: stride(from: Float(0), to: 180, by: 0.5).map { $0 },
            sections: [
                AudioSection(label: "Intro", startTime: 0, endTime: 15, startBeat: 0, endBeat: 30, colorIndex: 0),
                AudioSection(label: "Verse", startTime: 15, endTime: 45, startBeat: 30, endBeat: 90, colorIndex: 1),
                AudioSection(label: "Chorus", startTime: 45, endTime: 75, startBeat: 90, endBeat: 150, colorIndex: 2),
                AudioSection(label: "Verse", startTime: 75, endTime: 105, startBeat: 150, endBeat: 210, colorIndex: 1),
                AudioSection(label: "Chorus", startTime: 105, endTime: 135, startBeat: 210, endBeat: 270, colorIndex: 2),
                AudioSection(label: "Bridge", startTime: 135, endTime: 155, startBeat: 270, endBeat: 310, colorIndex: 3),
                AudioSection(label: "Outro", startTime: 155, endTime: 180, startBeat: 310, endBeat: 360, colorIndex: 0),
            ],
            waveformPeaks: (0..<500).map { _ in Float.random(in: 0.1...0.9) },
            onsets: stride(from: Float(0), to: 180, by: 0.5).map { $0 + 0.01 }
        )
    }
}
