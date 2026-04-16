import SwiftUI

@main
struct ThePlayerApp: App {
    @State private var audioEngine = AudioEngine()
    @State private var analysisService = AnalysisService()
    @State private var libraryService = LibraryService()

    var body: some Scene {
        WindowGroup {
            ContentView(audioEngine: audioEngine, analysisService: analysisService, libraryService: libraryService)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    openFilePanel()
                }
                .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
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
