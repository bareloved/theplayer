import AVFoundation
import Darwin

/// Schedules metronome clicks via Chris Wilson's "two clocks" lookahead pattern:
/// a small queue of clicks (~`lookaheadSeconds` ahead) is topped up by a fast
/// refill timer (~`tickSeconds`). Tempo / time-signature / first-downbeat
/// changes bump a generation counter that flushes pending clicks on the next
/// tick. Speed changes are picked up live by the next tick — slider drags no
/// longer trigger 80-buffer reschedule storms.
final class ClickTrackPlayer {
    var isEnabled: Bool = false {
        didSet {
            if isEnabled { start() } else { stop() }
        }
    }
    var volume: Float = 0.5 {
        didSet { playerNode.volume = volume }
    }

    private let audioEngine: AudioEngine
    private let playerNode = AVAudioPlayerNode()
    private var downbeatBuffer: AVAudioPCMBuffer?
    private var beatBuffer: AVAudioPCMBuffer?

    // Analysis snapshot — set from main via `updateAnalysis`. Bump on change.
    private var bpm: Float = 0
    private var firstDownbeatTime: Float = 0
    private var beatsPerBar: Int = 4
    private var analysisGeneration: Int = 0

    // Refill state.
    private var nextBeatToSchedule: Int = Int.min
    private var lastSnapshotGeneration: Int = -1
    private var lastTransportGeneration: Int = -1
    private var lastSnapshotSpeed: Float = 1

    private var refillTimer: Timer?

    /// Lookahead window. 60 ms keeps any drift on speed change imperceptible
    /// (worst case ≈ window × |Δspeed| / speed) while still letting tempo
    /// changes propagate within ~60 ms.
    private static let lookaheadSeconds: Double = 0.060
    /// Refill cadence. ~25 ms is the standard Web Audio recipe — fast enough
    /// to keep the queue topped up, slow enough that the timer is cheap.
    private static let tickSeconds: Double = 0.025
    /// Speed delta below this fraction is ignored — keeps slider micro-jitter
    /// from invalidating the queue every tick.
    private static let speedInvalidateThreshold: Float = 0.005

    private let cachedTimebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        loadBuffers()
        let format = downbeatBuffer?.format
        audioEngine.attachSecondaryPlayer(playerNode, format: format)
        playerNode.volume = volume
    }

    // MARK: - Public

    /// Update the timing reference. Bumps the generation so any already-queued
    /// clicks get flushed on the next refill tick.
    func updateAnalysis(bpm: Float, firstDownbeatTime: Float, beatsPerBar: Int) {
        if bpm != self.bpm
            || firstDownbeatTime != self.firstDownbeatTime
            || beatsPerBar != self.beatsPerBar {
            self.bpm = bpm
            self.firstDownbeatTime = firstDownbeatTime
            self.beatsPerBar = beatsPerBar
            self.analysisGeneration &+= 1
        }
    }

    // MARK: - Internal

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

        // Pre-amplify: source WAVs are quiet relative to song material.
        let gain: Float = 3.0
        if let chData = buffer.floatChannelData {
            let frameCount = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            for ch in 0..<channels {
                let samples = chData[ch]
                for i in 0..<frameCount {
                    let v = samples[i] * gain
                    samples[i] = max(-1.0, min(1.0, v))
                }
            }
        }
        return buffer
    }

    private func start() {
        guard refillTimer == nil else { return }
        if !playerNode.isPlaying { playerNode.play() }
        playerNode.volume = volume
        let timer = Timer(timeInterval: Self.tickSeconds, repeats: true) { [weak self] _ in
            self?.refillTick()
        }
        // Common mode so scrolling / dragging UI doesn't pause the refill.
        RunLoop.main.add(timer, forMode: .common)
        refillTimer = timer
    }

    private func stop() {
        refillTimer?.invalidate()
        refillTimer = nil
        playerNode.stop()
        nextBeatToSchedule = Int.min
        lastSnapshotGeneration = -1
        lastTransportGeneration = -1
        lastSnapshotSpeed = 1
    }

    private func refillTick() {
        guard isEnabled,
              audioEngine.isPlaying,
              bpm > 0, beatsPerBar > 0,
              let down = downbeatBuffer, let beat = beatBuffer,
              let now = audioEngine.preciseNow else {
            // Transport stopped or no analysis — drop any pending clicks so
            // they don't fire after the song stops.
            if playerNode.isPlaying { playerNode.stop(); playerNode.play() }
            nextBeatToSchedule = Int.min
            return
        }

        let speed = max(0.001, audioEngine.speed)

        // Decide whether to flush the pending queue.
        let analysisChanged = analysisGeneration != lastSnapshotGeneration
        let transportChanged = audioEngine.transportGeneration != lastTransportGeneration
        let lastSpeed = max(0.001, lastSnapshotSpeed)
        let speedDelta = abs(speed - lastSpeed) / lastSpeed
        let speedChanged = speedDelta > Self.speedInvalidateThreshold

        if analysisChanged || transportChanged || speedChanged {
            playerNode.stop()
            playerNode.play()
            playerNode.volume = volume
            nextBeatToSchedule = Int.min
            lastSnapshotGeneration = analysisGeneration
            lastTransportGeneration = audioEngine.transportGeneration
            lastSnapshotSpeed = speed
        }

        let beatDurationSong: Float = 60.0 / bpm
        let currentSongTime = now.songTime
        let currentHostTime = now.hostTime

        // Earliest beat index that hasn't passed in song-time yet.
        let earliestK = Int(ceil(Double((currentSongTime - firstDownbeatTime) / beatDurationSong)))
        var k = max(nextBeatToSchedule == Int.min ? earliestK : nextBeatToSchedule, earliestK)

        // Click latency compensation: the song passes through timePitchNode,
        // clicks bypass it. To align at the speaker, delay each click by the
        // song's extra processing latency.
        let songExtraLatency = audioEngine.songExtraLatencySeconds
        let latencyNanos = UInt64(max(0, songExtraLatency) * 1_000_000_000)
        let latencyHostTicks = latencyNanos * UInt64(cachedTimebase.denom) / UInt64(cachedTimebase.numer)

        // Convert lookahead from wall-clock to song-time using the current speed.
        let songTimeLimit = currentSongTime + Float(Self.lookaheadSeconds) * speed

        while true {
            let beatTimeInSong = firstDownbeatTime + Float(k) * beatDurationSong
            if beatTimeInSong > songTimeLimit { break }

            let offsetSeconds = Double((beatTimeInSong - currentSongTime) / speed)
            if offsetSeconds < 0 { k += 1; continue }
            let offsetNanos = UInt64(offsetSeconds * 1_000_000_000)
            let offsetHostTicks = offsetNanos * UInt64(cachedTimebase.denom) / UInt64(cachedTimebase.numer)
            let clickHostTime = currentHostTime &+ offsetHostTicks &+ latencyHostTicks
            let avTime = AVAudioTime(hostTime: clickHostTime)

            let isDownbeat = ((k % beatsPerBar) + beatsPerBar) % beatsPerBar == 0
            let buffer = isDownbeat ? down : beat
            playerNode.scheduleBuffer(buffer, at: avTime, options: [], completionHandler: nil)
            k += 1
        }
        nextBeatToSchedule = k
    }
}
