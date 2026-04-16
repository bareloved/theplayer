import Foundation

struct Playlist: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var songIds: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(name: String, songIds: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.songIds = songIds
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
