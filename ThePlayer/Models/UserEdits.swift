import Foundation

struct UserEdits: Codable, Equatable {
    static let currentSchemaVersion: Int = 1

    var sections: [AudioSection]
    var modifiedAt: Date
    var schemaVersion: Int

    init(sections: [AudioSection], modifiedAt: Date = Date(), schemaVersion: Int = UserEdits.currentSchemaVersion) {
        self.sections = sections
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
    }
}
