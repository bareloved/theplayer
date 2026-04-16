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
        didSet { speed = min(max(speed, 0.25), 2.0); applyTimePitch() }
    }

    var pitch: Float = 0 {
        didSet { pitch = min(max(pitch, -12), 12); applyTimePitch() }
    }

    var isPlaying: Bool { state == .playing }

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timePitchNode = AVAudioUnitTimePitch()
    private var audioFile: AVAudioFile?
    private var displayLink: Timer?

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
        guard state == .loaded || state == .paused else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        let startFrame = AVAudioFramePosition(Double(currentTime) * file.fileFormat.sampleRate)
        let framesRemaining = AVAudioFrameCount(file.length - startFrame)
        guard framesRemaining > 0 else { return }

        file.framePosition = startFrame
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: framesRemaining,
            at: nil
        )
        playerNode.play()
        state = .playing
        startTimeTracking()
    }

    func pause() {
        guard state == .playing else { return }
        playerNode.pause()
        state = .paused
        stopTimeTracking()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        stopTimeTracking()
        if state != .empty {
            state = .loaded
        }
        currentTime = 0
    }

    func seek(to time: Float) {
        let wasPlaying = isPlaying
        let clampedTime = min(max(time, 0), duration)
        playerNode.stop()
        currentTime = clampedTime
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

    private func applyTimePitch() {
        timePitchNode.rate = speed
        timePitchNode.pitch = pitch * 100 // AVAudioUnitTimePitch uses cents (100 cents = 1 semitone)
    }

    private func startTimeTracking() {
        stopTimeTracking()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopTimeTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateCurrentTime() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let time = Float(playerTime.sampleTime) / Float(playerTime.sampleRate)
        if time >= 0 && time <= duration {
            currentTime = time
        }
    }
}
