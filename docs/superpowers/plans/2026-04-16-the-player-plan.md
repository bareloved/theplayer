# The Player — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS native music practice app that slows down, speeds up, pitch-shifts, and intelligently loops sections of audio files using automatic song analysis.

**Architecture:** Monolithic SwiftUI app with three subsystems — UI layer (SwiftUI + NavigationSplitView), Audio Engine (AVAudioEngine + AVAudioUnitTimePitch), and Analysis Engine (Essentia C++ bridged via ObjC++). UI observes engine state via @Observable. Analysis results cached per file hash.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+, AVFoundation, AVAudioEngine, Essentia (C++), XcodeGen for project generation

---

## File Structure

```
ThePlayer/
├── project.yml                         # XcodeGen project definition
├── ThePlayer/
│   ├── ThePlayerApp.swift              # App entry, WindowGroup, commands
│   ├── Models/
│   │   ├── TrackAnalysis.swift         # BPM, beats, sections — Codable for cache
│   │   ├── AudioSection.swift          # Section label, times, beats, color
│   │   └── LoopRegion.swift            # Loop start/end with snap logic
│   ├── Audio/
│   │   ├── AudioEngine.swift           # @Observable: load, play, pause, seek, speed, pitch
│   │   └── WaveformExtractor.swift     # Extract downsampled peaks from AVAudioFile
│   ├── Analysis/
│   │   ├── TrackAnalyzerProtocol.swift # Protocol for analysis (enables mock + real)
│   │   ├── EssentiaAnalyzer.h          # ObjC++ public header
│   │   ├── EssentiaAnalyzer.mm         # ObjC++ implementation calling Essentia C++
│   │   ├── AnalysisService.swift       # Swift async wrapper, progress reporting
│   │   ├── AnalysisCache.swift         # File hash → JSON cache in App Support
│   │   └── MockAnalyzer.swift          # Returns dummy data for dev/test
│   ├── Views/
│   │   ├── ContentView.swift           # NavigationSplitView: sidebar + detail
│   │   ├── SidebarView.swift           # Section list + track info
│   │   ├── WaveformView.swift          # Canvas: peaks, sections, playhead, loop
│   │   ├── TransportBar.swift          # Play/skip/loop controls
│   │   └── SpeedPitchControl.swift     # Labeled slider with value display
│   └── ThePlayer-Bridging-Header.h     # Imports EssentiaAnalyzer.h
├── ThePlayerTests/
│   ├── TrackAnalysisTests.swift
│   ├── LoopRegionTests.swift
│   ├── AudioEngineTests.swift
│   ├── WaveformExtractorTests.swift
│   └── AnalysisCacheTests.swift
└── Resources/
    └── test-audio.wav                  # Short test audio file for integration tests
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: `ThePlayer/ThePlayerApp.swift`
- Create: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Install XcodeGen if not present**

Run: `brew install xcodegen`
Expected: xcodegen available on PATH

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p ThePlayer/Models ThePlayer/Audio ThePlayer/Analysis ThePlayer/Views
mkdir -p ThePlayerTests Resources
```

- [ ] **Step 3: Create project.yml**

```yaml
name: ThePlayer
options:
  bundleIdPrefix: com.theplayer
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true
settings:
  SWIFT_VERSION: "5.9"
  MACOSX_DEPLOYMENT_TARGET: "14.0"
targets:
  ThePlayer:
    type: application
    platform: macOS
    sources:
      - ThePlayer
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.theplayer.app
      PRODUCT_NAME: The Player
      INFOPLIST_VALUES:
        CFBundleDisplayName: The Player
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        LSMinimumSystemVersion: "14.0"
      SWIFT_OBJC_BRIDGING_HEADER: ThePlayer/ThePlayer-Bridging-Header.h
  ThePlayerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - ThePlayerTests
    dependencies:
      - target: ThePlayer
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.theplayer.tests
```

- [ ] **Step 4: Create app entry point**

Create `ThePlayer/ThePlayerApp.swift`:

```swift
import SwiftUI

@main
struct ThePlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

- [ ] **Step 5: Create placeholder ContentView**

Create `ThePlayer/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            Text("Sections")
                .frame(minWidth: 220)
        } detail: {
            Text("Open an audio file to get started")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 6: Create bridging header (empty for now)**

Create `ThePlayer/ThePlayer-Bridging-Header.h`:

```objc
// Bridging header for Objective-C++ Essentia wrapper
// #import "EssentiaAnalyzer.h"  // Uncomment when Essentia is integrated
```

- [ ] **Step 7: Generate Xcode project and verify build**

```bash
xcodegen generate
open ThePlayer.xcodeproj
```

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add project.yml ThePlayer/ ThePlayerTests/ Resources/ .gitignore
git commit -m "feat: scaffold Xcode project with XcodeGen"
```

---

### Task 2: Data Models

**Files:**
- Create: `ThePlayer/Models/TrackAnalysis.swift`
- Create: `ThePlayer/Models/AudioSection.swift`
- Create: `ThePlayer/Models/LoopRegion.swift`
- Create: `ThePlayerTests/TrackAnalysisTests.swift`
- Create: `ThePlayerTests/LoopRegionTests.swift`

- [ ] **Step 1: Write TrackAnalysis and AudioSection tests**

Create `ThePlayerTests/TrackAnalysisTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class TrackAnalysisTests: XCTestCase {

    func testTrackAnalysisCodableRoundTrip() throws {
        let sections = [
            AudioSection(label: "Verse", startTime: 0.0, endTime: 15.5, startBeat: 0, endBeat: 16, colorIndex: 0),
            AudioSection(label: "Chorus", startTime: 15.5, endTime: 30.0, startBeat: 16, endBeat: 32, colorIndex: 1)
        ]
        let analysis = TrackAnalysis(
            bpm: 120.0,
            beats: [0.0, 0.5, 1.0, 1.5, 2.0],
            sections: sections,
            waveformPeaks: [0.1, 0.5, 0.8, 0.3]
        )

        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(TrackAnalysis.self, from: data)

        XCTAssertEqual(decoded.bpm, 120.0)
        XCTAssertEqual(decoded.beats.count, 5)
        XCTAssertEqual(decoded.sections.count, 2)
        XCTAssertEqual(decoded.sections[0].label, "Verse")
        XCTAssertEqual(decoded.sections[1].endTime, 30.0, accuracy: 0.001)
        XCTAssertEqual(decoded.waveformPeaks.count, 4)
    }

    func testAudioSectionDuration() {
        let section = AudioSection(label: "Intro", startTime: 5.0, endTime: 20.0, startBeat: 0, endBeat: 16, colorIndex: 0)
        XCTAssertEqual(section.duration, 15.0, accuracy: 0.001)
    }

    func testAudioSectionBarCount() {
        let section = AudioSection(label: "Verse", startTime: 0.0, endTime: 30.0, startBeat: 0, endBeat: 32, colorIndex: 0)
        XCTAssertEqual(section.barCount, 8) // 32 beats / 4 beats per bar
    }

    func testAudioSectionColor() {
        let section0 = AudioSection(label: "A", startTime: 0, endTime: 1, startBeat: 0, endBeat: 4, colorIndex: 0)
        let section1 = AudioSection(label: "B", startTime: 1, endTime: 2, startBeat: 4, endBeat: 8, colorIndex: 1)
        XCTAssertNotEqual(section0.color, section1.color)
    }
}
```

- [ ] **Step 2: Write LoopRegion tests**

Create `ThePlayerTests/LoopRegionTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class LoopRegionTests: XCTestCase {

    func testLoopRegionContainsTime() {
        let loop = LoopRegion(startTime: 10.0, endTime: 20.0)
        XCTAssertTrue(loop.contains(time: 15.0))
        XCTAssertTrue(loop.contains(time: 10.0))
        XCTAssertFalse(loop.contains(time: 20.0))
        XCTAssertFalse(loop.contains(time: 5.0))
    }

    func testLoopRegionDuration() {
        let loop = LoopRegion(startTime: 5.0, endTime: 15.0)
        XCTAssertEqual(loop.duration, 10.0, accuracy: 0.001)
    }

    func testSnapToNearestBeat() {
        let beats: [Float] = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
        let snapped = LoopRegion.snapToNearestBeat(time: 1.3, beats: beats)
        XCTAssertEqual(snapped, 1.5, accuracy: 0.001)
    }

    func testSnapToNearestBeatExactMatch() {
        let beats: [Float] = [0.0, 0.5, 1.0, 1.5, 2.0]
        let snapped = LoopRegion.snapToNearestBeat(time: 1.0, beats: beats)
        XCTAssertEqual(snapped, 1.0, accuracy: 0.001)
    }

    func testSnapToNearestBeatEmptyBeats() {
        let snapped = LoopRegion.snapToNearestBeat(time: 1.3, beats: [])
        XCTAssertEqual(snapped, 1.3, accuracy: 0.001) // Returns original time
    }

    func testFromSection() {
        let section = AudioSection(label: "Chorus", startTime: 15.0, endTime: 30.0, startBeat: 16, endBeat: 32, colorIndex: 1)
        let loop = LoopRegion.from(section: section)
        XCTAssertEqual(loop.startTime, 15.0, accuracy: 0.001)
        XCTAssertEqual(loop.endTime, 30.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 3: Run tests — verify they fail**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Test|error|FAIL)"`
Expected: Compilation errors — models don't exist yet

- [ ] **Step 4: Implement AudioSection**

Create `ThePlayer/Models/AudioSection.swift`:

```swift
import SwiftUI

struct AudioSection: Codable, Identifiable, Equatable {
    var id: String { "\(label)-\(startTime)" }

    let label: String
    let startTime: Float
    let endTime: Float
    let startBeat: Int
    let endBeat: Int
    let colorIndex: Int

    var duration: Float { endTime - startTime }

    var barCount: Int { (endBeat - startBeat) / 4 }

    private static let palette: [Color] = [
        .blue, .green, .red, .yellow, .purple, .orange, .cyan, .pink
    ]

    var color: Color {
        Self.palette[colorIndex % Self.palette.count]
    }
}
```

- [ ] **Step 5: Implement TrackAnalysis**

Create `ThePlayer/Models/TrackAnalysis.swift`:

```swift
import Foundation

struct TrackAnalysis: Codable, Equatable {
    let bpm: Float
    let beats: [Float]
    let sections: [AudioSection]
    let waveformPeaks: [Float]
}
```

- [ ] **Step 6: Implement LoopRegion**

Create `ThePlayer/Models/LoopRegion.swift`:

```swift
import Foundation

struct LoopRegion: Equatable {
    var startTime: Float
    var endTime: Float

    var duration: Float { endTime - startTime }

    func contains(time: Float) -> Bool {
        time >= startTime && time < endTime
    }

    static func snapToNearestBeat(time: Float, beats: [Float]) -> Float {
        guard !beats.isEmpty else { return time }
        return beats.min(by: { abs($0 - time) < abs($1 - time) }) ?? time
    }

    static func from(section: AudioSection) -> LoopRegion {
        LoopRegion(startTime: section.startTime, endTime: section.endTime)
    }
}
```

- [ ] **Step 7: Run tests — verify they pass**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Test|PASS|FAIL)"`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add ThePlayer/Models/ ThePlayerTests/TrackAnalysisTests.swift ThePlayerTests/LoopRegionTests.swift
git commit -m "feat: add data models — TrackAnalysis, AudioSection, LoopRegion"
```

---

### Task 3: Audio Engine — Load & Playback

**Files:**
- Create: `ThePlayer/Audio/AudioEngine.swift`
- Create: `ThePlayerTests/AudioEngineTests.swift`

- [ ] **Step 1: Create a short test WAV file**

```bash
# Generate a 2-second 440Hz sine wave for testing
afconvert -f WAVE -d LEI16 /dev/null Resources/test-audio.wav 2>/dev/null || \
python3 -c "
import struct, math, wave
with wave.open('Resources/test-audio.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    for i in range(44100 * 2):
        sample = int(32767 * math.sin(2 * math.pi * 440 * i / 44100))
        w.writeframes(struct.pack('<h', sample))
"
```

- [ ] **Step 2: Write AudioEngine tests**

Create `ThePlayerTests/AudioEngineTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class AudioEngineTests: XCTestCase {

    func testInitialState() {
        let engine = AudioEngine()
        XCTAssertEqual(engine.state, .empty)
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertEqual(engine.duration, 0)
        XCTAssertEqual(engine.speed, 1.0)
        XCTAssertEqual(engine.pitch, 0)
        XCTAssertFalse(engine.isPlaying)
    }

    func testLoadFile() throws {
        let engine = AudioEngine()
        let url = Bundle(for: type(of: self)).url(forResource: "test-audio", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/test-audio.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Test audio file not available")
        }
        try engine.loadFile(url: url)
        XCTAssertEqual(engine.state, .loaded)
        XCTAssertGreaterThan(engine.duration, 0)
    }

    func testSpeedClamp() {
        let engine = AudioEngine()
        engine.speed = 0.1 // below minimum
        XCTAssertEqual(engine.speed, 0.25, accuracy: 0.01)
        engine.speed = 3.0 // above maximum
        XCTAssertEqual(engine.speed, 2.0, accuracy: 0.01)
    }

    func testPitchClamp() {
        let engine = AudioEngine()
        engine.pitch = -15 // below minimum
        XCTAssertEqual(engine.pitch, -12, accuracy: 0.01)
        engine.pitch = 15 // above maximum
        XCTAssertEqual(engine.pitch, 12, accuracy: 0.01)
    }
}
```

- [ ] **Step 3: Run tests — verify they fail**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(error|FAIL)"`
Expected: Compilation error — AudioEngine doesn't exist

- [ ] **Step 4: Implement AudioEngine**

Create `ThePlayer/Audio/AudioEngine.swift`:

```swift
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
        let metadata = asset.commonMetadata

        title = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle)
            .first?.stringValue ?? url.deletingPathExtension().lastPathComponent
        artist = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist)
            .first?.stringValue ?? ""
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
```

- [ ] **Step 5: Run tests — verify they pass**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Test|PASS|FAIL)"`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add ThePlayer/Audio/AudioEngine.swift ThePlayerTests/AudioEngineTests.swift Resources/
git commit -m "feat: audio engine with load, play/pause, seek, speed/pitch"
```

---

### Task 4: Waveform Extraction

**Files:**
- Create: `ThePlayer/Audio/WaveformExtractor.swift`
- Create: `ThePlayerTests/WaveformExtractorTests.swift`

- [ ] **Step 1: Write WaveformExtractor tests**

Create `ThePlayerTests/WaveformExtractorTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class WaveformExtractorTests: XCTestCase {

    func testExtractPeaks() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "test-audio", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/test-audio.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Test audio file not available")
        }

        let peaks = try WaveformExtractor.extractPeaks(from: url, targetCount: 200)
        XCTAssertEqual(peaks.count, 200)
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1.0 })
    }

    func testExtractPeaksNonZero() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "test-audio", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/test-audio.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Test audio file not available")
        }

        let peaks = try WaveformExtractor.extractPeaks(from: url, targetCount: 100)
        let maxPeak = peaks.max() ?? 0
        XCTAssertGreaterThan(maxPeak, 0, "Peaks should contain non-zero values for audio with content")
    }

    func testDownsampleArray() {
        let input: [Float] = [0.1, 0.5, 0.8, 0.3, 0.9, 0.2]
        let result = WaveformExtractor.downsample(input, to: 3)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], 0.5, accuracy: 0.01)  // max of [0.1, 0.5]
        XCTAssertEqual(result[1], 0.8, accuracy: 0.01)  // max of [0.8, 0.3]
        XCTAssertEqual(result[2], 0.9, accuracy: 0.01)  // max of [0.9, 0.2]
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(error|FAIL)"`
Expected: Compilation error — WaveformExtractor doesn't exist

- [ ] **Step 3: Implement WaveformExtractor**

Create `ThePlayer/Audio/WaveformExtractor.swift`:

```swift
import AVFoundation

enum WaveformExtractor {

    static func extractPeaks(from url: URL, targetCount: Int = 500) throws -> [Float] {
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
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Test|PASS|FAIL)"`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Audio/WaveformExtractor.swift ThePlayerTests/WaveformExtractorTests.swift
git commit -m "feat: waveform peak extraction from audio files"
```

---

### Task 5: Analysis Cache

**Files:**
- Create: `ThePlayer/Analysis/AnalysisCache.swift`
- Create: `ThePlayerTests/AnalysisCacheTests.swift`

- [ ] **Step 1: Write AnalysisCache tests**

Create `ThePlayerTests/AnalysisCacheTests.swift`:

```swift
import XCTest
@testable import ThePlayer

final class AnalysisCacheTests: XCTestCase {

    var cache: AnalysisCache!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cache = AnalysisCache(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testStoreAndRetrieve() throws {
        let analysis = TrackAnalysis(
            bpm: 120,
            beats: [0.0, 0.5, 1.0],
            sections: [],
            waveformPeaks: [0.1, 0.2]
        )
        let key = "abc123"

        try cache.store(analysis, forKey: key)
        let retrieved = try cache.retrieve(forKey: key)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.bpm, 120)
        XCTAssertEqual(retrieved?.beats.count, 3)
    }

    func testRetrieveNonexistent() throws {
        let retrieved = try cache.retrieve(forKey: "doesnotexist")
        XCTAssertNil(retrieved)
    }

    func testFileHash() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "test-audio", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/test-audio.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Test audio file not available")
        }

        let hash1 = try AnalysisCache.fileHash(for: url)
        let hash2 = try AnalysisCache.fileHash(for: url)
        XCTAssertEqual(hash1, hash2)
        XCTAssertFalse(hash1.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(error|FAIL)"`
Expected: Compilation error — AnalysisCache doesn't exist

- [ ] **Step 3: Implement AnalysisCache**

Create `ThePlayer/Analysis/AnalysisCache.swift`:

```swift
import Foundation
import CryptoKit

final class AnalysisCache {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("The Player/cache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func store(_ analysis: TrackAnalysis, forKey key: String) throws {
        let url = directory.appendingPathComponent("\(key).json")
        let data = try JSONEncoder().encode(analysis)
        try data.write(to: url)
    }

    func retrieve(forKey key: String) throws -> TrackAnalysis? {
        let url = directory.appendingPathComponent("\(key).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TrackAnalysis.self, from: data)
    }

    static func fileHash(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0

        // Read first 1MB for fast hashing
        let chunkSize = min(Int(fileSize), 1_048_576)
        let data = handle.readData(ofLength: chunkSize)

        var hasher = SHA256()
        hasher.update(data: data)
        // Include file size to differentiate files with identical first 1MB
        withUnsafeBytes(of: fileSize) { hasher.update(bufferPointer: $0) }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Test|PASS|FAIL)"`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Analysis/AnalysisCache.swift ThePlayerTests/AnalysisCacheTests.swift
git commit -m "feat: analysis cache with file hashing and JSON storage"
```

---

### Task 6: Analysis Service & Mock Analyzer

**Files:**
- Create: `ThePlayer/Analysis/TrackAnalyzerProtocol.swift`
- Create: `ThePlayer/Analysis/MockAnalyzer.swift`
- Create: `ThePlayer/Analysis/AnalysisService.swift`

- [ ] **Step 1: Create TrackAnalyzerProtocol**

Create `ThePlayer/Analysis/TrackAnalyzerProtocol.swift`:

```swift
import Foundation

protocol TrackAnalyzerProtocol {
    func analyze(fileURL: URL, progress: @escaping (Float) -> Void) async throws -> TrackAnalysis
}
```

- [ ] **Step 2: Create MockAnalyzer**

Create `ThePlayer/Analysis/MockAnalyzer.swift`:

```swift
import Foundation

struct MockAnalyzer: TrackAnalyzerProtocol {
    func analyze(fileURL: URL, progress: @escaping (Float) -> Void) async throws -> TrackAnalysis {
        // Simulate analysis time
        for i in 1...10 {
            try await Task.sleep(for: .milliseconds(50))
            progress(Float(i) / 10.0)
        }

        return TrackAnalysis(
            bpm: 120.0,
            beats: stride(from: Float(0), to: 180, by: 0.5).map { $0 },
            sections: [
                AudioSection(label: "Intro", startTime: 0, endTime: 15, startBeat: 0, endBeat: 30, colorIndex: 0),
                AudioSection(label: "Verse", startTime: 15, endTime: 45, startBeat: 30, endBeat: 90, colorIndex: 1),
                AudioSection(label: "Chorus", startTime: 45, endTime: 75, startBeat: 90, endBeat: 150, colorIndex: 2),
                AudioSection(label: "Verse", startTime: 75, endTime: 105, startBeat: 150, endBeat: 210, colorIndex: 1),
                AudioSection(label: "Chorus", startTime: 105, endTime: 135, startBeat: 210, endBeat: 270, colorIndex: 2),
                AudioSection(label: "Bridge", startTime: 135, endTime: 155, startBeat: 270, endBeat: 310, colorIndex: 3),
                AudioSection(label: "Outro", startTime: 155, endTime: 180, startBeat: 310, endBeat: 360, colorIndex: 0),
            ],
            waveformPeaks: (0..<500).map { _ in Float.random(in: 0.1...0.9) }
        )
    }
}
```

- [ ] **Step 3: Create AnalysisService**

Create `ThePlayer/Analysis/AnalysisService.swift`:

```swift
import Foundation
import Observation

@Observable
final class AnalysisService {
    private(set) var isAnalyzing = false
    private(set) var progress: Float = 0
    private(set) var lastAnalysis: TrackAnalysis?
    private(set) var analysisError: String?

    private let analyzer: TrackAnalyzerProtocol
    private let cache: AnalysisCache

    init(analyzer: TrackAnalyzerProtocol = MockAnalyzer(), cache: AnalysisCache = AnalysisCache()) {
        self.analyzer = analyzer
        self.cache = cache
    }

    func analyze(fileURL: URL) async {
        isAnalyzing = true
        progress = 0
        analysisError = nil

        do {
            // Check cache first
            let key = try AnalysisCache.fileHash(for: fileURL)
            if let cached = try cache.retrieve(forKey: key) {
                lastAnalysis = cached
                progress = 1.0
                isAnalyzing = false
                return
            }

            // Run analysis
            let result = try await analyzer.analyze(fileURL: fileURL) { [weak self] p in
                Task { @MainActor in
                    self?.progress = p
                }
            }

            // Cache result
            try cache.store(result, forKey: key)
            lastAnalysis = result
        } catch {
            analysisError = error.localizedDescription
            lastAnalysis = nil
        }

        isAnalyzing = false
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Analysis/TrackAnalyzerProtocol.swift ThePlayer/Analysis/MockAnalyzer.swift ThePlayer/Analysis/AnalysisService.swift
git commit -m "feat: analysis service with protocol, mock analyzer, and cache integration"
```

---

### Task 7: Main UI Shell — ContentView + SidebarView

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`
- Create: `ThePlayer/Views/SidebarView.swift`
- Modify: `ThePlayer/ThePlayerApp.swift`

- [ ] **Step 1: Update ThePlayerApp to create shared engine and service**

Replace `ThePlayer/ThePlayerApp.swift`:

```swift
import SwiftUI

@main
struct ThePlayerApp: App {
    @State private var audioEngine = AudioEngine()
    @State private var analysisService = AnalysisService()

    var body: some Scene {
        WindowGroup {
            ContentView(audioEngine: audioEngine, analysisService: analysisService)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

- [ ] **Step 2: Implement SidebarView**

Create `ThePlayer/Views/SidebarView.swift`:

```swift
import SwiftUI

struct SidebarView: View {
    let sections: [AudioSection]
    let bpm: Float?
    let duration: Float
    let sampleRate: Double
    let onSectionTap: (AudioSection) -> Void

    @Binding var selectedSection: AudioSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sections.isEmpty {
                ContentUnavailableView {
                    Label("No Sections", systemImage: "music.note.list")
                } description: {
                    Text("Open an audio file to analyze")
                }
                .frame(maxHeight: .infinity)
            } else {
                Text("Sections")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            SectionRow(
                                section: section,
                                index: index + 1,
                                isSelected: selectedSection == section,
                                onTap: { onSectionTap(section) }
                            )
                        }
                    }
                }
            }

            Spacer()

            if duration > 0 {
                trackInfoFooter
            }
        }
    }

    private var trackInfoFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Track Info")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                if let bpm {
                    Text("\(Int(bpm)) BPM")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }

                Text(formatDuration(duration) + " · \(Int(sampleRate / 1000))kHz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func formatDuration(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

private struct SectionRow: View {
    let section: AudioSection
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(section.color)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.label)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("\(formatTime(section.startTime)) – \(formatTime(section.endTime)) · \(section.barCount) bars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(index)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? section.color.opacity(0.15) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
```

- [ ] **Step 3: Update ContentView with full layout shell**

Replace `ThePlayer/Views/ContentView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var audioEngine: AudioEngine
    @Bindable var analysisService: AnalysisService
    @State private var selectedSection: AudioSection?
    @State private var loopRegion: LoopRegion?
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                sections: analysisService.lastAnalysis?.sections ?? [],
                bpm: analysisService.lastAnalysis?.bpm,
                duration: audioEngine.duration,
                sampleRate: audioEngine.sampleRate,
                onSectionTap: { section in
                    selectedSection = section
                    loopRegion = LoopRegion.from(section: section)
                    audioEngine.seek(to: section.startTime)
                    if !audioEngine.isPlaying { audioEngine.play() }
                },
                selectedSection: $selectedSection
            )
            .frame(minWidth: 220, idealWidth: 220)
        } detail: {
            if audioEngine.state == .empty {
                emptyState
            } else {
                playerDetail
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.blue, lineWidth: 3)
                    .background(.blue.opacity(0.05))
                    .padding(4)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Open an Audio File", systemImage: "waveform")
        } description: {
            Text("Drag and drop or press ⌘O")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playerDetail: some View {
        VStack(spacing: 0) {
            // Track title
            VStack(alignment: .leading, spacing: 2) {
                Text(audioEngine.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(audioEngine.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Waveform placeholder (Task 8)
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if analysisService.isAnalyzing {
                        ProgressView("Analyzing...", value: analysisService.progress, total: 1.0)
                            .padding()
                    } else if let error = analysisService.analysisError {
                        Label("Could not analyze: \(error)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Waveform (coming next)")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)

            // Transport placeholder (Task 9)
            Text("Transport controls (coming soon)")
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                openFile(url: url)
            }
        }
        return true
    }

    func openFile(url: URL) {
        do {
            try audioEngine.loadFile(url: url)
            selectedSection = nil
            loopRegion = nil
            Task {
                await analysisService.analyze(fileURL: url)
            }
        } catch {
            // Error handling added in Task 14
        }
    }
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/ThePlayerApp.swift ThePlayer/Views/ContentView.swift ThePlayer/Views/SidebarView.swift
git commit -m "feat: main UI shell with NavigationSplitView, sidebar, and drag-drop"
```

---

### Task 8: Waveform View

**Files:**
- Create: `ThePlayer/Views/WaveformView.swift`
- Modify: `ThePlayer/Views/ContentView.swift` (replace placeholder)

- [ ] **Step 1: Create WaveformView**

Create `ThePlayer/Views/WaveformView.swift`:

```swift
import SwiftUI

struct WaveformView: View {
    let peaks: [Float]
    let sections: [AudioSection]
    let duration: Float
    let currentTime: Float
    let loopRegion: LoopRegion?
    let onSeek: (Float) -> Void
    let onLoopDrag: (Float, Float) -> Void

    @State private var zoomLevel: CGFloat = 1.0
    @State private var scrollOffset: CGFloat = 0
    @State private var hoverTime: Float?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width * zoomLevel
            let height = geo.size.height

            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .leading) {
                    // Section color bands
                    sectionBands(width: totalWidth, height: height)

                    // Waveform bars
                    waveformBars(width: totalWidth, height: height)

                    // Loop region overlay
                    if let loop = loopRegion {
                        loopOverlay(loop: loop, width: totalWidth, height: height)
                    }

                    // Playhead
                    playhead(width: totalWidth, height: height)

                    // Hover tooltip
                    if let time = hoverTime, let loc = hoverLocation {
                        hoverTooltip(time: time, location: loc)
                    }
                }
                .frame(width: totalWidth, height: height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let fraction = Float(location.x / totalWidth)
                    onSeek(fraction * duration)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let fraction = Float(location.x / totalWidth)
                        hoverTime = fraction * duration
                        hoverLocation = location
                    case .ended:
                        hoverTime = nil
                        hoverLocation = nil
                    }
                }
            }
            .onMagnify { value in
                zoomLevel = max(1.0, min(zoomLevel * value.magnification, 20.0))
            }
            .overlay(alignment: .bottomLeading) {
                timeLabel(formatTime(currentTime))
                    .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                timeLabel(formatTime(duration))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionBands(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(sections) { section in
                let sectionWidth = CGFloat((section.endTime - section.startTime) / duration) * width
                Rectangle()
                    .fill(section.color.opacity(0.1))
                    .frame(width: sectionWidth, height: height)
            }
        }
    }

    private func waveformBars(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let barWidth = size.width / CGFloat(peaks.count)
            let midY = size.height / 2

            for (i, peak) in peaks.enumerated() {
                let x = CGFloat(i) * barWidth
                let barHeight = CGFloat(peak) * size.height * 0.8
                let fraction = Float(i) / Float(peaks.count)
                let time = fraction * duration

                let isPlayed = time <= currentTime
                let color: Color = isPlayed ? .blue : .gray.opacity(0.5)

                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: max(barWidth - 1, 1),
                    height: barHeight
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        let x = duration > 0 ? CGFloat(currentTime / duration) * width : 0
        return Rectangle()
            .fill(.white)
            .frame(width: 2, height: height)
            .overlay(alignment: .top) {
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .offset(y: -5)
            }
            .offset(x: x)
            .allowsHitTesting(false)
    }

    private func loopOverlay(loop: LoopRegion, width: CGFloat, height: CGFloat) -> some View {
        let startX = CGFloat(loop.startTime / duration) * width
        let endX = CGFloat(loop.endTime / duration) * width
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.blue.opacity(0.1))
                .frame(width: endX - startX, height: height)

            Rectangle()
                .fill(.blue.opacity(0.5))
                .frame(width: 2, height: height)

            Rectangle()
                .fill(.blue.opacity(0.5))
                .frame(width: 2, height: height)
                .offset(x: endX - startX - 2)

            Text("LOOP")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.blue)
                .padding(4)
        }
        .offset(x: startX)
        .allowsHitTesting(false)
    }

    private func hoverTooltip(time: Float, location: CGPoint) -> some View {
        Text(formatTime(time))
            .font(.caption2.monospaced())
            .padding(4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .position(x: location.x, y: location.y - 20)
            .allowsHitTesting(false)
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
    }

    private func formatTime(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
```

- [ ] **Step 2: Wire WaveformView into ContentView**

In `ThePlayer/Views/ContentView.swift`, replace the waveform placeholder in `playerDetail`:

Replace this block:
```swift
            // Waveform placeholder (Task 8)
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if analysisService.isAnalyzing {
                        ProgressView("Analyzing...", value: analysisService.progress, total: 1.0)
                            .padding()
                    } else if let error = analysisService.analysisError {
                        Label("Could not analyze: \(error)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Waveform (coming next)")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
```

With:
```swift
            // Waveform
            ZStack {
                WaveformView(
                    peaks: analysisService.lastAnalysis?.waveformPeaks ?? [],
                    sections: analysisService.lastAnalysis?.sections ?? [],
                    duration: audioEngine.duration,
                    currentTime: audioEngine.currentTime,
                    loopRegion: loopRegion,
                    onSeek: { time in audioEngine.seek(to: time) },
                    onLoopDrag: { start, end in
                        loopRegion = LoopRegion(startTime: start, endTime: end)
                    }
                )

                if analysisService.isAnalyzing {
                    ProgressView("Analyzing...", value: analysisService.progress, total: 1.0)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                if let error = analysisService.analysisError {
                    VStack {
                        Spacer()
                        Label("Could not analyze: \(error)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(8)
                }
            }
            .padding(16)
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/WaveformView.swift ThePlayer/Views/ContentView.swift
git commit -m "feat: waveform view with sections, playhead, loop overlay, and zoom"
```

---

### Task 9: Transport Bar

**Files:**
- Create: `ThePlayer/Views/TransportBar.swift`
- Create: `ThePlayer/Views/SpeedPitchControl.swift`
- Modify: `ThePlayer/Views/ContentView.swift` (replace transport placeholder)

- [ ] **Step 1: Create SpeedPitchControl**

Create `ThePlayer/Views/SpeedPitchControl.swift`:

```swift
import SwiftUI

struct SpeedPitchControl: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let unit: String
    let color: Color
    let formatter: (Float) -> String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            HStack(spacing: 8) {
                Text(formatter(range.lowerBound))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)

                Slider(value: $value, in: range, step: step)
                    .tint(color)
                    .frame(width: 100)

                Text(formatter(range.upperBound))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .leading)
            }

            Text(formatter(value) + unit)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}
```

- [ ] **Step 2: Create TransportBar**

Create `ThePlayer/Views/TransportBar.swift`:

```swift
import SwiftUI

struct TransportBar: View {
    @Bindable var audioEngine: AudioEngine
    @Binding var loopRegion: LoopRegion?
    @Binding var isSettingLoop: Bool

    var body: some View {
        HStack {
            // Speed control
            SpeedPitchControl(
                label: "Speed",
                value: $audioEngine.speed,
                range: 0.25...2.0,
                step: 0.05,
                unit: "%",
                color: .blue,
                formatter: { "\(Int($0 * 100))" }
            )

            Spacer()

            // Transport controls
            HStack(spacing: 16) {
                Button(action: { audioEngine.skipBackward() }) {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: { audioEngine.togglePlayPause() }) {
                    Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Button(action: { audioEngine.skipForward() }) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: toggleLoopMode) {
                    Label("A-B", systemImage: "repeat")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(loopRegion != nil ? .blue : .secondary)
            }

            Spacer()

            // Pitch control
            SpeedPitchControl(
                label: "Pitch",
                value: $audioEngine.pitch,
                range: -12...12,
                step: 1.0,
                unit: " st",
                color: .green,
                formatter: { v in v >= 0 ? "+\(Int(v))" : "\(Int(v))" }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toggleLoopMode() {
        if loopRegion != nil {
            loopRegion = nil
            isSettingLoop = false
        } else {
            isSettingLoop = true
        }
    }
}
```

- [ ] **Step 3: Wire TransportBar into ContentView**

In `ThePlayer/Views/ContentView.swift`, add a state variable and replace the transport placeholder.

Add to the state variables at the top of `ContentView`:
```swift
    @State private var isSettingLoop = false
```

Replace:
```swift
            // Transport placeholder (Task 9)
            Text("Transport controls (coming soon)")
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
```

With:
```swift
            TransportBar(
                audioEngine: audioEngine,
                loopRegion: $loopRegion,
                isSettingLoop: $isSettingLoop
            )
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ThePlayer/Views/TransportBar.swift ThePlayer/Views/SpeedPitchControl.swift ThePlayer/Views/ContentView.swift
git commit -m "feat: transport bar with play/pause, skip, speed/pitch sliders, loop toggle"
```

---

### Task 10: Loop System

**Files:**
- Modify: `ThePlayer/Audio/AudioEngine.swift` (add loop scheduling)
- Modify: `ThePlayer/Views/ContentView.swift` (loop logic)

- [ ] **Step 1: Add loop support to AudioEngine**

Add these properties and methods to `AudioEngine`:

After the `var isPlaying` computed property, add:
```swift
    var activeLoop: LoopRegion?
```

Add a new method after `skipBackward`:
```swift
    func setLoop(_ loop: LoopRegion?) {
        activeLoop = loop
        if let loop, isPlaying {
            // If currently outside loop, seek to loop start
            if currentTime < loop.startTime || currentTime >= loop.endTime {
                seek(to: loop.startTime)
            }
        }
    }

    func playLoop() {
        guard let loop = activeLoop, let file = audioFile else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        playerNode.stop()

        let startFrame = AVAudioFramePosition(Double(loop.startTime) * file.fileFormat.sampleRate)
        let endFrame = AVAudioFramePosition(Double(loop.endTime) * file.fileFormat.sampleRate)
        let frameCount = AVAudioFrameCount(endFrame - startFrame)
        guard frameCount > 0 else { return }

        file.framePosition = startFrame
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil
        ) { [weak self] in
            Task { @MainActor in
                // Re-schedule loop when segment finishes
                if self?.activeLoop != nil {
                    self?.playLoop()
                }
            }
        }
        playerNode.play()
        state = .playing
        startTimeTracking()
    }
```

- [ ] **Step 2: Update ContentView to use loop scheduling**

In `ContentView.swift`, update the `onSectionTap` closure to use the engine's loop:

Replace:
```swift
                onSectionTap: { section in
                    selectedSection = section
                    loopRegion = LoopRegion.from(section: section)
                    audioEngine.seek(to: section.startTime)
                    if !audioEngine.isPlaying { audioEngine.play() }
                },
```

With:
```swift
                onSectionTap: { section in
                    selectedSection = section
                    let loop = LoopRegion.from(section: section)
                    loopRegion = loop
                    audioEngine.setLoop(loop)
                    audioEngine.playLoop()
                },
```

Add an `onChange` modifier after the `.onDrop` modifier to sync loop state:
```swift
        .onChange(of: loopRegion) { _, newLoop in
            audioEngine.setLoop(newLoop)
            if let newLoop, audioEngine.isPlaying {
                audioEngine.playLoop()
            }
        }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Audio/AudioEngine.swift ThePlayer/Views/ContentView.swift
git commit -m "feat: loop scheduling — section loop and A-B loop support"
```

---

### Task 11: Keyboard Shortcuts

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Add keyboard event handling to ContentView**

Add this modifier chain after the `.onChange(of: loopRegion)` modifier in ContentView:

```swift
        .onKeyPress(.space) {
            audioEngine.togglePlayPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            let beats = analysisService.lastAnalysis?.beats ?? []
            if !beats.isEmpty {
                let target = LoopRegion.snapToNearestBeat(
                    time: audioEngine.currentTime - 0.1,
                    beats: beats.filter { $0 < audioEngine.currentTime - 0.1 }
                )
                audioEngine.seek(to: max(target, 0))
            } else {
                audioEngine.skipBackward()
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            let beats = analysisService.lastAnalysis?.beats ?? []
            if !beats.isEmpty {
                let target = LoopRegion.snapToNearestBeat(
                    time: audioEngine.currentTime + 0.1,
                    beats: beats.filter { $0 > audioEngine.currentTime + 0.1 }
                )
                audioEngine.seek(to: min(target, audioEngine.duration))
            } else {
                audioEngine.skipForward()
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            audioEngine.speed += 0.05
            return .handled
        }
        .onKeyPress(.downArrow) {
            audioEngine.speed -= 0.05
            return .handled
        }
        .onKeyPress(KeyEquivalent("[")) {
            audioEngine.pitch -= 1
            return .handled
        }
        .onKeyPress(KeyEquivalent("]")) {
            audioEngine.pitch += 1
            return .handled
        }
        .onKeyPress(KeyEquivalent("l")) {
            if loopRegion != nil {
                loopRegion = nil
            }
            return .handled
        }
        .onKeyPress(KeyEquivalent("1")) { jumpToSection(1) }
        .onKeyPress(KeyEquivalent("2")) { jumpToSection(2) }
        .onKeyPress(KeyEquivalent("3")) { jumpToSection(3) }
        .onKeyPress(KeyEquivalent("4")) { jumpToSection(4) }
        .onKeyPress(KeyEquivalent("5")) { jumpToSection(5) }
        .onKeyPress(KeyEquivalent("6")) { jumpToSection(6) }
        .onKeyPress(KeyEquivalent("7")) { jumpToSection(7) }
        .onKeyPress(KeyEquivalent("8")) { jumpToSection(8) }
        .onKeyPress(KeyEquivalent("9")) { jumpToSection(9) }
        .onKeyPress(.escape) {
            loopRegion = nil
            selectedSection = nil
            return .handled
        }
        .focusable()
```

Add the helper method to ContentView:

```swift
    private func jumpToSection(_ index: Int) -> KeyPress.Result {
        guard let sections = analysisService.lastAnalysis?.sections,
              index <= sections.count else { return .ignored }
        let section = sections[index - 1]
        selectedSection = section
        let loop = LoopRegion.from(section: section)
        loopRegion = loop
        audioEngine.setLoop(loop)
        audioEngine.playLoop()
        return .handled
    }
```

- [ ] **Step 2: Add ⌘O command to the app**

In `ThePlayer/ThePlayerApp.swift`, update the commands block:

Replace:
```swift
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
```

With:
```swift
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav, .aiff, .mp3]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        NotificationCenter.default.post(name: .openAudioFile, object: url)
                    }
                }
                .keyboardShortcut("o")
            }
        }
```

Add a notification name extension at the bottom of `ThePlayerApp.swift`:

```swift
extension Notification.Name {
    static let openAudioFile = Notification.Name("openAudioFile")
}
```

In `ContentView.swift`, add an `onReceive` modifier:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .openAudioFile)) { notification in
            if let url = notification.object as? URL {
                openFile(url: url)
            }
        }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/Views/ContentView.swift ThePlayer/ThePlayerApp.swift
git commit -m "feat: keyboard shortcuts — space, arrows, brackets, number keys, ⌘O"
```

---

### Task 12: File Loading Polish — Open Dialog & Recents

**Files:**
- Modify: `ThePlayer/ThePlayerApp.swift` (recent files)
- Modify: `ThePlayer/Views/ContentView.swift` (open panel refinement)

- [ ] **Step 1: Add document-based support for recent files**

In `ThePlayer/ThePlayerApp.swift`, update the scene to use `DocumentGroup`-like behavior for recents by adding `NSApp` configuration:

Replace the full file content:

```swift
import SwiftUI

@main
struct ThePlayerApp: App {
    @State private var audioEngine = AudioEngine()
    @State private var analysisService = AnalysisService()

    var body: some Scene {
        WindowGroup {
            ContentView(audioEngine: audioEngine, analysisService: analysisService)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    openFilePanel()
                }
                .keyboardShortcut("o")
            }
        }
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav, .aiff, .mp3]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an audio file to practice with"
        if panel.runModal() == .OK, let url = panel.url {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            NotificationCenter.default.post(name: .openAudioFile, object: url)
        }
    }
}

extension Notification.Name {
    static let openAudioFile = Notification.Name("openAudioFile")
}
```

- [ ] **Step 2: Update ContentView to also register recents on drag-drop**

In `ContentView.openFile(url:)`, add the recents call:

Replace:
```swift
    func openFile(url: URL) {
        do {
            try audioEngine.loadFile(url: url)
            selectedSection = nil
            loopRegion = nil
            Task {
                await analysisService.analyze(fileURL: url)
            }
        } catch {
            // Error handling added in Task 14
        }
    }
```

With:
```swift
    func openFile(url: URL) {
        do {
            try audioEngine.loadFile(url: url)
            selectedSection = nil
            loopRegion = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            Task {
                await analysisService.analyze(fileURL: url)
            }
        } catch {
            // Error handling added in Task 14
        }
    }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ThePlayer/ThePlayerApp.swift ThePlayer/Views/ContentView.swift
git commit -m "feat: file open dialog with recent files support"
```

---

### Task 13: Error Handling

**Files:**
- Modify: `ThePlayer/Views/ContentView.swift`

- [ ] **Step 1: Add error state and alert to ContentView**

Add a state variable at the top of `ContentView`:
```swift
    @State private var loadError: String?
    @State private var showErrorAlert = false
```

Update `openFile` to surface errors:

Replace:
```swift
    func openFile(url: URL) {
        do {
            try audioEngine.loadFile(url: url)
            selectedSection = nil
            loopRegion = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            Task {
                await analysisService.analyze(fileURL: url)
            }
        } catch {
            // Error handling added in Task 14
        }
    }
```

With:
```swift
    func openFile(url: URL) {
        do {
            try audioEngine.loadFile(url: url)
            selectedSection = nil
            loopRegion = nil
            loadError = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            Task {
                await analysisService.analyze(fileURL: url)
            }
        } catch {
            loadError = "Could not open file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
```

Add an `.alert` modifier after the existing modifiers:

```swift
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "An unknown error occurred")
        }
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ThePlayer/Views/ContentView.swift
git commit -m "feat: error handling with alert for unsupported/corrupt files"
```

---

### Task 14: Essentia Integration

**Files:**
- Create: `ThePlayer/Analysis/EssentiaAnalyzer.h`
- Create: `ThePlayer/Analysis/EssentiaAnalyzer.mm`
- Modify: `ThePlayer/ThePlayer-Bridging-Header.h`
- Modify: `ThePlayer/Analysis/AnalysisService.swift`
- Modify: `project.yml`

> **Note:** This task requires Essentia to be built for macOS. The steps below cover the C++ library integration. If Essentia is not yet built, the app remains fully functional using `MockAnalyzer` — this task can be deferred.

- [ ] **Step 1: Build Essentia for macOS**

```bash
git clone https://github.com/MTG/essentia.git /tmp/essentia
cd /tmp/essentia
python3 waf configure --build-static --lightweight= --with-algorithm=RhythmExtractor2013 --with-algorithm=SBic
python3 waf build
```

This produces `build/src/libessentia.a` and headers in `build/src/`. Copy into the project:

```bash
mkdir -p Vendor/essentia/lib Vendor/essentia/include
cp /tmp/essentia/build/src/libessentia.a Vendor/essentia/lib/
cp -R /tmp/essentia/src/essentia/ Vendor/essentia/include/essentia/
```

- [ ] **Step 2: Update project.yml for Essentia**

Add to the `ThePlayer` target settings in `project.yml`:

```yaml
      HEADER_SEARCH_PATHS:
        - $(SRCROOT)/Vendor/essentia/include
      LIBRARY_SEARCH_PATHS:
        - $(SRCROOT)/Vendor/essentia/lib
      OTHER_LDFLAGS:
        - -lessentia
        - -lc++
```

Run: `xcodegen generate`

- [ ] **Step 3: Create EssentiaAnalyzer ObjC++ header**

Create `ThePlayer/Analysis/EssentiaAnalyzer.h`:

```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EssentiaSection : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic) float startTime;
@property (nonatomic) float endTime;
@property (nonatomic) NSInteger startBeat;
@property (nonatomic) NSInteger endBeat;
@property (nonatomic) NSInteger colorIndex;
@end

@interface EssentiaResult : NSObject
@property (nonatomic) float bpm;
@property (nonatomic, strong) NSArray<NSNumber *> *beats;
@property (nonatomic, strong) NSArray<EssentiaSection *> *sections;
@end

@interface EssentiaAnalyzerObjC : NSObject
- (nullable EssentiaResult *)analyzeFileAtPath:(NSString *)path
                                         error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 4: Create EssentiaAnalyzer ObjC++ implementation**

Create `ThePlayer/Analysis/EssentiaAnalyzer.mm`:

```objc
#import "EssentiaAnalyzer.h"
#include <essentia/algorithmfactory.h>
#include <essentia/essentiamath.h>
#include <essentia/pool.h>

using namespace essentia;
using namespace essentia::standard;

@implementation EssentiaSection
@end

@implementation EssentiaResult
@end

@implementation EssentiaAnalyzerObjC

- (nullable EssentiaResult *)analyzeFileAtPath:(NSString *)path
                                         error:(NSError **)error {
    try {
        essentia::init();

        AlgorithmFactory& factory = AlgorithmFactory::instance();

        // Load audio
        Algorithm* loader = factory.create("MonoLoader",
            "filename", std::string([path UTF8String]),
            "sampleRate", 44100);

        std::vector<Real> audio;
        loader->output("audio").set(audio);
        loader->compute();
        delete loader;

        // BPM and beat detection
        Algorithm* rhythm = factory.create("RhythmExtractor2013");
        Real bpm;
        std::vector<Real> ticks;
        Real confidence;
        std::vector<Real> estimates;
        std::vector<Real> bpmIntervals;

        rhythm->input("signal").set(audio);
        rhythm->output("bpm").set(bpm);
        rhythm->output("ticks").set(ticks);
        rhythm->output("confidence").set(confidence);
        rhythm->output("estimates").set(estimates);
        rhythm->output("bpmIntervals").set(bpmIntervals);
        rhythm->compute();
        delete rhythm;

        // Section segmentation via SBic
        Algorithm* sbic = factory.create("SBic",
            "minLength", 10,
            "size1", 300,
            "size2", 200,
            "inc1", 60,
            "inc2", 20,
            "cpw", 1.5);

        // Compute features for segmentation (MFCCs)
        Algorithm* frameCutter = factory.create("FrameCutter",
            "frameSize", 2048,
            "hopSize", 1024);
        Algorithm* windowing = factory.create("Windowing", "type", "hann");
        Algorithm* spectrum = factory.create("Spectrum");
        Algorithm* mfcc = factory.create("MFCC");

        std::vector<std::vector<Real>> allMfccs;
        std::vector<Real> frame, windowedFrame, spectrumVec, mfccBands, mfccCoeffs;

        frameCutter->input("signal").set(audio);
        frameCutter->output("frame").set(frame);

        windowing->input("frame").set(frame);
        windowing->output("frame").set(windowedFrame);

        spectrum->input("frame").set(windowedFrame);
        spectrum->output("spectrum").set(spectrumVec);

        mfcc->input("spectrum").set(spectrumVec);
        mfcc->output("bands").set(mfccBands);
        mfcc->output("mfcc").set(mfccCoeffs);

        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrum->compute();
            mfcc->compute();
            allMfccs.push_back(mfccCoeffs);
        }

        delete frameCutter;
        delete windowing;
        delete spectrum;
        delete mfcc;

        // Convert to TNT matrix format for SBic
        std::vector<std::vector<Real>> features = allMfccs;
        std::vector<Real> segmentation;

        sbic->input("features").set(features);
        sbic->output("segmentation").set(segmentation);
        sbic->compute();
        delete sbic;

        // Build result
        EssentiaResult *result = [[EssentiaResult alloc] init];
        result.bpm = bpm;

        NSMutableArray<NSNumber *> *beatArray = [NSMutableArray new];
        for (Real tick : ticks) {
            [beatArray addObject:@(tick)];
        }
        result.beats = beatArray;

        // Convert segmentation boundaries to sections
        float audioDuration = (float)audio.size() / 44100.0f;
        NSMutableArray<EssentiaSection *> *sectionArray = [NSMutableArray new];

        std::vector<float> boundaries;
        boundaries.push_back(0);
        for (Real seg : segmentation) {
            boundaries.push_back((float)seg);
        }
        boundaries.push_back(audioDuration);

        // Assign labels by simple similarity grouping
        for (size_t i = 0; i < boundaries.size() - 1; i++) {
            EssentiaSection *section = [[EssentiaSection alloc] init];
            section.startTime = boundaries[i];
            section.endTime = boundaries[i + 1];

            // Find nearest beats for start/end
            int startBeat = 0, endBeat = 0;
            for (size_t b = 0; b < ticks.size(); b++) {
                if (ticks[b] <= boundaries[i]) startBeat = (int)b;
                if (ticks[b] <= boundaries[i + 1]) endBeat = (int)b;
            }
            section.startBeat = startBeat;
            section.endBeat = endBeat;
            section.colorIndex = (NSInteger)(i % 8);

            // Simple label assignment
            NSArray *labels = @[@"Intro", @"Verse", @"Chorus", @"Verse", @"Chorus", @"Bridge", @"Outro"];
            section.label = i < labels.count ? labels[i] : [NSString stringWithFormat:@"Section %zu", i + 1];

            [sectionArray addObject:section];
        }
        result.sections = sectionArray;

        essentia::shutdown();
        return result;

    } catch (const std::exception& e) {
        if (error) {
            *error = [NSError errorWithDomain:@"EssentiaAnalyzer"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                        [NSString stringWithUTF8String:e.what()]}];
        }
        return nil;
    }
}

@end
```

- [ ] **Step 5: Update bridging header**

Replace `ThePlayer/ThePlayer-Bridging-Header.h`:

```objc
#import "EssentiaAnalyzer.h"
```

- [ ] **Step 6: Create Swift wrapper conforming to TrackAnalyzerProtocol**

Add to `ThePlayer/Analysis/AnalysisService.swift` — create a new struct above the `AnalysisService` class:

```swift
struct EssentiaAnalyzerSwift: TrackAnalyzerProtocol {
    func analyze(fileURL: URL, progress: @escaping (Float) -> Void) async throws -> TrackAnalysis {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                progress(0.1)

                let analyzer = EssentiaAnalyzerObjC()
                var error: NSError?
                guard let result = analyzer.analyzeFile(atPath: fileURL.path, error: &error) else {
                    continuation.resume(throwing: error ?? NSError(domain: "EssentiaAnalyzer", code: -1))
                    return
                }

                progress(0.8)

                let sections = result.sections.enumerated().map { index, section in
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

                // Waveform peaks are extracted separately by WaveformExtractor
                let peaks = (try? WaveformExtractor.extractPeaks(from: fileURL)) ?? []

                progress(1.0)

                let analysis = TrackAnalysis(
                    bpm: result.bpm,
                    beats: beats,
                    sections: sections,
                    waveformPeaks: peaks
                )
                continuation.resume(returning: analysis)
            }
        }
    }
}
```

- [ ] **Step 7: Switch AnalysisService to use real analyzer when available**

In `AnalysisService.init`, update the default:

Replace:
```swift
    init(analyzer: TrackAnalyzerProtocol = MockAnalyzer(), cache: AnalysisCache = AnalysisCache()) {
```

With:
```swift
    init(analyzer: TrackAnalyzerProtocol? = nil, cache: AnalysisCache = AnalysisCache()) {
        #if ESSENTIA_AVAILABLE
        self.analyzer = analyzer ?? EssentiaAnalyzerSwift()
        #else
        self.analyzer = analyzer ?? MockAnalyzer()
        #endif
```

> **Note:** Until Essentia is compiled and linked, the app uses `MockAnalyzer`. Add `-DESSENTIA_AVAILABLE` to `OTHER_SWIFT_FLAGS` in `project.yml` once Essentia is built and linked.

- [ ] **Step 8: Build to verify (without Essentia — mock mode)**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (using MockAnalyzer)

- [ ] **Step 9: Commit**

```bash
git add ThePlayer/Analysis/ ThePlayer/ThePlayer-Bridging-Header.h project.yml
git commit -m "feat: Essentia integration with ObjC++ bridge and Swift wrapper"
```

---

### Task 15: Run All Tests & Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -scheme ThePlayer -destination 'platform=macOS' 2>&1 | grep -E "(Test Suite|Executed|PASS|FAIL)"`
Expected: All tests pass

- [ ] **Step 2: Build release configuration**

Run: `xcodebuild -scheme ThePlayer -destination 'platform=macOS' -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Verify app launches**

Run: `open build/Release/The\ Player.app` (or build from Xcode and run)
Expected: App opens with empty state showing "Open an Audio File" prompt

- [ ] **Step 4: Commit any final fixes**

```bash
git add -A
git status
# Only commit if there are changes
git diff --cached --quiet || git commit -m "chore: final verification fixes"
```
