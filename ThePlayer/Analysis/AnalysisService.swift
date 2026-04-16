import Foundation
import Observation

@Observable
final class AnalysisService {
    private(set) var isAnalyzing = false
    private(set) var progress: Float = 0
    private(set) var lastAnalysis: TrackAnalysis?
    private(set) var analysisError: String?

    private let analyzer: TrackAnalyzerProtocol
    private let cache: AnalysisCache

    init(analyzer: TrackAnalyzerProtocol = MockAnalyzer(), cache: AnalysisCache = AnalysisCache()) {
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
