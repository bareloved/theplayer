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
    let firstDownbeatTime: Float
    let timeSignature: TimeSignature
    let isSettingDownbeat: Bool
    let onSetDownbeat: ((Float) -> Void)?
    let editorViewModel: SectionEditorViewModel?
    let selectedSectionId: UUID?
    let onSelectSection: ((UUID?) -> Void)?

    @State private var zoomLevel: CGFloat = 1.0
    @State private var scrollOffset: CGFloat = 0
    @State private var hoverTime: Float?
    @State private var hoverLocation: CGPoint?
    @StateObject private var scrollController = ScrollController()

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width * zoomLevel
            let height = geo.size.height

            let bandHeight = WaveformZoomMath.rulerHeight
            let downbeatStripHeight: CGFloat = 12
            let waveHeight = max(0, height - bandHeight - downbeatStripHeight)

            HorizontalNSScrollView(
                contentWidth: totalWidth,
                contentHeight: height,
                onCommandScroll: { delta in
                    let factor: CGFloat = delta > 0 ? 1.15 : 1.0 / 1.15
                    zoomLevel = max(WaveformZoomMath.minZoom,
                                    min(zoomLevel * factor, WaveformZoomMath.maxZoom))
                },
                controller: scrollController
            ) {
                VStack(spacing: 0) {
                    WaveformRulerBand(
                        duration: duration,
                        bpm: bpm,
                        firstDownbeatTime: firstDownbeatTime,
                        timeSignature: timeSignature,
                        totalWidth: totalWidth,
                        geoWidth: geo.size.width,
                        bandHeight: bandHeight,
                        zoomLevel: $zoomLevel,
                        scrollController: scrollController
                    )

                    downbeatStrip(width: totalWidth, height: downbeatStripHeight)

                    ZStack(alignment: .leading) {
                        sectionBands(width: totalWidth, height: waveHeight)
                        if snapToGrid {
                            barLines(width: totalWidth, height: waveHeight)
                        }
                        waveformBars(width: totalWidth, height: waveHeight)

                        if let loop = loopRegion {
                            loopOverlay(loop: loop, width: totalWidth, height: waveHeight)
                        }

                        playhead(width: totalWidth, height: waveHeight)

                        if let vm = editorViewModel {
                            boundaryHandles(viewModel: vm, width: totalWidth, height: waveHeight)
                        }

                        if let start = pendingLoopStart {
                            pendingLoopMarker(start: start, width: totalWidth, height: waveHeight)
                        }

                        if let time = hoverTime, let loc = hoverLocation {
                            hoverTooltip(time: time, location: loc)
                        }
                    }
                    .frame(width: totalWidth, height: waveHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let fraction = Float(location.x / totalWidth)
                        let time = fraction * duration
                        if isSettingDownbeat, let onSetDownbeat {
                            onSetDownbeat(time)
                            return
                        }
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
                .frame(width: totalWidth, height: height)
            }
            .gesture(MagnifyGesture().onChanged { value in
                zoomLevel = max(WaveformZoomMath.minZoom,
                                min(zoomLevel * value.magnification, WaveformZoomMath.maxZoom))
            })
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
                    Button(action: { zoomLevel = max(WaveformZoomMath.minZoom, zoomLevel / 1.5) }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(zoomLevel > WaveformZoomMath.minZoom ? .primary : .tertiary)
                    .disabled(zoomLevel <= WaveformZoomMath.minZoom)

                    Text("\(Int(zoomLevel * 100))%")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 36)

                    Button(action: { zoomLevel = min(WaveformZoomMath.maxZoom, zoomLevel * 1.5) }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(zoomLevel < WaveformZoomMath.maxZoom ? .primary : .tertiary)
                    .disabled(zoomLevel >= WaveformZoomMath.maxZoom)
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
            } else if isSettingDownbeat {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.cyan, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Grid positions based on current snap division
    private var gridPositions: [Float] {
        snapDivision.snapPositions(
            beats: beats, bpm: bpm, duration: duration,
            beatsPerBar: timeSignature.beatsPerBar,
            firstBeatTime: firstDownbeatTime
        )
    }

    /// Bar positions (every `beatsPerBar` beats, starting at `firstDownbeatTime`) for strong lines
    private var barPositions: Set<Float> {
        let bpb = timeSignature.beatsPerBar
        guard bpm > 0, bpb > 0, duration > 0 else { return [] }
        let barDuration: Float = Float(60.0) / bpm * Float(bpb)
        guard barDuration > 0 else { return [] }
        var positions: Set<Float> = []
        var t = firstDownbeatTime
        // Walk forward
        while t < duration {
            if t >= 0 {
                positions.insert((t * 100).rounded() / 100)
            }
            t += barDuration
        }
        // Walk backward from the first downbeat so bars cover the intro as well
        var tBack = firstDownbeatTime - barDuration
        while tBack >= 0 {
            positions.insert((tBack * 100).rounded() / 100)
            tBack -= barDuration
        }
        return positions
    }

    private func barLines(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard duration > 0 else { return }

            let downbeatRounded = (firstDownbeatTime * 100).rounded() / 100

            // Draw grid lines at snap positions
            for gridTime in gridPositions {
                let x = CGFloat(gridTime / duration) * size.width
                let rounded = (gridTime * 100).rounded() / 100
                let isBar = barPositions.contains(rounded)
                let isDownbeatAnchor = abs(rounded - downbeatRounded) < 0.001

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))

                if isDownbeatAnchor {
                    // Red line co-located with the draggable downbeat arrow.
                    context.stroke(path, with: .color(.red.opacity(0.7)), lineWidth: 1.5)
                } else {
                    let opacity: CGFloat = isBar ? 0.45 : 0.2
                    let lw: CGFloat = isBar ? 1.5 : 0.75
                    context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lw)
                }
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
            let midY = size.height / 2
            let n = peaks.count
            let pxPerPeak = size.width / CGFloat(n)

            // Determine how many visual segments to draw: one per pixel for max detail
            let segments = max(Int(size.width), n)
            let peakPerSegment = CGFloat(n) / CGFloat(segments)

            // Played vs unplayed split based on currentTime
            let playedX = duration > 0 ? CGFloat(currentTime / duration) * size.width : 0

            // Build two rectangles per x: one played, one unplayed (split at playhead)
            for s in 0..<segments {
                let x = CGFloat(s) * (size.width / CGFloat(segments))
                let nextX = CGFloat(s + 1) * (size.width / CGFloat(segments))
                // Average peaks in this x window
                let fromIdx = Int(CGFloat(s) * peakPerSegment)
                let toIdx = min(n, Int(CGFloat(s + 1) * peakPerSegment) + 1)
                guard fromIdx < toIdx else { continue }
                var pk: Float = 0
                for i in fromIdx..<toIdx { pk = max(pk, peaks[i]) }
                let halfBar = CGFloat(pk) * size.height * 0.48
                let rect = CGRect(
                    x: x,
                    y: midY - halfBar,
                    width: max(nextX - x, 0.5),
                    height: halfBar * 2
                )
                let color: Color = (x < playedX) ? .blue : .gray.opacity(0.5)
                context.fill(Path(rect), with: .color(color))
            }
            _ = pxPerPeak  // silence unused warning
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func downbeatStrip(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.15))
                .frame(width: width, height: height)
            if duration > 0, firstDownbeatTime >= 0, firstDownbeatTime < duration {
                DownbeatArrowHandle(
                    firstDownbeatTime: firstDownbeatTime,
                    duration: duration,
                    parentWidth: width,
                    parentHeight: height,
                    onSetDownbeat: onSetDownbeat
                )
            }
        }
        .frame(width: width, height: height)
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

