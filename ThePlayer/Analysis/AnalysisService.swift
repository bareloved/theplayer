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
    private(set) var lastAnalysisKey: String?
    private(set) var lastFileURL: URL?
    private(set) var hasUserEditsForCurrent = false
    private(set) var analysisError: String?

    private let analyzer: TrackAnalyzerProtocol
    private let cache: AnalysisCache
    let userEdits: UserEditsStore

    init(
        analyzer: TrackAnalyzerProtocol = EssentiaAnalyzerSwift(),
        cache: AnalysisCache = AnalysisCache(),
        userEdits: UserEditsStore = UserEditsStore()
    ) {
        self.analyzer = analyzer
        self.cache = cache
        self.userEdits = userEdits
    }

    static func mergeCachedAnalysis(_ analysis: TrackAnalysis, userEdits: UserEdits?) -> TrackAnalysis {
        guard let edits = userEdits, !edits.sections.isEmpty else { return analysis }
        return analysis.with(sections: edits.sections)
    }

    func analyze(fileURL: URL) async {
        isAnalyzing = true
        progress = 0
        analysisError = nil
        lastFileURL = fileURL

        do {
            let key = try AnalysisCache.fileHash(for: fileURL)
            lastAnalysisKey = key

            if let cached = try cache.retrieve(forKey: key) {
                let edits = try userEdits.retrieve(forKey: key)
                hasUserEditsForCurrent = edits != nil
                lastAnalysis = Self.mergeCachedAnalysis(cached, userEdits: edits)
                progress = 1.0
                isAnalyzing = false
                return
            }

            let result = try await analyzer.analyze(fileURL: fileURL) { [weak self] p in
                Task { @MainActor in
                    self?.progress = p
                }
            }

            try cache.store(result, forKey: key)
            let edits = try userEdits.retrieve(forKey: key)
            hasUserEditsForCurrent = edits != nil
            lastAnalysis = Self.mergeCachedAnalysis(result, userEdits: edits)
        } catch {
            analysisError = error.localizedDescription
            lastAnalysis = nil
        }

        isAnalyzing = false
    }

    /// Persist edited sections for the currently loaded track.
    func saveUserEdits(_ sections: [AudioSection]) throws {
        guard let key = lastAnalysisKey else { return }
        try userEdits.store(UserEdits(sections: sections), forKey: key)
        hasUserEditsForCurrent = true
    }

    /// Discard sidecar and reload analyzer output for the currently loaded track.
    func discardUserEdits() async {
        guard let key = lastAnalysisKey, let cached = try? cache.retrieve(forKey: key) else { return }
        try? userEdits.delete(forKey: key)
        hasUserEditsForCurrent = false
        lastAnalysis = cached
    }
}
