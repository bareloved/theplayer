import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let openLibraryPicker = Notification.Name("openLibraryPicker")
    static let openAddSongsPanel = Notification.Name("openAddSongsPanel")
}

private struct OpaqueToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbarBackground(.visible, for: .windowToolbar)
    }
}

private struct AddSongsPanelTrigger: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .openAddSongsPanel)) { _ in
            action()
        }
    }
}

struct ContentView: View {
    @Bindable var audioEngine: AudioEngine
    @Bindable var analysisService: AnalysisService
    @Bindable var libraryService: LibraryService
    @State private var loopRegion: LoopRegion?
    @State private var isLoopEnabled: Bool = true
    @State private var isTargeted = false
    @State private var snapToGrid = true
    @State private var loadError: String?
    @State private var showErrorAlert = false
    @State private var keyMonitor: Any?
    @State private var showLibrarySidebar = true
    @State private var showSectionsSidebar = true
    @AppStorage("librarySidebarWidth") private var librarySidebarWidth: Double = 220
    @AppStorage("sectionsSidebarWidth") private var sectionsSidebarWidth: Double = 220
    @State private var sectionsVM: SectionsViewModel?
    @State private var selectedSectionId: UUID?
    @State private var isBoundaryDragging: Bool = false
    @State private var clickTrackPlayer: ClickTrackPlayer?
    @State private var keyboardMonitor: KeyboardJumpMonitor?
    @AppStorage("clickTrackEnabled") private var clickEnabled: Bool = false
    @AppStorage("clickTrackVolume") private var clickVolume: Double = 0.5

    private var selectedSection: AudioSection? {
        guard let id = selectedSectionId else { return nil }
        return sectionsVM?.sections.first(where: { $0.stableId == id })
    }

    private var sectionsSidebar: some View {
        SidebarView(
            sections: sectionsVM?.sections ?? [],
            bpm: analysisService.lastAnalysis?.bpm,
            timeSignature: analysisService.lastAnalysis?.timeSignature ?? .fourFour,
            duration: audioEngine.duration,
            sampleRate: audioEngine.sampleRate,
            onSectionTap: { section in
                selectedSectionId = section.stableId
                loopRegion = LoopRegion.from(section: section)
            },
            onRename: { id, newLabel in
                sectionsVM?.rename(sectionId: id, to: newLabel)
            },
            onDelete: { id in
                sectionsVM?.delete(sectionId: id)
                if selectedSectionId == id {
                    selectedSectionId = nil
                    loopRegion = nil
                }
            },
            selectedSection: Binding(
                get: { self.selectedSection },
                set: { newValue in
                    if let section = newValue {
                        self.selectedSectionId = section.stableId
                        self.loopRegion = LoopRegion.from(section: section)
                    } else {
                        self.selectedSectionId = nil
                        self.loopRegion = nil
                    }
                }
            )
        )
    }

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
                    onReanalyze: { song in
                        guard song.fileExists else { return }
                        let url = URL(fileURLWithPath: song.filePath)
                        Task {
                            try? await analysisService.reanalyze(fileURL: url)
                        }
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
                sectionsSidebar
                    .frame(width: sectionsSidebarWidth)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .modifier(OpaqueToolbar())
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { showLibrarySidebar.toggle() }) {
                    Image(systemName: "sidebar.left")
                }
                .fastTooltip("Toggle Library")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showSectionsSidebar.toggle() }) {
                    Image(systemName: "sidebar.right")
                }
                .fastTooltip("Toggle Sections")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .modifier(AddSongsPanelTrigger(action: presentAddSongsPanel))
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.blue, lineWidth: 3)
                    .background(.blue.opacity(0.05))
                    .padding(4)
            }
        }
        .onChange(of: loopRegion) { _, newLoop in
            let effective = isLoopEnabled ? newLoop : nil
            audioEngine.setLoop(effective)
            // While the user is dragging a section boundary, only update the
            // loop bounds — don't seek. Otherwise every tick yanks the playhead.
            guard !isBoundaryDragging else { return }
            if !isLoopEnabled, let region = newLoop {
                // Loop disabled but the user just designated a region (e.g. by
                // clicking a section): jump the playhead there so the click
                // still feels like navigation.
                audioEngine.seek(to: region.startTime)
            }
            // If isLoopEnabled is true, setLoop() above re-armed the loop
            // in place. We deliberately do NOT seek to loop.startTime —
            // playback continues; the loop wraps when its end is reached.
        }
        .onChange(of: isLoopEnabled) { _, enabled in
            audioEngine.setLoop(enabled ? loopRegion : nil)
        }
        .onAppear {
            installKeyMonitor()
            if clickTrackPlayer == nil {
                let ctp = ClickTrackPlayer(audioEngine: audioEngine)
                ctp.volume = Float(clickVolume)
                clickTrackPlayer = ctp
                pushClickAnalysis()
                ctp.isEnabled = clickEnabled
            }
            if keyboardMonitor == nil {
                let monitor = KeyboardJumpMonitor(audioEngine: audioEngine) {
                    JumpContext(
                        snapToGrid: snapToGrid,
                        analysis: analysisService.lastAnalysis,
                        duration: audioEngine.duration
                    )
                }
                monitor.start()
                keyboardMonitor = monitor
            }
        }
        .onDisappear {
            removeKeyMonitor()
            keyboardMonitor?.stop()
            keyboardMonitor = nil
        }
        .onChange(of: clickEnabled) { _, newValue in
            clickTrackPlayer?.isEnabled = newValue
        }
        .onChange(of: clickVolume) { _, newValue in
            clickTrackPlayer?.volume = Float(newValue)
        }
        .onChange(of: analysisService.lastAnalysis?.bpm) { _, _ in pushClickAnalysis() }
        .onChange(of: analysisService.lastAnalysis?.firstDownbeatTime) { _, _ in pushClickAnalysis() }
        .onChange(of: analysisService.lastAnalysis?.timeSignature) { _, _ in pushClickAnalysis() }
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
                }
            } else {
                // Section no longer exists — clear loop + selection.
                selectedSectionId = nil
                loopRegion = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAudioFile)) { notification in
            if let url = notification.object as? URL {
                openFile(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sectionsUndoRequested)) { _ in
            sectionsVM?.undoManager.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sectionsRedoRequested)) { _ in
            sectionsVM?.undoManager.redo()
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
                    duration: audioEngine.duration,
                    currentTime: audioEngine.currentTime,
                    loopRegion: loopRegion,
                    isLoopEnabled: isLoopEnabled,
                    onSeek: { time in audioEngine.seek(to: time) },
                    onLoopRegionSet: { region in
                        loopRegion = region
                        isLoopEnabled = true
                    },
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
                                selectedSectionId = nil
                                loopRegion = nil
                            } else {
                                selectedSectionId = id
                                loopRegion = LoopRegion.from(section: section)
                            }
                        } else {
                            selectedSectionId = nil
                            loopRegion = nil
                        }
                    },
                    onBoundaryDragChange: { active in
                        isBoundaryDragging = active
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
                isLoopEnabled: $isLoopEnabled,
                snapToGrid: $snapToGrid,
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

    /// Push the current analysis snapshot into the click scheduler. Slot in
    /// when bpm / first-downbeat / time-signature change. Speed changes are
    /// picked up live by the scheduler's refill tick — no call needed here.
    private func pushClickAnalysis() {
        guard let player = clickTrackPlayer else { return }
        guard let analysis = analysisService.lastAnalysis,
              !analysis.beats.isEmpty else {
            player.updateAnalysis(bpm: 0, firstDownbeatTime: 0, beatsPerBar: 4)
            return
        }
        player.updateAnalysis(
            bpm: analysis.bpm,
            firstDownbeatTime: analysis.firstDownbeatTime,
            beatsPerBar: analysis.timeSignature.beatsPerBar
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
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadDroppedURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            // Single audio file dropped → preserve today's "open it" behavior.
            if urls.count == 1, !isDirectory(urls[0]) {
                openFile(url: urls[0])
                return
            }
            await importPaths(urls)
        }
        return true
    }

    private func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private func presentAddSongsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { await importPaths(urls) }
        }
    }

    private func importPaths(_ urls: [URL]) async {
        var expanded: [URL] = []
        for url in urls {
            if isDirectory(url) {
                for await audio in FolderImporter.enumerateAudioFiles(at: url) {
                    expanded.append(audio)
                }
            } else {
                expanded.append(url)
            }
        }
        _ = await libraryService.addSongs(urls: expanded)
    }

    func openFile(url: URL) {
        do {
            try audioEngine.loadFile(url: url)
            selectedSectionId = nil
            loopRegion = nil
            loadError = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            let capturedDuration = audioEngine.duration
            Task { @MainActor in
                let resolved = await audioEngine.loadEmbeddedMetadata(url: url)
                libraryService.addSong(
                    filePath: url.path,
                    title: resolved.title.isEmpty ? fallbackTitle : resolved.title,
                    artist: resolved.artist,
                    bpm: analysisService.lastAnalysis?.bpm ?? 0,
                    duration: capturedDuration
                )
            }
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
            // Mirror the Loop on/off button. No-op when no region exists.
            if loopRegion != nil { isLoopEnabled.toggle() }
            return true
        case 51: // Delete/Backspace
            if let id = selectedSectionId {
                sectionsVM?.delete(sectionId: id)
                return true
            }
            return false
        case 53: // Escape
            loopRegion = nil
            selectedSectionId = nil
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

    private func jumpToSection(_ index: Int) {
        guard let sections = sectionsVM?.sections,
              index <= sections.count else { return }
        let section = sections[index - 1]
        selectedSectionId = section.stableId
        let loop = LoopRegion.from(section: section)
        loopRegion = loop
        audioEngine.setLoop(loop)
        audioEngine.playLoop()
    }
}
