import SwiftUI
import AppKit

struct WaveformView: View {
    let peaks: [Float]
    let sections: [AudioSection]
    let beats: [Float]
    let onsets: [Float]
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
    let onSetDownbeat: ((Float) -> Void)?
    let sectionsVM: SectionsViewModel?
    let selectedSectionId: UUID?
    let onSelectSection: ((UUID?) -> Void)?

    @State private var zoomLevel: CGFloat = 1.0
    @State private var scrollOffset: CGFloat = 0
    @State private var hoverTime: Float?
    @State private var hoverLocation: CGPoint?
    @StateObject private var scrollController = ScrollController()
    @State private var alignDragStartFDT: Float?
    @State private var alignDragActive: Bool = false
    /// Horizontal pixel offset applied to the audio layer during a drag. Keeps
    /// the grid/ruler static (no tile re-rasterization) while the waveform
    /// slides cheaply via a SwiftUI transform. Committed to fDT + scroll on end.
    @State private var waveformDragOffset: CGFloat = 0
    @State private var mouseLocation: CGPoint?
    @State private var highlightedOnset: Float?
    @State private var sectionDragActive: Bool = false
    @State private var sectionDragStartTime: Float?
    @State private var sectionDragCurrentTime: Float?
    @State private var pendingSectionRenameId: UUID?

    private static let onsetSnapMaxPx: Double = 30

    private func nearestOnset(at location: CGPoint?, totalWidth: CGFloat) -> Float? {
        guard let location, totalWidth > 0, duration > 0 else { return nil }
        let pxPerSec = Double(totalWidth) / Double(max(duration, 0.001))
        let time = Float(location.x / totalWidth) * duration
        return OnsetPicker.nearestOnset(
            to: time,
            in: onsets,
            pxPerSec: pxPerSec,
            maxPx: Self.onsetSnapMaxPx
        )
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width * zoomLevel
            let height = geo.size.height

            let bandHeight = WaveformZoomMath.rulerHeight
            let waveHeight = max(0, height - bandHeight)

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

                    ZStack(alignment: .leading) {
                        sectionBands(width: totalWidth, height: waveHeight)
                            .offset(x: waveformDragOffset)
                        if sectionDragActive,
                           let s = sectionDragStartTime,
                           let e = sectionDragCurrentTime {
                            let lo = min(s, e)
                            let hi = max(s, e)
                            let snappedLo: Float = snapToGrid ? gridFloor(lo) : lo
                            let snappedHi: Float = snapToGrid ? gridCeil(hi) : hi
                            let leftX = max(0, CGFloat(snappedLo / duration) * totalWidth)
                            let rightX = min(totalWidth, CGFloat(snappedHi / duration) * totalWidth)
                            let width = max(0, rightX - leftX)
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.18))
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                )
                                .frame(width: width, height: waveHeight)
                                .offset(x: leftX)
                        }
                        if snapToGrid {
                            barLines(width: totalWidth, height: waveHeight)
                        }
                        waveformBars(width: totalWidth, height: waveHeight)
                            .offset(x: waveformDragOffset)

                        if let loop = loopRegion {
                            loopOverlay(loop: loop, width: totalWidth, height: waveHeight)
                                .offset(x: waveformDragOffset)
                        }

                        playhead(width: totalWidth, height: waveHeight)
                            .offset(x: waveformDragOffset)
                        downbeatIndicator(width: totalWidth, height: waveHeight)

                        if let onset = highlightedOnset, duration > 0 {
                            let x = CGFloat(onset / duration) * totalWidth
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.5))
                                .frame(width: 1, height: waveHeight)
                                .offset(x: x)
                                .allowsHitTesting(false)
                        }

                        if let vm = sectionsVM {
                            boundaryHandles(viewModel: vm, width: totalWidth, height: waveHeight)
                                .offset(x: waveformDragOffset)
                        }

                        if let start = pendingLoopStart {
                            pendingLoopMarker(start: start, width: totalWidth, height: waveHeight)
                                .offset(x: waveformDragOffset)
                        }

                        if let time = hoverTime, let loc = hoverLocation {
                            hoverTooltip(time: time, location: loc)
                        }
                    }
                    .frame(width: totalWidth, height: waveHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .local)
                            .onChanged { value in
                                guard totalWidth > 0, duration > 0 else { return }
                                guard !sectionDragActive else { return }
                                if !alignDragActive {
                                    guard NSEvent.modifierFlags.contains(.command) else { return }
                                    alignDragActive = true
                                    alignDragStartFDT = firstDownbeatTime
                                    NSCursor.closedHand.set()
                                }
                                guard let startFDT = alignDragStartFDT else { return }
                                let pxPerSec = totalWidth / CGFloat(duration)
                                // Clamp the visible offset to the range that maps to a
                                // valid fDT in [0, duration], so no rubber-band snap on release.
                                let maxDragRight = CGFloat(startFDT) * pxPerSec
                                let maxDragLeft = CGFloat(Float(duration) - startFDT) * pxPerSec
                                waveformDragOffset = min(max(value.translation.width, -maxDragLeft), maxDragRight)
                            }
                            .onEnded { _ in
                                guard alignDragActive, let startFDT = alignDragStartFDT else {
                                    waveformDragOffset = 0
                                    alignDragActive = false
                                    alignDragStartFDT = nil
                                    NSCursor.arrow.set()
                                    return
                                }
                                let pxPerSec = totalWidth / CGFloat(duration)
                                let deltaSec = Float(waveformDragOffset / pxPerSec)
                                let newFDT = max(0, min(Float(duration), startFDT - deltaSec))

                                // Atomically: commit fDT (grid repositions in content) and
                                // scroll the viewport by the same pixel amount (grid stays
                                // visually pinned; waveform stays at the dragged position).
                                let currentOrigin = scrollController.scrollOriginX
                                let maxOrigin = max(0, totalWidth - geo.size.width)
                                let newScroll = min(max(currentOrigin - waveformDragOffset, 0), maxOrigin)
                                scrollController.setScrollOriginX(newScroll)
                                onSetDownbeat?(newFDT)

                                waveformDragOffset = 0
                                alignDragActive = false
                                alignDragStartFDT = nil
                                NSCursor.arrow.set()
                            }
                    )
                    .simultaneousGesture(
                        // minimumDistance: 8 matches the commit threshold below, and keeps
                        // stationary clicks from activating this drag (so onTapGesture fires
                        // normally for plain-click seek).
                        DragGesture(minimumDistance: 8, coordinateSpace: .local)
                            .onChanged { value in
                                guard totalWidth > 0, duration > 0, sectionsVM != nil else { return }
                                if !sectionDragActive {
                                    guard NSEvent.modifierFlags.contains(.option) else { return }
                                    sectionDragActive = true
                                    sectionDragStartTime = Float(value.startLocation.x / totalWidth) * duration
                                    NSCursor.crosshair.set()
                                }
                                sectionDragCurrentTime = Float(value.location.x / totalWidth) * duration
                            }
                            .onEnded { value in
                                defer {
                                    sectionDragActive = false
                                    sectionDragStartTime = nil
                                    sectionDragCurrentTime = nil
                                    NSCursor.arrow.set()
                                }
                                guard sectionDragActive,
                                      let vm = sectionsVM,
                                      let startT = sectionDragStartTime else { return }
                                let dx = value.location.x - value.startLocation.x
                                guard abs(dx) >= 8 else { return }
                                let rawEnd = Float(value.location.x / totalWidth) * duration
                                // Floor the lower bound, ceil the upper, so any nonzero drag
                                // encloses at least one whole grid cell (matches DAW convention).
                                // Nearest-snap would collapse sub-bar drags to zero length.
                                let lo = min(startT, rawEnd)
                                let hi = max(startT, rawEnd)
                                let snappedLo = snapToGrid ? gridFloor(lo) : lo
                                let snappedHi = snapToGrid ? gridCeil(hi) : hi
                                if let newId = vm.createSection(
                                    startTime: snappedLo,
                                    endTime: snappedHi,
                                    snapToBeat: false
                                ) {
                                    onSelectSection?(newId)
                                    pendingSectionRenameId = newId
                                }
                            }
                    )
                    .onTapGesture { location in
                        let fraction = Float(location.x / totalWidth)
                        let time = fraction * duration
                        if isSettingLoop {
                            onLoopPointSet(time)
                        } else {
                            onSeek(snapToGrid ? nearestGridTime(to: time) : time)
                        }
                    }
                    .contextMenu {
                        let nearest = nearestOnset(at: mouseLocation, totalWidth: totalWidth)
                        Button(action: {
                            if let t = nearest {
                                onSetDownbeat?(t)
                            }
                        }) {
                            Text("Set 1 here")
                            if nearest == nil { Text("No onset nearby") }
                        }
                        .disabled(nearest == nil)
                    }
                    .onChange(of: mouseLocation) { _, newLoc in
                        highlightedOnset = nearestOnset(at: newLoc, totalWidth: totalWidth)
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let fraction = Float(location.x / totalWidth)
                            hoverTime = fraction * duration
                            hoverLocation = location
                            mouseLocation = location
                        case .ended:
                            hoverTime = nil
                            hoverLocation = nil
                            mouseLocation = nil
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

                    Text(formatZoom(zoomLevel))
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
            }
        }
    }

    /// Largest grid position ≤ `t`, or `t` itself if no grid is available or `t` precedes the grid.
    private func gridFloor(_ t: Float) -> Float {
        let grid = gridPositions
        guard !grid.isEmpty else { return t }
        var best: Float = grid.first ?? t
        for g in grid where g <= t + 0.0001 { best = g }
        return best
    }

    /// Smallest grid position ≥ `t`, or `t` itself if no grid is available or `t` exceeds the grid.
    private func gridCeil(_ t: Float) -> Float {
        let grid = gridPositions
        guard !grid.isEmpty else { return t }
        for g in grid where g >= t - 0.0001 { return g }
        return grid.last ?? t
    }

    /// Nearest grid-snap time to `t`, or `t` itself if no grid is available.
    private func nearestGridTime(to t: Float) -> Float {
        let grid = gridPositions
        guard !grid.isEmpty else { return t }
        var best = grid[0]
        var bestDist = abs(best - t)
        for g in grid.dropFirst() {
            let d = abs(g - t)
            if d < bestDist {
                best = g
                bestDist = d
            }
        }
        return best
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
        TiledCanvas(totalWidth: width, height: height) { context, size, xRange in
            guard duration > 0 else { return }
            let pad: CGFloat = 2

            for gridTime in gridPositions {
                let x = CGFloat(gridTime / duration) * size.width
                if x < xRange.lowerBound - pad || x > xRange.upperBound + pad { continue }
                let rounded = (gridTime * 100).rounded() / 100
                let isBar = barPositions.contains(rounded)

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))

                let opacity: CGFloat = isBar ? 0.45 : 0.2
                let lw: CGFloat = isBar ? 1.5 : 0.75
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lw)
            }
        }
        .allowsHitTesting(false)
    }

    private func sectionBands(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(sections) { section in
                let sectionX = CGFloat(section.startTime / duration) * width
                let sectionWidth = CGFloat((section.endTime - section.startTime) / duration) * width
                let isSelected = section.stableId == selectedSectionId

                // Band background
                Rectangle()
                    .fill(section.color.opacity(isSelected ? 0.25 : 0.1))
                    .overlay(
                        Rectangle()
                            .strokeBorder(section.color, lineWidth: isSelected ? 2 : 0)
                    )
                    .frame(width: sectionWidth, height: height)
                    .offset(x: sectionX)

                // Label badge (only if the band has room to show it)
                if sectionWidth >= 20 {
                    SectionLabelBadge(
                        label: section.label,
                        color: section.color,
                        isSelected: isSelected,
                        isRenaming: Binding(
                            get: { pendingSectionRenameId == section.stableId },
                            set: { if !$0 { pendingSectionRenameId = nil } }
                        ),
                        onCommitRename: { newLabel in
                            sectionsVM?.rename(sectionId: section.stableId, to: newLabel)
                        },
                        onTap: { onSelectSection?(section.stableId) },
                        contextMenuContent: {
                            AnyView(
                                Group {
                                    Button("Rename") { pendingSectionRenameId = section.stableId }
                                    Menu("Change Color") {
                                        ForEach(0..<8, id: \.self) { idx in
                                            Button(action: {
                                                sectionsVM?.recolor(sectionId: section.stableId, colorIndex: idx)
                                            }) {
                                                Text("•").foregroundColor(AudioSection.color(forIndex: idx))
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        sectionsVM?.delete(sectionId: section.stableId)
                                        if selectedSectionId == section.stableId {
                                            onSelectSection?(nil)
                                        }
                                    }
                                }
                            )
                        }
                    )
                    .padding(.leading, 4)
                    .padding(.top, 3)
                    .offset(x: sectionX)
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    @ViewBuilder
    private func boundaryHandles(viewModel vm: SectionsViewModel, width: CGFloat, height: CGFloat) -> some View {
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
        TiledCanvas(totalWidth: width, height: height) { context, size, xRange in
            guard !peaks.isEmpty else { return }
            let midY = size.height / 2
            let n = peaks.count

            // Draw at most one rect per peak (when zoomed in) or one per pixel
            // (when zoomed out) — whichever is smaller. Prevents stretched
            // staircase at high zoom and caps the draw count at low zoom.
            let segments = max(1, min(Int(size.width), n))
            let peakPerSegment = CGFloat(n) / CGFloat(segments)
            let segmentWidth = size.width / CGFloat(segments)

            let playedX = duration > 0 ? CGFloat(currentTime / duration) * size.width : 0

            // Only iterate segments that fall inside this tile's x-range.
            let firstSeg = max(0, Int(floor(xRange.lowerBound / segmentWidth)) - 1)
            let lastSeg = min(segments, Int(ceil(xRange.upperBound / segmentWidth)) + 1)
            for s in firstSeg..<lastSeg {
                let x = CGFloat(s) * segmentWidth
                let fromIdx = Int(CGFloat(s) * peakPerSegment)
                let toIdx = min(n, max(fromIdx + 1, Int(CGFloat(s + 1) * peakPerSegment)))
                var pk: Float = 0
                for i in fromIdx..<toIdx { pk = max(pk, peaks[i]) }
                let halfBar = CGFloat(pk) * size.height * 0.48
                let rect = CGRect(
                    x: x,
                    y: midY - halfBar,
                    width: max(segmentWidth, 0.5),
                    height: halfBar * 2
                )
                let color: Color = (x < playedX) ? .blue : .gray.opacity(0.5)
                context.fill(Path(rect), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func downbeatIndicator(width: CGFloat, height: CGFloat) -> some View {
        if duration > 0 {
            let clamped = max(0, min(firstDownbeatTime, duration))
            let x = CGFloat(clamped / duration) * width
            Rectangle()
                .fill(Color.red.opacity(0.75))
                .frame(width: 1.5, height: height)
                .offset(x: x)
                .allowsHitTesting(false)
        }
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

    private func formatZoom(_ zoom: CGFloat) -> String {
        if zoom >= 9.95 {
            return "x\(Int(zoom.rounded()))"
        } else if abs(zoom - zoom.rounded()) < 0.05 {
            return "x\(Int(zoom.rounded()))"
        } else {
            return String(format: "x%.1f", Double(zoom))
        }
    }

    private func formatTime(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

