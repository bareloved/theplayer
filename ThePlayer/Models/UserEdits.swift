import Foundation

struct UserEdits: Codable, Equatable {
    static let currentSchemaVersion: Int = 2

    var sections: [AudioSection]
    var bpmOverride: Float?
    var downbeatOffsetOverride: Int?
    var timeSignatureOverride: TimeSignature?
    var modifiedAt: Date
    var schemaVersion: Int

    init(
        sections: [AudioSection],
        bpmOverride: Float? = nil,
        downbeatOffsetOverride: Int? = nil,
        timeSignatureOverride: TimeSignature? = nil,
        modifiedAt: Date = Date(),
        schemaVersion: Int = UserEdits.currentSchemaVersion
    ) {
        self.sections = sections
        self.bpmOverride = bpmOverride
        self.downbeatOffsetOverride = downbeatOffsetOverride
        self.timeSignatureOverride = timeSignatureOverride
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
    }
}
