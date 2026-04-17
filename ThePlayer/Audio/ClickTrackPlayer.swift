import AVFoundation
import Darwin

final class ClickTrackPlayer {
    var isEnabled: Bool = false {
        didSet { if !isEnabled { stop() } }
    }
    var volume: Float = 0.5 {
        didSet { playerNode.volume = volume }
    }

    private let audioEngine: AudioEngine
    private let playerNode = AVAudioPlayerNode()
    private var downbeatBuffer: AVAudioPCMBuffer?
    private var beatBuffer: AVAudioPCMBuffer?

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        loadBuffers()
        // Connect using the buffer's format so the mixer's expected channel
        // count / sample rate match the WAV exactly.
        let format = downbeatBuffer?.format
        audioEngine.attachSecondaryPlayer(playerNode, format: format)
        playerNode.volume = volume
    }

    private func loadBuffers() {
        downbeatBuffer = loadBuffer(name: "MetronomeUp")
        beatBuffer = loadBuffer(name: "MetronomeDown")
    }

    private func loadBuffer(name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        try? file.read(into: buffer)
        return buffer
    }

    func reschedule(bpm: Float, firstDownbeatTime: Float, beatsPerBar: Int, currentSongTime: Float, speed: Float) {
        guard isEnabled, bpm > 0, beatsPerBar > 0, speed > 0,
              let down = downbeatBuffer, let beat = beatBuffer else {
            stop()
            return
        }

        playerNode.stop()

        guard let lastRender = playerNode.lastRenderTime else {
            return
        }
        let currentHostTime = lastRender.hostTime

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)

        let beatDurationSong: Float = 60.0 / bpm
        let kStart = Int(ceil(Double((currentSongTime - firstDownbeatTime) / beatDurationSong)))

        let beatsToSchedule = 80
        playerNode.volume = volume

        for i in 0..<beatsToSchedule {
            let k = kStart + i
            let beatTimeInSong = firstDownbeatTime + Float(k) * beatDurationSong
            if beatTimeInSong < currentSongTime - 0.01 { continue }
            let offsetSeconds = Double((beatTimeInSong - currentSongTime) / speed)
            if offsetSeconds < 0 { continue }
            let offsetNanos = UInt64(offsetSeconds * 1_000_000_000)
            let offsetHostTicks = offsetNanos * UInt64(timebase.denom) / UInt64(timebase.numer)
            let clickHostTime = currentHostTime &+ offsetHostTicks
            let avTime = AVAudioTime(hostTime: clickHostTime)

            let isDownbeat = ((k % beatsPerBar) + beatsPerBar) % beatsPerBar == 0
            let buffer = isDownbeat ? down : beat
            playerNode.scheduleBuffer(buffer, at: avTime, options: [], completionHandler: nil)
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func stop() {
        playerNode.stop()
    }
}
