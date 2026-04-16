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
    }
}

extension Notification.Name {
    static let openAudioFile = Notification.Name("openAudioFile")
}
