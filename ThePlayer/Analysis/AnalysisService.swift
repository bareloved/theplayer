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
                    let onsets = (result.onsets ?? []).map { $0.floatValue }

                    progress(1.0)

                    let analysis = TrackAnalysis(
                        bpm: result.bpm,
                        beats: beats,
                        sections: sections,
                        waveformPeaks: peaks,
                        downbeatOffset: Int(result.downbeatOffset),
                        timeSignature: .fourFour,
                        onsets: onsets
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
    private(set) var baseAnalysis: TrackAnalysis?
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
        guard let edits = userEdits else { return analysis }
        let mergedSections = edits.sections.isEmpty ? analysis.sections : edits.sections
        let mergedBpm = edits.bpmOverride ?? analysis.bpm
        let mergedTimeSig = edits.timeSignatureOverride ?? analysis.timeSignature
        let mergedFirstDb = edits.downbeatTimeOverride ?? analysis.firstDownbeatTime
        return TrackAnalysis(
            bpm: mergedBpm,
            beats: analysis.beats,
            sections: mergedSections,
            waveformPeaks: analysis.waveformPeaks,
            downbeatOffset: analysis.downbeatOffset,
            firstDownbeatTime: mergedFirstDb,
            timeSignature: mergedTimeSig,
            onsets: analysis.onsets
        )
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
                baseAnalysis = cached
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
            baseAnalysis = result
            lastAnalysis = Self.mergeCachedAnalysis(result, userEdits: edits)
        } catch {
            analysisError = error.localizedDescription
            lastAnalysis = nil
        }

        isAnalyzing = false
    }

    func reanalyze(key providedKey: String? = nil, fileURL: URL) async throws {
        isAnalyzing = true
        progress = 0
        analysisError = nil
        lastFileURL = fileURL

        let key: String
        if let providedKey { key = providedKey }
        else { key = try AnalysisCache.fileHash(for: fileURL) }
        lastAnalysisKey = key

        let result = try await analyzer.analyze(fileURL: fileURL) { [weak self] p in
            Task { @MainActor in self?.progress = p }
        }
        try cache.store(result, forKey: key)
        let edits = try userEdits.retrieve(forKey: key)
        hasUserEditsForCurrent = edits != nil
        baseAnalysis = result
        lastAnalysis = Self.mergeCachedAnalysis(result, userEdits: edits)
        isAnalyzing = false
    }

    /// Patch only the timing-override fields on the current sidecar, preserving sections.
    func saveTimingOverrides(bpm: Float?, downbeatTime: Float?, timeSignature: TimeSignature?) throws {
        guard let key = lastAnalysisKey else { return }
        let existing = try userEdits.retrieve(forKey: key) ?? UserEdits(sections: [])
        var updated = existing
        updated.bpmOverride = bpm
        updated.downbeatTimeOverride = downbeatTime
        updated.timeSignatureOverride = timeSignature
        updated.modifiedAt = Date()
        try userEdits.store(updated, forKey: key)
        hasUserEditsForCurrent = true
    }

    /// True if the user has edited sections (vs. timing overrides only).
    /// Separate from `hasUserEditsForCurrent` so the "Manual section edits applied" banner
    /// doesn't fire for silent timing tweaks (BPM / downbeat / time signature).
    var hasUserSectionEdits: Bool {
        guard let base = baseAnalysis, let last = lastAnalysis else { return false }
        return last.sections != base.sections
    }

    /// Persist edited sections for the currently loaded track. Preserves any timing overrides
    /// already in the sidecar (bpm / downbeat / time signature).
    func saveUserEdits(_ sections: [AudioSection]) throws {
        guard let key = lastAnalysisKey else { return }
        var next = (try? userEdits.retrieve(forKey: key)) ?? UserEdits(sections: [])
        next.sections = sections
        next.modifiedAt = Date()
        try userEdits.store(next, forKey: key)
        hasUserEditsForCurrent = true
    }

    /// Discard SECTION edits only. Timing overrides (bpm / downbeat / time signature) remain.
    /// Used by the "Discard Edits" banner.
    func discardSectionEdits() async {
        guard let key = lastAnalysisKey, let base = baseAnalysis else { return }
        var next = (try? userEdits.retrieve(forKey: key)) ?? UserEdits(sections: [])
        next.sections = []
        next.modifiedAt = Date()
        try? userEdits.store(next, forKey: key)
        lastAnalysis = Self.mergeCachedAnalysis(base, userEdits: next)
        let hasAny = next.bpmOverride != nil ||
                     next.downbeatTimeOverride != nil ||
                     next.timeSignatureOverride != nil ||
                     !next.sections.isEmpty
        hasUserEditsForCurrent = hasAny
    }

    /// Nuke the entire sidecar (sections + timing). Kept in case a caller needs a full reset.
    func discardUserEdits() async {
        guard let key = lastAnalysisKey, let cached = try? cache.retrieve(forKey: key) else { return }
        try? userEdits.delete(forKey: key)
        hasUserEditsForCurrent = false
        baseAnalysis = cached
        lastAnalysis = cached
    }

    /// Apply a patched sidecar and re-merge lastAnalysis. Used by timing-controls UI.
    func applyUserEditsPatch(_ edits: UserEdits) throws {
        guard let key = lastAnalysisKey else { return }
        try userEdits.store(edits, forKey: key)
        if let base = baseAnalysis {
            lastAnalysis = Self.mergeCachedAnalysis(base, userEdits: edits)
            hasUserEditsForCurrent = true
        }
    }
}
