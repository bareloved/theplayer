import Foundation

struct Setlist: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    var songIds: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(name: String, description: String? = nil, songIds: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.songIds = songIds
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
