import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var audioEngine: AudioEngine
    @Bindable var analysisService: AnalysisService
    @Bindable var libraryService: LibraryService
    @State private var selectedSection: AudioSection?
    @State private var loopRegion: LoopRegion?
    @State private var isTargeted = false
    @State private var isSettingLoop = false
    @State private var pendingLoopStart: Float?
    @State private var snapToGrid = true
    @State private var snapDivision: SnapDivision = .oneBar
    @State private var loadError: String?
    @State private var showErrorAlert = false
    @State private var keyMonitor: Any?
    @State private var showLibrarySidebar = true
    @State private var showSectionsSidebar = true
    @State private var librarySidebarWidth: CGFloat = 220
    @State private var sectionsSidebarWidth: CGFloat = 220
    @State private var sectionsVM: SectionsViewModel?
    @State private var selectedSectionId: UUID?
    @State private var clickTrackPlayer: ClickTrackPlayer?
    @AppStorage("clickTrackEnabled") private var clickEnabled: Bool = false
    @AppStorage("clickTrackVolume") private var clickVolume: Double = 0.5

    var body: some View {
        HStack(spacing: 0) {
            // Left: Library sidebar
            if showLibrarySidebar {
                LibrarySidebar(
                    libraryService: libraryService,
                    onSongSelect: { song in
                        loadSongFromLibrary(song)
                    },
                    onSetlistSongSelect: { song, setlistId, index in
                        loadSongFromLibrary(song)
                    },
                    currentSongPath: audioEngine.fileURL?.path
                )
                .frame(width: librarySidebarWidth)

                ResizableDivider(dimension: $librarySidebarWidth, minSize: 200, maxSize: 400)
            }

            // Center: Player
            Group {
                if audioEngine.state == .empty {
                    emptyState
                } else {
                    playerDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right: Sections sidebar
            if showSectionsSidebar && audioEngine.state != .empty {
                ResizableDivider(dimension: $sectionsSidebarWidth, minSize: 160, maxSize: 400, isLeading: false)

                SidebarView(
                    sections: sectionsVM?.sections ?? [],
                    bpm: analysisService.lastAnalysis?.bpm,
                    timeSignature: analysisService.lastAnalysis?.timeSignature ?? .fourFour,
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
                .frame(width: sectionsSidebarWidth)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { showLibrarySidebar.toggle() }) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Library")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showSectionsSidebar.toggle() }) {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Sections")
            }
        }
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
        .onAppear {
            installKeyMonitor()
            if clickTrackPlayer == nil {
                let ctp = ClickTrackPlayer(audioEngine: audioEngine)
                ctp.isEnabled = clickEnabled
                ctp.volume = Float(clickVolume)
                clickTrackPlayer = ctp
                audioEngine.onTimingChanged = {
                    rescheduleClicks()
                }
            }
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: clickEnabled) { _, newValue in
            clickTrackPlayer?.isEnabled = newValue
            rescheduleClicks()
        }
        .onChange(of: clickVolume) { _, newValue in
            clickTrackPlayer?.volume = Float(newValue)
        }
        .onChange(of: analysisService.lastAnalysis?.bpm) { _, _ in rescheduleClicks() }
        .onChange(of: analysisService.lastAnalysis?.firstDownbeatTime) { _, _ in rescheduleClicks() }
        .onChange(of: analysisService.lastAnalysis?.timeSignature) { _, _ in rescheduleClicks() }
        .onChange(of: analysisService.lastAnalysisKey) { _, newKey in
            guard newKey != nil, let analysis = analysisService.lastAnalysis else {
                sectionsVM = nil
                selectedSectionId = nil
                return
            }
            sectionsVM = buildSectionsVM(from: analysis)
            selectedSectionId = nil
        }
        .onChange(of: sectionsVM?.sections) { _, newSections in
            guard let id = selectedSectionId else { return }
            if let newSections,
               let section = newSections.first(where: { $0.stableId == id }) {
                let loop = LoopRegion.from(section: section)
                if loopRegion != loop {
                    loopRegion = loop
                    audioEngine.setLoop(loop)
                }
            } else {
                // Section no longer exists — clear loop + selection.
                selectedSectionId = nil
                loopRegion = nil
                audioEngine.setLoop(nil)
            }
        }
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
                    sections: sectionsVM?.sections ?? [],
                    beats: analysisService.lastAnalysis?.beats ?? [],
                    onsets: analysisService.lastAnalysis?.onsets ?? [],
                    bpm: analysisService.lastAnalysis?.bpm ?? 0,
                    snapToGrid: snapToGrid,
                    snapDivision: snapDivision,
                    duration: audioEngine.duration,
                    currentTime: audioEngine.currentTime,
                    loopRegion: loopRegion,
                    isSettingLoop: isSettingLoop,
                    pendingLoopStart: pendingLoopStart,
                    onSeek: { time in audioEngine.seek(to: time) },
                    onLoopPointSet: { time in handleLoopPoint(time) },
                    firstDownbeatTime: analysisService.lastAnalysis?.firstDownbeatTime ?? 0,
                    timeSignature: analysisService.lastAnalysis?.timeSignature ?? .fourFour,
                    onSetDownbeat: { time in
                        setDownbeatOverride(time)
                    },
                    sectionsVM: sectionsVM,
                    selectedSectionId: selectedSectionId,
                    onSelectSection: { newId in
                        guard let vm = sectionsVM else { return }
                        if let id = newId,
                           let section = vm.sections.first(where: { $0.stableId == id }) {
                            if selectedSectionId == id {
                                // Toggle off
                                selectedSectionId = nil
                                loopRegion = nil
                                audioEngine.setLoop(nil)
                            } else {
                                selectedSectionId = id
                                let loop = LoopRegion.from(section: section)
                                loopRegion = loop
                                audioEngine.setLoop(loop)
                            }
                        } else {
                            selectedSectionId = nil
                            loopRegion = nil
                            audioEngine.setLoop(nil)
                        }
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
                isSettingLoop: $isSettingLoop,
                snapToGrid: $snapToGrid,
                snapDivision: $snapDivision,
                isInSetlist: libraryService.activeSetlistId != nil,
                onNextInSetlist: { advanceSetlist() },
                timingControls: AnyView(
                    TimingControls(
                        bpm: analysisService.lastAnalysis?.bpm ?? 0,
                        timeSignature: analysisService.lastAnalysis?.timeSignature ?? .fourFour,
                        hasBpmOverride: analysisService.baseAnalysis?.bpm != analysisService.lastAnalysis?.bpm,
                        hasTimeSigOverride: analysisService.baseAnalysis?.timeSignature != analysisService.lastAnalysis?.timeSignature,
                        onSetBpm: { v in setBpmOverride(v) },
                        onResetBpm: { setBpmOverride(nil) },
                        onSetTimeSignature: { ts in setTimeSignatureOverride(ts) },
                        onResetTimeSignature: { setTimeSignatureOverride(nil) },
                        isClickEnabled: clickEnabled,
                        clickVolume: $clickVolume,
                        onToggleClick: { clickEnabled.toggle() }
                    )
                )
            )
        }
    }

    private func rescheduleClicks() {
        guard let player = clickTrackPlayer else { return }
        guard audioEngine.isPlaying,
              clickEnabled,
              let analysis = analysisService.lastAnalysis,
              !analysis.beats.isEmpty else {
            player.stop()
            return
        }
        let firstDownbeat = analysis.firstDownbeatTime
        player.reschedule(
            bpm: analysis.bpm,
            firstDownbeatTime: firstDownbeat,
            beatsPerBar: analysis.timeSignature.beatsPerBar,
            speed: audioEngine.speed
        )
    }

    private func setBpmOverride(_ value: Float?) {
        guard let key = analysisService.lastAnalysisKey else { return }
        var next = (try? analysisService.userEdits.retrieve(forKey: key)) ?? UserEdits(sections: [])
        next.bpmOverride = value
        next.modifiedAt = Date()
        try? analysisService.applyUserEditsPatch(next)
    }

    private func setDownbeatOverride(_ value: Float?) {
        guard let key = analysisService.lastAnalysisKey else { return }
        var next = (try? analysisService.userEdits.retrieve(forKey: key)) ?? UserEdits(sections: [])
        next.downbeatTimeOverride = value
        next.modifiedAt = Date()
        try? analysisService.applyUserEditsPatch(next)
    }

    private func setTimeSignatureOverride(_ value: TimeSignature?) {
        guard let key = analysisService.lastAnalysisKey else { return }
        var next = (try? analysisService.userEdits.retrieve(forKey: key)) ?? UserEdits(sections: [])
        next.timeSignatureOverride = value
        next.modifiedAt = Date()
        try? analysisService.applyUserEditsPatch(next)
    }

    private func buildSectionsVM(from analysis: TrackAnalysis) -> SectionsViewModel {
        let persisted = analysis.sections
        let seed: [AudioSection]
        if persisted.isEmpty {
            seed = [AudioSection(
                label: "Untitled",
                startTime: 0,
                endTime: Float(audioEngine.duration),
                startBeat: 0,
                endBeat: max(0, analysis.beats.count - 1),
                colorIndex: 0
            )]
        } else {
            seed = persisted
        }
        let vm = SectionsViewModel(
            sections: seed,
            beats: analysis.beats,
            duration: Float(audioEngine.duration)
        )
        vm.onChange = { [weak analysisService] sections in
            // `onChange` only fires after a user mutation — the initial synthetic seed
            // is installed before this closure is attached (and SectionsViewModel init
            // never calls onChange), so no guard is needed.
            try? analysisService?.saveUserEdits(sections)
        }
        return vm
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
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            libraryService.addSong(
                filePath: url.path,
                title: audioEngine.title.isEmpty ? fallbackTitle : audioEngine.title,
                artist: audioEngine.artist,
                bpm: analysisService.lastAnalysis?.bpm ?? 0,
                duration: audioEngine.duration
            )
            Task {
                await analysisService.analyze(fileURL: url)
            }
        } catch {
            loadError = "Could not open file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func loadSongFromLibrary(_ song: SongEntry) {
        guard song.fileExists else { return }
        let url = URL(fileURLWithPath: song.filePath)
        saveCurrentPracticeState()
        openFile(url: url)
        audioEngine.speed = song.lastSpeed
        audioEngine.pitch = song.lastPitch
        if song.lastPosition > 0 {
            audioEngine.seek(to: song.lastPosition)
        }
        if let loopStart = song.lastLoopStart, let loopEnd = song.lastLoopEnd {
            loopRegion = LoopRegion(startTime: loopStart, endTime: loopEnd)
        }
        libraryService.incrementPracticeCount(songId: song.id)
    }

    private func saveCurrentPracticeState() {
        guard let url = audioEngine.fileURL else { return }
        if let song = libraryService.library.songByPath(url.path) {
            libraryService.savePracticeState(
                songId: song.id,
                speed: audioEngine.speed,
                pitch: audioEngine.pitch,
                position: audioEngine.currentTime,
                loopStart: loopRegion?.startTime,
                loopEnd: loopRegion?.endTime
            )
        }
    }

    private func advanceSetlist() {
        saveCurrentPracticeState()
        if let nextSong = libraryService.nextSetlistSong() {
            loadSongFromLibrary(nextSong)
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
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            saveCurrentPracticeState()
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

        // Don't intercept while the user is typing in a text field (BPM editor, etc.)
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
            return false
        }

        switch event.keyCode {
        case 49: // Space
            audioEngine.togglePlayPause()
            return true
        case 123: // Left arrow
            if snapToGrid {
                let positions = getSnapPositions()
                if !positions.isEmpty {
                    let prev = positions.last(where: { $0 < audioEngine.currentTime - 0.05 })
                    audioEngine.seek(to: max(prev ?? 0, 0))
                } else {
                    audioEngine.skipBackward()
                }
            } else {
                audioEngine.skipBackward()
            }
            return true
        case 124: // Right arrow
            if snapToGrid {
                let positions = getSnapPositions()
                if !positions.isEmpty {
                    let next = positions.first(where: { $0 > audioEngine.currentTime + 0.05 })
                    audioEngine.seek(to: min(next ?? audioEngine.duration, audioEngine.duration))
                } else {
                    audioEngine.skipForward()
                }
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

    private func getSnapPositions() -> [Float] {
        let analysis = analysisService.lastAnalysis
        let bpb = analysis?.timeSignature.beatsPerBar ?? 4
        let beats = analysis?.beats ?? []
        let firstBeatTime: Float? = analysis?.firstDownbeatTime
        return snapDivision.snapPositions(
            beats: beats,
            bpm: analysis?.bpm ?? 0,
            duration: audioEngine.duration,
            beatsPerBar: bpb,
            firstBeatTime: firstBeatTime
        )
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
