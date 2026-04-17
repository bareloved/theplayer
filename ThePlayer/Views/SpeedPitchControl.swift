import SwiftUI

struct SpeedPitchControl: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let unit: String
    let color: Color
    let formatter: (Float) -> String
    var defaultValue: Float = 1.0
    var snapPoints: [Float] = []
    var sliderWidth: CGFloat = 100

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            HStack(spacing: 8) {
                Text(formatter(range.lowerBound))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)

                Slider(value: $value, in: range, step: step)
                    .tint(color)
                    .frame(width: sliderWidth)
                    .onChange(of: value) { _, newVal in
                        // Snap to nearby snap points
                        for snap in snapPoints {
                            if abs(newVal - snap) < step * 0.6 {
                                value = snap
                                return
                            }
                        }
                    }

                Text(formatter(range.upperBound))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .leading)
            }

            Text(formatter(value) + unit)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        value = defaultValue
                    }
                }
        }
    }
}
