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
            sections: [],
            waveformPeaks: (0..<500).map { _ in Float.random(in: 0.1...0.9) },
            onsets: stride(from: Float(0), to: 180, by: 0.5).map { $0 + 0.01 }
        )
    }
}
