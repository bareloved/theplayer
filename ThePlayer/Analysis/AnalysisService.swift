import Foundation
import Observation

struct EssentiaAnalyzerSwift: TrackAnalyzerProtocol {
    func analyze(fileURL: URL, progress: @escaping (Float) -> Void) async throws -> TrackAnalysis {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                progress(0.1)

                let analyzer = EssentiaAnalyzerObjC()
                do {
                    let result = try analyzer.analyzeFile(atPath: fileURL.path)

                    progress(0.8)

                    let sections = result.sections.enumerated().map { _, section in
                        AudioSection(
                            label: section.label,
                            startTime: section.startTime,
                            endTime: section.endTime,
                            startBeat: Int(section.startBeat),
                            endBeat: Int(section.endBeat),
                            colorIndex: Int(section.colorIndex)
                        )
                    }

                    let beats = result.beats.map { $0.floatValue }
                    let peaks = (try? WaveformExtractor.extractPeaks(from: fileURL)) ?? []

                    progress(1.0)

                    let analysis = TrackAnalysis(
                        bpm: result.bpm,
                        beats: beats,
                        sections: sections,
                        waveformPeaks: peaks
                    )
                    continuation.resume(returning: analysis)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@Observable
final class AnalysisService {
    private(set) var isAnalyzing = false
    private(set) var progress: Float = 0
    private(set) var lastAnalysis: TrackAnalysis?
    private(set) var analysisError: String?

    private let analyzer: TrackAnalyzerProtocol
    private let cache: AnalysisCache

    init(analyzer: TrackAnalyzerProtocol = EssentiaAnalyzerSwift(), cache: AnalysisCache = AnalysisCache()) {
        self.analyzer = analyzer
        self.cache = cache
    }

    func analyze(fileURL: URL) async {
        isAnalyzing = true
        progress = 0
        analysisError = nil

        do {
            // Check cache first
            let key = try AnalysisCache.fileHash(for: fileURL)
            if let cached = try cache.retrieve(forKey: key) {
                lastAnalysis = cached
                progress = 1.0
                isAnalyzing = false
                return
            }

            // Run analysis
            let result = try await analyzer.analyze(fileURL: fileURL) { [weak self] p in
                Task { @MainActor in
                    self?.progress = p
                }
            }

            // Cache result
            try cache.store(result, forKey: key)
            lastAnalysis = result
        } catch {
            analysisError = error.localizedDescription
            lastAnalysis = nil
        }

        isAnalyzing = false
    }
}
