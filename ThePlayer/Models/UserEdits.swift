import Foundation

struct UserEdits: Codable, Equatable {
    static let currentSchemaVersion: Int = 3

    var sections: [AudioSection]
    var bpmOverride: Float?
    var downbeatTimeOverride: Float?    // seconds; replaces the old Int beat-offset override
    var timeSignatureOverride: TimeSignature?
    var modifiedAt: Date
    var schemaVersion: Int

    init(
        sections: [AudioSection],
        bpmOverride: Float? = nil,
        downbeatTimeOverride: Float? = nil,
        timeSignatureOverride: TimeSignature? = nil,
        modifiedAt: Date = Date(),
        schemaVersion: Int = UserEdits.currentSchemaVersion
    ) {
        self.sections = sections
        self.bpmOverride = bpmOverride
        self.downbeatTimeOverride = downbeatTimeOverride
        self.timeSignatureOverride = timeSignatureOverride
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
    }
}
