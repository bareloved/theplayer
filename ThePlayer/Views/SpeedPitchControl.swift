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
                    value = defaultValue
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
    @State private var dragStartX: CGFloat = 0

    // Non-linear mapping: defaultValue sits at 50% of the track.
    // Left half maps [range.lower .. default], right half maps [default .. range.upper].
    // Falls back to linear if default is at the midpoint already.

    private var useNonLinear: Bool {
        let mid = (range.lowerBound + range.upperBound) / 2
        return abs(defaultValue - mid) > step
    }

    private var fraction: CGFloat {
        fractionFor(value)
    }

    // Use log scale when all bounds positive (speed slider). Log scale makes
    // equal ratios take equal space: 0.5 sits halfway between 0.25 and 1.0.
    private var useLogScale: Bool {
        useNonLinear && range.lowerBound > 0 && defaultValue > 0
    }

    private func fractionFor(_ val: Float) -> CGFloat {
        guard useNonLinear else {
            return CGFloat((val - range.lowerBound) / (range.upperBound - range.lowerBound))
        }

        if useLogScale {
            let v = max(val, range.lowerBound)
            if v <= defaultValue {
                let f = log(v / range.lowerBound) / log(defaultValue / range.lowerBound)
                return CGFloat(f * 0.5)
            } else {
                let f = log(v / defaultValue) / log(range.upperBound / defaultValue)
                return CGFloat(0.5 + f * 0.5)
            }
        } else {
            // Linear within each half (for non-positive ranges)
            if val <= defaultValue {
                let f = (val - range.lowerBound) / (defaultValue - range.lowerBound)
                return CGFloat(f * 0.5)
            } else {
                let f = (val - defaultValue) / (range.upperBound - defaultValue)
                return CGFloat(0.5 + f * 0.5)
            }
        }
    }

    private func valueFor(fraction frac: CGFloat) -> Float {
        let raw: Float

        if !useNonLinear {
            raw = range.lowerBound + Float(frac) * (range.upperBound - range.lowerBound)
        } else if useLogScale {
            if frac <= 0.5 {
                let f = Float(frac) / 0.5
                raw = range.lowerBound * pow(defaultValue / range.lowerBound, f)
            } else {
                let f = (Float(frac) - 0.5) / 0.5
                raw = defaultValue * pow(range.upperBound / defaultValue, f)
            }
        } else {
            if frac <= 0.5 {
                let f = Float(frac) / 0.5
                raw = range.lowerBound + f * (defaultValue - range.lowerBound)
            } else {
                let f = (Float(frac) - 0.5) / 0.5
                raw = defaultValue + f * (range.upperBound - defaultValue)
            }
        }

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
                    .onTapGesture(count: 2) {
                        value = defaultValue
                    }
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { drag in
                                if !isDragging {
                                    isDragging = true
                                    dragStartX = thumbX
                                }
                                let frac = max(0, min(1, (dragStartX + drag.translation.width) / width))
                                var newVal = valueFor(fraction: frac)
                                for snap in snapPoints {
                                    if abs(newVal - snap) < step * 0.5 {
                                        newVal = snap
                                        break
                                    }
                                }
                                value = newVal
                            }
                            .onEnded { _ in isDragging = false }
                    )
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
                value = newVal
            }
        }
    }
}
