import AVFoundation

enum WaveformExtractor {

    /// Default number of peak samples extracted per track. Bumps here should
    /// also trigger cache invalidation for old analyses (see `AnalysisCache`).
    static let targetPeakCount: Int = 16000

    static func extractPeaks(from url: URL, targetCount: Int = targetPeakCount) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw WaveformError.bufferCreationFailed
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw WaveformError.noChannelData
        }

        let channelCount = Int(format.channelCount)
        let sampleCount = Int(buffer.frameLength)

        // Mix to mono by averaging channels
        var monoSamples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += abs(channelData[ch][i])
            }
            monoSamples[i] = sum / Float(channelCount)
        }

        return downsample(monoSamples, to: targetCount)
    }

    static func downsample(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard targetCount > 0, !samples.isEmpty else { return [] }
        guard samples.count > targetCount else { return samples }

        let chunkSize = samples.count / targetCount
        var peaks = [Float]()
        peaks.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            let chunk = samples[start..<end]
            peaks.append(chunk.max() ?? 0)
        }

        return peaks
    }

    enum WaveformError: Error {
        case bufferCreationFailed
        case noChannelData
    }
}
