import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var audioEngine: AudioEngine
    @Bindable var analysisService: AnalysisService
    @State private var selectedSection: AudioSection?
    @State private var loopRegion: LoopRegion?
    @State private var isTargeted = false
    @State private var isSettingLoop = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                sections: analysisService.lastAnalysis?.sections ?? [],
                bpm: analysisService.lastAnalysis?.bpm,
                duration: audioEngine.duration,
                sampleRate: audioEngine.sampleRate,
                onSectionTap: { section in
                    selectedSection = section
                    let loop = LoopRegion.from(section: section)
                    loopRegion = loop
                    audioEngine.setLoop(loop)
                    audioEngine.playLoop()
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
        .onChange(of: loopRegion) { _, newLoop in
            audioEngine.setLoop(newLoop)
            if let newLoop, audioEngine.isPlaying {
                audioEngine.playLoop()
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .openAudioFile)) { notification in
            if let url = notification.object as? URL {
                openFile(url: url)
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

            TransportBar(
                audioEngine: audioEngine,
                loopRegion: $loopRegion,
                isSettingLoop: $isSettingLoop
            )
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
            // Error handling added in Task 13
        }
    }

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
}
