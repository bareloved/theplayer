import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var audioEngine: AudioEngine
    @Bindable var analysisService: AnalysisService
    @State private var selectedSection: AudioSection?
    @State private var loopRegion: LoopRegion?
    @State private var isTargeted = false
    @State private var isSettingLoop = false
    @State private var pendingLoopStart: Float?
    @State private var loadError: String?
    @State private var showErrorAlert = false
    @State private var keyMonitor: Any?

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
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: .openAudioFile)) { notification in
            if let url = notification.object as? URL {
                openFile(url: url)
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "An unknown error occurred")
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
                    beats: analysisService.lastAnalysis?.beats ?? [],
                    bpm: analysisService.lastAnalysis?.bpm ?? 0,
                    duration: audioEngine.duration,
                    currentTime: audioEngine.currentTime,
                    loopRegion: loopRegion,
                    isSettingLoop: isSettingLoop,
                    pendingLoopStart: pendingLoopStart,
                    onSeek: { time in audioEngine.seek(to: time) },
                    onLoopPointSet: { time in handleLoopPoint(time) }
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

    private func handleLoopPoint(_ time: Float) {
        if let start = pendingLoopStart {
            let loopStart = min(start, time)
            let loopEnd = max(start, time)
            guard loopEnd - loopStart > 0.1 else { return } // minimum loop length
            let loop = LoopRegion(startTime: loopStart, endTime: loopEnd)
            loopRegion = loop
            pendingLoopStart = nil
            isSettingLoop = false
            audioEngine.setLoop(loop)
            audioEngine.playLoop()
        } else {
            pendingLoopStart = time
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyEvent(event) { return nil }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Don't intercept when modifier keys are held (except shift)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        switch event.keyCode {
        case 49: // Space
            audioEngine.togglePlayPause()
            return true
        case 123: // Left arrow — snap to previous bar
            let barPositions = getBarPositions()
            if !barPositions.isEmpty {
                let prev = barPositions.last(where: { $0 < audioEngine.currentTime - 0.1 })
                audioEngine.seek(to: max(prev ?? 0, 0))
            } else {
                audioEngine.skipBackward()
            }
            return true
        case 124: // Right arrow — snap to next bar
            let barPositions2 = getBarPositions()
            if !barPositions2.isEmpty {
                let next = barPositions2.first(where: { $0 > audioEngine.currentTime + 0.1 })
                audioEngine.seek(to: min(next ?? audioEngine.duration, audioEngine.duration))
            } else {
                audioEngine.skipForward()
            }
            return true
        case 126: // Up arrow
            audioEngine.speed += 0.05
            return true
        case 125: // Down arrow
            audioEngine.speed -= 0.05
            return true
        case 33: // [
            audioEngine.pitch -= 1
            return true
        case 30: // ]
            audioEngine.pitch += 1
            return true
        case 37: // L
            if loopRegion != nil { loopRegion = nil }
            return true
        case 53: // Escape
            loopRegion = nil
            selectedSection = nil
            pendingLoopStart = nil
            isSettingLoop = false
            return true
        default:
            break
        }

        // Number keys 1-9 (keyCode 18-26)
        if let chars = event.charactersIgnoringModifiers,
           let digit = chars.first?.wholeNumberValue,
           digit >= 1 && digit <= 9 {
            jumpToSection(digit)
            return true
        }

        return false
    }

    private func getBarPositions() -> [Float] {
        let beats = analysisService.lastAnalysis?.beats ?? []
        guard beats.count >= 4 else { return [] }
        return stride(from: 0, to: beats.count, by: 4).map { beats[$0] }
    }

    private func jumpToSection(_ index: Int) {
        guard let sections = analysisService.lastAnalysis?.sections,
              index <= sections.count else { return }
        let section = sections[index - 1]
        selectedSection = section
        let loop = LoopRegion.from(section: section)
        loopRegion = loop
        audioEngine.setLoop(loop)
        audioEngine.playLoop()
    }
}
