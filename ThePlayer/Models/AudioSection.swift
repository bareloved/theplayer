import SwiftUI

struct AudioSection: Identifiable, Equatable {
    var id: String { "\(label)-\(startTime)" }

    let label: String
    let startTime: Float
    let endTime: Float
    let startBeat: Int
    let endBeat: Int
    let colorIndex: Int

    var duration: Float { endTime - startTime }

    var barCount: Int { (endBeat - startBeat) / 4 }

    private static let palette: [Color] = [
        .blue, .green, .red, .yellow, .purple, .orange, .cyan, .pink
    ]

    var color: Color {
        Self.palette[colorIndex % Self.palette.count]
    }
}

extension AudioSection: Codable {
    enum CodingKeys: String, CodingKey {
        case label
        case startTime
        case endTime
        case startBeat
        case endBeat
        case colorIndex
    }
}
