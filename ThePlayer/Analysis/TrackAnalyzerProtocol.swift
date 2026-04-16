import Foundation

protocol TrackAnalyzerProtocol {
    func analyze(fileURL: URL, progress: @escaping (Float) -> Void) async throws -> TrackAnalysis
}
