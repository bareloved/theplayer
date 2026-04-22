import SwiftUI

struct AudioSection: Identifiable, Equatable {
    var stableId: UUID
    var label: String
    var startTime: Float
    var endTime: Float
    var startBeat: Int
    var endBeat: Int
    var colorIndex: Int

    var id: UUID { stableId }
    var duration: Float { endTime - startTime }
    var barCount: Int { (endBeat - startBeat) / 4 }

    func barCount(beatsPerBar: Int) -> Int {
        guard beatsPerBar > 0 else { return 0 }
        return (endBeat - startBeat) / beatsPerBar
    }

    init(
        stableId: UUID = UUID(),
        label: String,
        startTime: Float,
        endTime: Float,
        startBeat: Int,
        endBeat: Int,
        colorIndex: Int
    ) {
        self.stableId = stableId
        self.label = label
        self.startTime = startTime
        self.endTime = endTime
        self.startBeat = startBeat
        self.endBeat = endBeat
        self.colorIndex = colorIndex
    }

    private static let palette: [Color] = [
        .blue, .green, .red, .yellow, .purple, .orange, .cyan, .pink
    ]

    var color: Color { Self.palette[colorIndex % Self.palette.count] }
}

extension AudioSection: Codable {
    enum CodingKeys: String, CodingKey {
        case stableId, label, startTime, endTime, startBeat, endBeat, colorIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.stableId = try c.decodeIfPresent(UUID.self, forKey: .stableId) ?? UUID()
        self.label = try c.decode(String.self, forKey: .label)
        self.startTime = try c.decode(Float.self, forKey: .startTime)
        self.endTime = try c.decode(Float.self, forKey: .endTime)
        self.startBeat = try c.decode(Int.self, forKey: .startBeat)
        self.endBeat = try c.decode(Int.self, forKey: .endBeat)
        self.colorIndex = try c.decode(Int.self, forKey: .colorIndex)
    }
}
