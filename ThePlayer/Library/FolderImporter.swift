import Foundation
import UniformTypeIdentifiers

enum FolderImporter {
    /// Recursively enumerates audio files under `root`, skipping hidden files and
    /// package contents. Yields each audio URL on a background task.
    static func enumerateAudioFiles(at root: URL) -> AsyncStream<URL> {
        AsyncStream { continuation in
            Task.detached {
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .typeIdentifierKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continuation.finish()
                    return
                }
                while let next = enumerator.nextObject() {
                    if Task.isCancelled { break }
                    guard let url = next as? URL else { continue }
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .typeIdentifierKey])
                    guard values?.isRegularFile == true else { continue }
                    if let typeId = values?.typeIdentifier,
                       let utType = UTType(typeId),
                       utType.conforms(to: .audio) {
                        continuation.yield(url)
                    }
                }
                continuation.finish()
            }
        }
    }
}
