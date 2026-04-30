import Foundation

struct Playlist: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    var songIds: [UUID]
    var createdAt: Date
    var updatedAt: Date
    var folderId: UUID?

    init(name: String, description: String? = nil, songIds: [UUID] = [], folderId: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.songIds = songIds
        self.createdAt = Date()
        self.updatedAt = Date()
        self.folderId = folderId
    }
}
