import Foundation
import os

final class UserEditsStore {
    private let directory: URL
    private let logger = Logger(subsystem: "com.theplayer.app", category: "UserEditsStore")

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("The Player/cache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).user.json")
    }

    func store(_ edits: UserEdits, forKey key: String) throws {
        let data = try JSONEncoder().encode(edits)
        try data.write(to: url(forKey: key), options: .atomic)
    }

    func retrieve(forKey key: String) throws -> UserEdits? {
        let fileURL = url(forKey: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let edits = try JSONDecoder().decode(UserEdits.self, from: data)
        guard edits.schemaVersion <= UserEdits.currentSchemaVersion else {
            logger.warning("Ignoring user edits with unknown schema version \(edits.schemaVersion) for key \(key)")
            return nil
        }
        return edits
    }

    func delete(forKey key: String) throws {
        let fileURL = url(forKey: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func exists(forKey key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forKey: key).path)
    }
}
