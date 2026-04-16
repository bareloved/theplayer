import SwiftUI

enum SectionLabelPresets {
    /// Common section labels in display order.
    static let labels: [String] = [
        "Intro", "Verse", "Pre-Chorus", "Chorus",
        "Bridge", "Solo", "Breakdown", "Drop", "Outro"
    ]

    /// Default color index for known labels. Mirrors AudioSection.palette indices.
    /// Returns nil for unknown labels (caller should keep current colorIndex).
    static func defaultColorIndex(for label: String) -> Int? {
        switch label {
        case "Intro":      return 0  // blue
        case "Verse":      return 1  // green
        case "Pre-Chorus": return 5  // orange
        case "Chorus":     return 2  // red
        case "Bridge":     return 3  // yellow
        case "Solo":       return 4  // purple
        case "Breakdown":  return 6  // cyan
        case "Drop":       return 7  // pink
        case "Outro":      return 0  // blue
        default:           return nil
        }
    }
}
