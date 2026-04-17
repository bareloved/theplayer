import SwiftUI
import AppKit

struct WaveformView: View {
    let peaks: [Float]
    let sections: [AudioSection]
    let beats: [Float]
    let bpm: Float
    let snapToGrid: Bool
    let snapDivision: SnapDivision
    let duration: Float
    let currentTime: Float
    let loopRegion: LoopRegion?
    let isSettingLoop: Bool
    let pendingLoopStart: Float?
    let onSeek: (Float) -> Void
    let onLoopPointSet: (Float) -> Void
    let editorViewModel: SectionEditorViewModel?
    let selectedSectionId: UUID?
    let onSelectSection: ((UUID?) -> Void)?

    @State private var zoomLevel: CGFloat = 1.0
    @State private var scrollOffset: CGFloat = 0
    @State private var hoverTime: Float?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width * zoomLevel
            let height = geo.size.height

            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .leading) {
                    sectionBands(width: totalWidth, height: height)
                    if snapToGrid {
                        barLines(width: totalWidth, height: height)
                    }
                    waveformBars(width: totalWidth, height: height)

                    if let loop = loopRegion {
                        loopOverlay(loop: loop, width: totalWidth, height: height)
                    }

                    playhead(width: totalWidth, height: height)

                    if let vm = editorViewModel {
                        boundaryHandles(viewModel: vm, width: totalWidth, height: height)
                    }

                    if let start = pendingLoopStart {
                        pendingLoopMarker(start: start, width: totalWidth, height: height)
                    }

                    if let time = hoverTime, let loc = hoverLocation {
                        hoverTooltip(time: time, location: loc)
                    }
                }
                .frame(width: totalWidth, height: height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let fraction = Float(location.x / totalWidth)
                    let time = fraction * duration
                    if let onSelectSection = onSelectSection, editorViewModel != nil {
                        let hit = sections.first(where: { time >= $0.startTime && time < $0.endTime })
                        onSelectSection(hit?.stableId)
                        return
                    }
                    if isSettingLoop {
                        onLoopPointSet(time)
                    } else {
                        onSeek(time)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let fraction = Float(location.x / totalWidth)
                        hoverTime = fraction * duration
                        hoverLocation = location
                    case .ended:
                        hoverTime = nil
                        hoverLocation = nil
                    }
                }
            }
            .gesture(MagnifyGesture().onChanged { value in
                zoomLevel = max(1.0, min(zoomLevel * value.magnification, 20.0))
            })
            .background {
                ScrollWheelHandler { delta in
                    let factor: CGFloat = delta > 0 ? 1.15 : 1.0 / 1.15
                    zoomLevel = max(1.0, min(zoomLevel * factor, 20.0))
                }
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) {
            timeLabel(formatTime(currentTime))
                .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                timeLabel(formatTime(duration))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Button(action: { zoomLevel = max(1.0, zoomLevel / 1.5) }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(zoomLevel > 1.0 ? .primary : .tertiary)
                    .disabled(zoomLevel <= 1.0)

                    Text("\(Int(zoomLevel * 100))%")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 36)

                    Button(action: { zoomLevel = min(20.0, zoomLevel * 1.5) }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(zoomLevel < 20.0 ? .primary : .tertiary)
                    .disabled(zoomLevel >= 20.0)
                }
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(8)
        }
        .overlay {
            if isSettingLoop {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.orange, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Grid positions based on current snap division
    private var gridPositions: [Float] {
        snapDivision.snapPositions(beats: beats, bpm: bpm, duration: duration)
    }

    /// Bar positions (always every 4 beats) for strong lines
    private var barPositions: Set<Float> {
        guard beats.count >= 4 else { return [] }
        let bars = stride(from: 0, to: beats.count, by: 4).map { beats[$0] }
        return Set(bars.map { ($0 * 100).rounded() / 100 }) // round for matching
    }

    private func barLines(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard duration > 0 else { return }

            // Draw grid lines at snap positions
            for gridTime in gridPositions {
                let x = CGFloat(gridTime / duration) * size.width
                let rounded = (gridTime * 100).rounded() / 100
                let isBar = barPositions.contains(rounded)
                let opacity: CGFloat = isBar ? 0.45 : 0.2
                let lw: CGFloat = isBar ? 1.5 : 0.75

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lw)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func sectionBands(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(sections) { section in
                let sectionWidth = CGFloat((section.endTime - section.startTime) / duration) * width
                let isSelected = section.stableId == selectedSectionId
                Rectangle()
                    .fill(section.color.opacity(isSelected ? 0.25 : 0.1))
                    .overlay(
                        Rectangle()
                            .strokeBorder(section.color, lineWidth: isSelected ? 2 : 0)
                    )
                    .frame(width: sectionWidth, height: height)
            }
        }
    }

    @ViewBuilder
    private func boundaryHandles(viewModel vm: SectionEditorViewModel, width: CGFloat, height: CGFloat) -> some View {
        ForEach(Array(vm.sections.enumerated()), id: \.element.stableId) { idx, section in
            if idx > 0 {
                let x = CGFloat(section.startTime / duration) * width
                SectionBoundaryHandle(
                    xPosition: x,
                    height: height,
                    isHovered: false,
                    onDragChanged: { delta in
                        let timeDelta = Float(delta / width) * duration
                        let newTime = section.startTime + timeDelta
                        let snap = !NSEvent.modifierFlags.contains(.option)
                        vm.moveBoundary(beforeSectionId: section.stableId, toTime: newTime, snapToBeat: snap)
                    },
                    onDragEnded: { /* persistence handled via vm.onChange */ }
                )
            }
        }
    }

    private func waveformBars(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let barWidth = size.width / CGFloat(peaks.count)
            let midY = size.height / 2

            for (i, peak) in peaks.enumerated() {
                let x = CGFloat(i) * barWidth
                let barHeight = CGFloat(peak) * size.height * 0.8
                let fraction = Float(i) / Float(peaks.count)
                let time = fraction * duration

                let isPlayed = time <= currentTime
                let color: Color = isPlayed ? .blue : .gray.opacity(0.5)

                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: max(barWidth - 1, 1),
                    height: barHeight
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        let x = duration > 0 ? CGFloat(currentTime / duration) * width : 0
        return Rectangle()
            .fill(.white)
            .frame(width: 2, height: height)
            .overlay(alignment: .top) {
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .offset(y: -5)
            }
            .offset(x: x)
            .allowsHitTesting(false)
    }

    private func loopOverlay(loop: LoopRegion, width: CGFloat, height: CGFloat) -> some View {
        let startX = CGFloat(loop.startTime / duration) * width
        let endX = CGFloat(loop.endTime / duration) * width
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.blue.opacity(0.1))
                .frame(width: endX - startX, height: height)

            Rectangle()
                .fill(.blue.opacity(0.5))
                .frame(width: 2, height: height)

            Rectangle()
                .fill(.blue.opacity(0.5))
                .frame(width: 2, height: height)
                .offset(x: endX - startX - 2)

            Text("LOOP")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.blue)
                .padding(4)
        }
        .offset(x: startX)
        .allowsHitTesting(false)
    }

    private func pendingLoopMarker(start: Float, width: CGFloat, height: CGFloat) -> some View {
        let x = duration > 0 ? CGFloat(start / duration) * width : 0
        return VStack(spacing: 2) {
            Text("A")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange)
            Rectangle()
                .fill(.orange)
                .frame(width: 2, height: height)
        }
        .offset(x: x)
        .allowsHitTesting(false)
    }

    private func hoverTooltip(time: Float, location: CGPoint) -> some View {
        Text(formatTime(time))
            .font(.caption2.monospaced())
            .padding(4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .position(x: location.x, y: location.y - 20)
            .allowsHitTesting(false)
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
    }

    private func formatTime(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

private struct ScrollWheelHandler: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            onScroll?(event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
