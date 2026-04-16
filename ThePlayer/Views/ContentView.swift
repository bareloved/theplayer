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
            // Error handling added in Task 13
        }
    }
}
