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
            // Click scheduler reads speed on each refill tick — no notify needed.
        }
    }

    /// Bumps on every transport-affecting event (play/pause/stop/seek/playLoop).
    /// Lets clients (e.g. the click scheduler) detect "anything changed in the
    /// playback timeline" without subscribing to callbacks.
    private(set) var transportGeneration: Int = 0

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

    // Cached hot-path values read from `updateCurrentTime` at 60 Hz.
    private let cachedTimebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()
    private var cachedTimePitchLatency: Float = 0
    private var cachedVisualOffsetSeconds: Float = 0
    private var visualOffsetObserver: NSObjectProtocol?
    /// True only while playback is using the loop scheduler (lead-in +
    /// iteration chain). When false, `wrapWithinLoop` is a no-op so a click
    /// past loop end displays the actual position instead of being mapped
    /// back into the loop range.
    private var loopActiveForPlayback: Bool = false

    init() {
        setupAudioChain()
        cachedTimePitchLatency = Float(timePitchNode.latency)
        refreshVisualOffsetCache()
        // UserDefaults change notification — refresh the cache only when
        // the user moves the offset slider, not 60 times a second.
        visualOffsetObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshVisualOffsetCache() }
    }

    deinit {
        if let observer = visualOffsetObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refreshVisualOffsetCache() {
        let ms = UserDefaults.standard.object(forKey: "visualOffsetMs") as? Double
        cachedVisualOffsetSeconds = Float((ms ?? 0.0) / 1000.0)
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

    private func bumpTransport() {
        transportGeneration &+= 1
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

        // Reset to filename immediately so any synchronous reader can never
        // observe the previously-loaded file's title/artist.
        title = url.deletingPathExtension().lastPathComponent
        artist = ""
    }

    /// Reads embedded title/artist from the file's metadata, updates the
    /// engine's published `title`/`artist`, and returns the resolved values.
    /// Awaitable so callers (e.g. saving to the library) can avoid racing
    /// against the previous file's metadata.
    func loadEmbeddedMetadata(url: URL) async -> (title: String, artist: String) {
        let asset = AVURLAsset(url: url)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let resolvedTitle: String
        let resolvedArtist: String
        if let metadata = try? await asset.load(.commonMetadata) {
            let loadedTitle = try? await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle)
                .first?.load(.stringValue)
            let loadedArtist = try? await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist)
                .first?.load(.stringValue)
            resolvedTitle = (loadedTitle ?? nil) ?? fallbackTitle
            resolvedArtist = (loadedArtist ?? nil) ?? ""
        } else {
            resolvedTitle = fallbackTitle
            resolvedArtist = ""
        }
        await MainActor.run {
            self.title = resolvedTitle
            self.artist = resolvedArtist
        }
        return (resolvedTitle, resolvedArtist)
    }

    func play() {
        guard let file = audioFile else { return }
        guard state != .playing else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        seekGeneration += 1
        let gen = seekGeneration

        // Ableton-style armed loop: if a loop bracket is set and the playhead
        // is anywhere before its end, schedule a lead-in segment from the
        // current position to loop end, then chain full loop iterations. If
        // the playhead is past loop end, the loop is "behind" us — play
        // through normally.
        if let loop = activeLoop, currentTime < loop.endTime {
            scheduleLoopAware(from: currentTime, loop: loop, file: file, gen: gen)
        } else {
            schedulePlayback(from: currentTime, file: file)
        }
        playerNode.play()
        state = .playing
        startTimeTracking()
        bumpTransport()
        notifyTimingChanged()
    }

    func pause() {
        guard state == .playing else { return }
        updateCurrentTimeNow()
        playerNode.pause()
        state = .paused
        stopTimeTracking()
        bumpTransport()
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
        loopActiveForPlayback = false
        bumpTransport()
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
            play()   // bumps transport
        } else {
            bumpTransport()
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
        // Re-arm playback in place so the new bracket takes effect at sample
        // boundaries — without yanking the playhead. If the new loop is nil
        // or its end is behind us, fall through to a normal segment from the
        // current position (loop won't apply going forward, which matches
        // Ableton: a loop "behind" the playhead doesn't pull it back).
        guard isPlaying, let file = audioFile else { return }
        seekGeneration += 1
        let gen = seekGeneration
        playerNode.stop()
        if let loop, currentTime < loop.endTime {
            scheduleLoopAware(from: currentTime, loop: loop, file: file, gen: gen)
        } else {
            schedulePlayback(from: currentTime, file: file)
        }
        playerNode.play()
    }

    func playLoop() {
        guard let loop = activeLoop, let file = audioFile else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        seekGeneration += 1
        let loopGen = seekGeneration
        playerNode.stop()

        playbackOrigin = loop.startTime
        currentTime = loop.startTime
        loopActiveForPlayback = true

        scheduleLoopIteration(loop: loop, file: file, gen: loopGen)
        playerNode.play()
        state = .playing
        startTimeTracking()
        bumpTransport()
        notifyTimingChanged()
    }

    /// Schedules a "lead-in" segment from `time` to `loop.endTime`, then
    /// chains full loop iterations on completion. Used by both `play()` and
    /// `setLoop()` so that wherever the playhead currently is — before, inside,
    /// or partway through a loop — playback wraps cleanly at the loop end.
    private func scheduleLoopAware(from time: Float, loop: LoopRegion, file: AVAudioFile, gen: Int) {
        let sr = file.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(Double(time) * sr)
        let endFrame = AVAudioFramePosition(Double(loop.endTime) * sr)
        guard endFrame > startFrame else {
            schedulePlayback(from: time, file: file)
            return
        }
        let frameCount = AVAudioFrameCount(endFrame - startFrame)

        playbackOrigin = time
        loopActiveForPlayback = true

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil
        ) { [weak self] in
            Task { @MainActor in
                guard let self, self.seekGeneration == gen,
                      let active = self.activeLoop, active == loop else { return }
                self.scheduleLoopIteration(loop: loop, file: file, gen: gen)
            }
        }
    }

    private func scheduleLoopIteration(loop: LoopRegion, file: AVAudioFile, gen: Int) {
        let sr = file.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(Double(loop.startTime) * sr)
        let endFrame = AVAudioFramePosition(Double(loop.endTime) * sr)
        guard endFrame > startFrame else { return }
        let frameCount = AVAudioFrameCount(endFrame - startFrame)

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil
        ) { [weak self] in
            Task { @MainActor in
                guard let self, self.seekGeneration == gen,
                      let active = self.activeLoop, active == loop else { return }
                self.scheduleLoopIteration(loop: loop, file: file, gen: gen)
            }
        }
    }

    private func schedulePlayback(from time: Float, file: AVAudioFile) {
        playbackOrigin = time
        loopActiveForPlayback = false
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
        // Latency on AVAudioUnitTimePitch can shift with rate; refresh the
        // cached value so 60 Hz updateCurrentTime doesn't re-read it.
        cachedTimePitchLatency = Float(timePitchNode.latency)
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

    private func updateCurrentTime() {
        guard state == .playing else { return }
        guard let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let elapsed = Float(playerTime.sampleTime) / Float(playerTime.sampleRate)

        // Forward-project from the last render tick to NOW using the host clock,
        // so the playhead tracks the hardware clock continuously instead of
        // stair-stepping at 60 Hz.
        let now = mach_absolute_time()
        let hostDeltaTicks: UInt64 = now > nodeTime.hostTime ? (now &- nodeTime.hostTime) : 0
        let hostDeltaSeconds = Double(hostDeltaTicks) * Double(cachedTimebase.numer) / Double(cachedTimebase.denom) / 1_000_000_000.0

        // Compensate for timePitchNode's processing latency so the playhead
        // matches what the user is hearing, not the just-rendered sample
        // that's still working its way through the time-pitch unit.
        let songLatencySeconds = cachedTimePitchLatency * speed

        // Visual-only look-ahead: user-tunable extra offset on top of the
        // host-clock interpolation. Does NOT affect click scheduling.
        let raw = playbackOrigin + elapsed + Float(hostDeltaSeconds) * speed
            - songLatencySeconds + cachedVisualOffsetSeconds * speed
        let time = wrapWithinLoop(raw)
        if time >= 0 && time <= duration {
            currentTime = time
        }
    }

    private func updateCurrentTimeNow() {
        guard let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let elapsed = Float(playerTime.sampleTime) / Float(playerTime.sampleRate)
        let raw = playbackOrigin + elapsed
        let time = wrapWithinLoop(raw)
        if time >= 0 && time <= duration {
            currentTime = time
        }
    }

    /// When a loop is active, the playerNode's sampleTime grows monotonically
    /// across loop iterations (we chain segments without stopping). Map that
    /// continuously-advancing time back into [loop.startTime, loop.endTime).
    private func wrapWithinLoop(_ time: Float) -> Float {
        // Only wrap when playback is actually using the loop scheduler. If the
        // user clicked past loop end (or no loop is set), the playerNode is
        // playing through normally and the displayed time should reflect the
        // raw position — not be mapped back into the loop range.
        guard loopActiveForPlayback, let loop = activeLoop else { return time }
        let loopDur = loop.endTime - loop.startTime
        guard loopDur > 0, time >= loop.startTime else { return time }
        let offset = (time - loop.startTime).truncatingRemainder(dividingBy: loopDur)
        return loop.startTime + offset
    }
}
