import Foundation

struct SongEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var filePath: String
    var title: String
    var artist: String
    var bpm: Float
    var duration: Float
    var analysisCacheKey: String?
    var lastSpeed: Float = 1.0
    var lastPitch: Float = 0
    var lastPosition: Float = 0
    var lastLoopStart: Float?
    var lastLoopEnd: Float?
    var lastOpenedAt: Date?
    var addedAt: Date
    var practiceCount: Int = 0
    var totalPracticeTime: Double = 0

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    init(filePath: String, title: String, artist: String, bpm: Float, duration: Float) {
        self.id = UUID()
        self.filePath = filePath
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.duration = duration
        self.addedAt = Date()
    }
}
