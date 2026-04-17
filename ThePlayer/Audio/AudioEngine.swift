import AVFoundation
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
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
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
        let time = playbackOrigin + elapsed
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
