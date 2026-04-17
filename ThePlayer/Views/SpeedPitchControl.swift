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
    var sliderWidth: CGFloat = 160

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

                CustomSlider(
                    value: $value,
                    range: range,
                    step: step,
                    color: color,
                    defaultValue: defaultValue,
                    snapPoints: snapPoints
                )
                .frame(width: sliderWidth, height: 20)

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

// MARK: - Custom Slider with snap markers and double-click reset

private struct CustomSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let color: Color
    let defaultValue: Float
    let snapPoints: [Float]

    @State private var isDragging = false

    private var fraction: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    private func fractionFor(_ val: Float) -> CGFloat {
        CGFloat((val - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    private func valueFor(fraction: CGFloat) -> Float {
        let raw = range.lowerBound + Float(fraction) * (range.upperBound - range.lowerBound)
        // Round to step
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbX = fraction * width

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 4)

                // Filled track
                Capsule()
                    .fill(color)
                    .frame(width: max(thumbX, 0), height: 4)

                // Snap point markers
                ForEach(snapPoints, id: \.self) { snap in
                    let x = fractionFor(snap) * width
                    Circle()
                        .fill(.white.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .position(x: x, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }

                // Thumb
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: 16, height: 16)
                    .position(x: thumbX, y: geo.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                isDragging = true
                                let frac = max(0, min(1, drag.location.x / width))
                                var newVal = valueFor(fraction: frac)
                                // Snap
                                for snap in snapPoints {
                                    if abs(newVal - snap) < step * 1.2 {
                                        newVal = snap
                                        break
                                    }
                                }
                                value = newVal
                            }
                            .onEnded { _ in isDragging = false }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            value = defaultValue
                        }
                    }
            }
            // Click anywhere on track to jump
            .contentShape(Rectangle())
            .onTapGesture { location in
                let frac = max(0, min(1, location.x / width))
                var newVal = valueFor(fraction: frac)
                for snap in snapPoints {
                    if abs(newVal - snap) < step * 1.2 {
                        newVal = snap
                        break
                    }
                }
                withAnimation(.easeInOut(duration: 0.1)) {
                    value = newVal
                }
            }
        }
    }
}
