import Foundation

/// A simple named folder used to group setlists or playlists in the library
/// sidebar. Folders are flat (no nesting) for now.
struct LibraryFolder: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
