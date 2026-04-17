import Foundation

struct TimeSignature: Codable, Equatable, Hashable {
    let beatsPerBar: Int
    let beatUnit: Int

    static let fourFour = TimeSignature(beatsPerBar: 4, beatUnit: 4)
    static let threeFour = TimeSignature(beatsPerBar: 3, beatUnit: 4)
    static let sixEight = TimeSignature(beatsPerBar: 6, beatUnit: 8)
    static let twelveEight = TimeSignature(beatsPerBar: 12, beatUnit: 8)
    static let twoFour = TimeSignature(beatsPerBar: 2, beatUnit: 4)

    static let presets: [TimeSignature] = [
        .fourFour, .threeFour, .sixEight, .twelveEight, .twoFour
    ]

    var displayString: String { "\(beatsPerBar)/\(beatUnit)" }
}
