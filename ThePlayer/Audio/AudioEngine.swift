import AVFoundation
import Darwin
import Observation

enum AudioEngineState: Equatable {
    case empty
    case loaded
    case playing
    case paused
}

@Observable
final class AudioEngine {
    private(set) var state: AudioEngineState = .empty
    private(set) var currentTime: Float = 0
    private(set) var duration: Float = 0
    private(set) var fileURL: URL?
    private(set) var title: String = ""
    private(set) var artist: String = ""
    private(set) var sampleRate: Double = 0

    var speed: Float = 1.0 {
        didSet {
            let clamped = min(max(speed, 0.25), 2.0)
            if clamped != speed { speed = clamped; return }
            applyTimePitch()
            notifyTimingChanged()
        }
    }

    var pitch: Float = 0 {
        didSet {
            let clamped = min(max(pitch, -12), 12)
            if clamped != pitch { pitch = clamped; return }
            applyTimePitch()
        }
    }

    var isPlaying: Bool { state == .playing }

    var activeLoop: LoopRegion?

    var onTimingChanged: (() -> Void)?

    /// Atomically sample the current song position and its host time from the audio graph.
    /// Used by the click scheduler to avoid drift from the 15 Hz currentTime timer.
    var preciseNow: (songTime: Float, hostTime: UInt64)? {
        guard let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return nil }
        let elapsed = Float(playerTime.sampleTime) / Float(playerTime.sampleRate)
        return (playbackOrigin + elapsed, nodeTime.hostTime)
    }

    /// Wall-clock seconds of processing delay the song incurs beyond the click path.
    /// The song passes through `timePitchNode`; clicks bypass it. To keep them in
    /// sync at the speaker, the click scheduler delays each click by this amount.
    var songExtraLatencySeconds: TimeInterval {
        TimeInterval(timePitchNode.latency)
    }

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timePitchNode = AVAudioUnitTimePitch()
    private var audioFile: AVAudioFile?
    private var displayLink: Timer?
    private var isSeeking = false
    private var seekGeneration: Int = 0
    private var playbackOrigin: Float = 0 // absolute time offset when playback was scheduled

    init() {
        setupAudioChain()
    }

    private func setupAudioChain() {
        engine.attach(playerNode)
        engine.attach(timePitchNode)
        engine.connect(playerNode, to: timePitchNode, format: nil)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: nil)
    }

    func attachSecondaryPlayer(_ node: AVAudioNode, format: AVAudioFormat? = nil) {
        if node.engine !== engine {
            engine.attach(node)
        }
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    private func notifyTimingChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.onTimingChanged?()
        }
    }

    func loadFile(url: URL) throws {
        stop()

        let file = try AVAudioFile(forReading: url)
        audioFile = file
        fileURL = url
        duration = Float(file.length) / Float(file.fileFormat.sampleRate)
        sampleRate = file.fileFormat.sampleRate
        currentTime = 0
        state = .loaded

        loadMetadata(url: url)
    }

    private func loadMetadata(url: URL) {
        let asset = AVURLAsset(url: url)
        Task {
            let metadata = try? await asset.load(.commonMetadata)
            guard let metadata else {
                await MainActor.run {
                    title = url.deletingPathExtension().lastPathComponent
                    artist = ""
                }
                return
            }
            let loadedTitle = try? await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle)
                .first?.load(.stringValue)
            let loadedArtist = try? await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist)
                .first?.load(.stringValue)
            await MainActor.run {
                title = loadedTitle ?? url.deletingPathExtension().lastPathComponent
                artist = loadedArtist ?? ""
            }
        }
    }

    func play() {
        guard let file = audioFile else { return }
        guard state != .playing else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        schedulePlayback(from: currentTime, file: file)
        playerNode.play()
        state = .playing
        startTimeTracking()
        notifyTimingChanged()
    }

    func pause() {
        guard state == .playing else { return }
        updateCurrentTimeNow()
        playerNode.pause()
        state = .paused
        stopTimeTracking()
        notifyTimingChanged()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func stop() {
        seekGeneration += 1
        playerNode.stop()
        engine.stop()
        stopTimeTracking()
        if state != .empty {
            state = .loaded
        }
        currentTime = 0
        notifyTimingChanged()
    }

    func seek(to time: Float) {
        guard audioFile != nil else { return }
        let wasPlaying = isPlaying

        seekGeneration += 1
        playerNode.stop()
        stopTimeTracking()

        currentTime = min(max(time, 0), duration)
        state = wasPlaying ? .loaded : (state == .empty ? .empty : .loaded)

        if wasPlaying {
            play()
        } else {
            notifyTimingChanged()
        }
    }

    func skipForward(seconds: Float = 5) {
        seek(to: currentTime + seconds)
    }

    func skipBackward(seconds: Float = 5) {
        seek(to: currentTime - seconds)
    }

    func setLoop(_ loop: LoopRegion?) {
        activeLoop = loop
        if let loop, isPlaying {
            if currentTime < loop.startTime || currentTime >= loop.endTime {
                seek(to: loop.startTime)
            }
        }
    }

    func playLoop() {
        guard let loop = activeLoop, let file = audioFile else { return }

        let gen = seekGeneration

        if !engine.isRunning {
            try? engine.start()
        }

        seekGeneration += 1
        let loopGen = seekGeneration
        playerNode.stop()

        let startFrame = AVAudioFramePosition(Double(loop.startTime) * file.fileFormat.sampleRate)
        let endFrame = AVAudioFramePosition(Double(loop.endTime) * file.fileFormat.sampleRate)
        let frameCount = AVAudioFrameCount(endFrame - startFrame)
        guard frameCount > 0 else { return }

        playbackOrigin = loop.startTime
        currentTime = loop.startTime

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil
        ) { [weak self] in
            Task { @MainActor in
                guard let self, self.seekGeneration == loopGen else { return }
                if self.activeLoop != nil {
                    self.playLoop()
                }
            }
        }
        playerNode.play()
        state = .playing
        startTimeTracking()
        notifyTimingChanged()
    }

    private func schedulePlayback(from time: Float, file: AVAudioFile) {
        playbackOrigin = time
        let startFrame = AVAudioFramePosition(Double(time) * file.fileFormat.sampleRate)
        let totalFrames = file.length
        guard startFrame < totalFrames else { return }
        let framesRemaining = AVAudioFrameCount(totalFrames - startFrame)

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: framesRemaining,
            at: nil
        )
    }

    private func applyTimePitch() {
        timePitchNode.rate = speed
        timePitchNode.pitch = pitch * 100
    }

    private func startTimeTracking() {
        stopTimeTracking()
        // 60 Hz so the visual playhead stays within one frame (~16 ms) of the
        // audio. 15 Hz caused an audible "hear before see" lag.
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopTimeTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Visual playhead time offset (seconds) applied to the reported currentTime.
    /// User-tunable via @AppStorage("visualOffsetMs") in ContentView.
    private var visualLookAheadSeconds: Float {
        let ms = UserDefaults.standard.object(forKey: "visualOffsetMs") as? Double
        return Float((ms ?? 0.0) / 1000.0)
    }

    private func updateCurrentTime() {
        guard state == .playing else { return }
        guard let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let elapsed = Float(playerTime.sampleTime) / Float(playerTime.sampleRate)

        // Forward-project from the last render tick to NOW using the host clock,
        // so the playhead tracks the hardware clock continuously instead of
        // stair-stepping at 60 Hz (which caused ~up-to-16ms visual lag behind
        // the click you hear).
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let now = mach_absolute_time()
        let hostDeltaTicks: UInt64 = now > nodeTime.hostTime ? (now &- nodeTime.hostTime) : 0
        let hostDeltaSeconds = Double(hostDeltaTicks) * Double(tb.numer) / Double(tb.denom) / 1_000_000_000.0

        // Compensate for timePitchNode's processing latency so the playhead
        // matches what the user is hearing, not the just-rendered sample
        // that's still working its way through the time-pitch unit.
        let songLatencySeconds = Float(timePitchNode.latency) * speed

        // Visual-only look-ahead: user-tunable extra offset on top of the
        // host-clock interpolation. Does NOT affect click scheduling
        // (which uses `preciseNow` and host-time math).
        let time = playbackOrigin + elapsed + Float(hostDeltaSeconds) * speed
            - songLatencySeconds + visualLookAheadSeconds * speed
        if time >= 0 && time <= duration {
            currentTime = time
        }
    }

    private func updateCurrentTimeNow() {
        guard let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let elapsed = Float(playerTime.sampleTime) / Float(playerTime.sampleRate)
        let time = playbackOrigin + elapsed
        if time >= 0 && time <= duration {
            currentTime = time
        }
    }
}
