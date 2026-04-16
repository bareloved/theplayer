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

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timePitchNode = AVAudioUnitTimePitch()
    private var audioFile: AVAudioFile?
    private var displayLink: Timer?
    private var isSeeking = false
    private var seekGeneration: Int = 0

    init() {
        setupAudioChain()
    }

    private func setupAudioChain() {
        engine.attach(playerNode)
        engine.attach(timePitchNode)
        engine.connect(playerNode, to: timePitchNode, format: nil)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: nil)
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
    }

    func pause() {
        guard state == .playing else { return }
        updateCurrentTimeNow()
        playerNode.pause()
        state = .paused
        stopTimeTracking()
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
    }

    private func schedulePlayback(from time: Float, file: AVAudioFile) {
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
        let time = Float(playerTime.sampleTime) / Float(playerTime.sampleRate)
        if time >= 0 && time <= duration {
            currentTime = time
        }
    }

    private func updateCurrentTimeNow() {
        guard let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let time = Float(playerTime.sampleTime) / Float(playerTime.sampleRate)
        if time >= 0 && time <= duration {
            currentTime = time
        }
    }
}
