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
    let isLoopEnabled: Bool
    let onSeek: (Float) -> Void
    let onLoopRegionSet: (LoopRegion) -> Void
    let firstDownbeatTime: Float
    let timeSignature: TimeSignature
    let onSetDownbeat: ((Float) -> Void)?
    let sectionsVM: SectionsViewModel?
    let selectedSectionId: UUID?
    let onSelectSection: ((UUID?) -> Void)?
    let onBoundaryDragChange: ((Bool) -> Void)?

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
    @State private var loopDragActive: Bool = false
    @State private var loopDragStartTime: Float?
    @State private var loopDragCurrentTime: Float?
    @State private var pendingSectionRenameId: UUID?
    @State private var cachedGridPositions: [Float] = []
    @State private var cachedBarPositions: Set<Float> = []
    @State private var isOptionHeld: Bool = false
    @State private var flagsMonitor: Any?

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
            // Reserve room at the bottom so the overlay horizontal scroller
            // doesn't land on top of the waveform bars.
            let scrollerReserved: CGFloat = HorizontalNSScrollView<AnyView>.overlayScrollerReservedHeight
            let waveHeight = max(0, height - bandHeight - scrollerReserved)

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
                        scrollController: scrollController,
                        loopRegion: loopRegion,
                        isLoopEnabled: isLoopEnabled
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
                        if loopDragActive,
                           let s = loopDragStartTime,
                           let e = loopDragCurrentTime {
                            let lo = min(s, e)
                            let hi = max(s, e)
                            let snappedLo: Float = snapToGrid ? gridFloor(lo) : lo
                            let snappedHi: Float = snapToGrid ? gridCeil(hi) : hi
                            let leftX = max(0, CGFloat(snappedLo / duration) * totalWidth)
                            let rightX = min(totalWidth, CGFloat(snappedHi / duration) * totalWidth)
                            let width = max(0, rightX - leftX)
                            Rectangle()
                                .fill(Color.blue.opacity(0.18))
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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

                        if let vm = sectionsVM {
                            boundaryHandles(viewModel: vm, width: totalWidth, height: waveHeight)
                                .offset(x: waveformDragOffset)
                        }

                        if let time = hoverTime, let loc = hoverLocation, duration > 0 {
                            let displayTime = snapToGrid ? nearestBeatTime(to: time) : time
                            let hoverX = CGFloat(displayTime / duration) * totalWidth
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: 1, height: waveHeight)
                                .position(x: hoverX, y: waveHeight / 2)
                                .allowsHitTesting(false)
                            hoverTooltip(time: displayTime, location: CGPoint(x: hoverX, y: loc.y))
                        }

                        // Section label badges are rendered LAST so they sit on
                        // top of every other layer (bars, playhead, boundary
                        // handles, loop overlay, etc.).
                        sectionLabels(width: totalWidth, height: waveHeight)
                            .offset(x: waveformDragOffset)
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
                        // minimumDistance: 8 keeps stationary clicks from triggering this
                        // gesture so plain-click seek still works.
                        DragGesture(minimumDistance: 8, coordinateSpace: .local)
                            .onChanged { value in
                                guard totalWidth > 0, duration > 0 else { return }
                                if !loopDragActive {
                                    guard NSEvent.modifierFlags.contains(.shift) else { return }
                                    if NSEvent.modifierFlags.contains(.option) { return }
                                    if NSEvent.modifierFlags.contains(.command) { return }
                                    loopDragActive = true
                                    loopDragStartTime = Float(value.startLocation.x / totalWidth) * duration
                                    NSCursor.crosshair.set()
                                }
                                loopDragCurrentTime = Float(value.location.x / totalWidth) * duration
                            }
                            .onEnded { value in
                                defer {
                                    loopDragActive = false
                                    loopDragStartTime = nil
                                    loopDragCurrentTime = nil
                                    NSCursor.arrow.set()
                                }
                                guard loopDragActive,
                                      let startT = loopDragStartTime else { return }
                                let dx = value.location.x - value.startLocation.x
                                guard abs(dx) >= 8 else { return }
                                let rawEnd = Float(value.location.x / totalWidth) * duration
                                let lo = min(startT, rawEnd)
                                let hi = max(startT, rawEnd)
                                let snappedLo = snapToGrid ? gridFloor(lo) : lo
                                let snappedHi = snapToGrid ? gridCeil(hi) : hi
                                guard snappedHi - snappedLo > 0.1 else { return }
                                onLoopRegionSet(LoopRegion(startTime: snappedLo, endTime: snappedHi))
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
                        let snapped = snapToGrid ? nearestBeatTime(to: time) : time
                        onSeek(snapped)
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
                .frame(width: totalWidth, height: height, alignment: .top)
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
        .onAppear {
            recomputeGridCaches()
            isOptionHeld = NSEvent.modifierFlags.contains(.option)
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isOptionHeld = event.modifierFlags.contains(.option)
                return event
            }
        }
        .onDisappear {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
        }
        .onChange(of: bpm) { _, _ in recomputeGridCaches() }
        .onChange(of: duration) { _, _ in recomputeGridCaches() }
        .onChange(of: firstDownbeatTime) { _, _ in recomputeGridCaches() }
        .onChange(of: timeSignature) { _, _ in recomputeGridCaches() }
        .onChange(of: snapDivision) { _, _ in recomputeGridCaches() }
        .onChange(of: beats) { _, _ in recomputeGridCaches() }
    }

    private func recomputeGridCaches() {
        cachedGridPositions = gridPositions
        cachedBarPositions = barPositions
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

    /// Nearest beat time to `t`. Uses BPM-derived beat positions (independent of
    /// the bar-level `snapDivision`), so seek/hover snap feels musical.
    private func nearestBeatTime(to t: Float) -> Float {
        guard bpm > 0, duration > 0 else { return t }
        let beatDuration: Float = 60.0 / bpm
        guard beatDuration > 0 else { return t }
        let origin: Float = firstDownbeatTime
        let n = ((t - origin) / beatDuration).rounded()
        let snapped = origin + n * beatDuration
        return min(max(snapped, 0), duration)
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
        // Snapshot once per view evaluation; closures below capture by value
        // so the per-tile redraw doesn't recompute either.
        let grid = cachedGridPositions
        let bars = cachedBarPositions
        return TiledCanvas(totalWidth: width, height: height) { context, size, xRange in
            guard duration > 0 else { return }
            let pad: CGFloat = 2

            // Build one combined path per stroke style, fill each once.
            var barPath = Path()
            var beatPath = Path()
            for gridTime in grid {
                let x = CGFloat(gridTime / duration) * size.width
                if x < xRange.lowerBound - pad || x > xRange.upperBound + pad { continue }
                let rounded = (gridTime * 100).rounded() / 100
                let isBar = bars.contains(rounded)
                if isBar {
                    barPath.move(to: CGPoint(x: x, y: 0))
                    barPath.addLine(to: CGPoint(x: x, y: size.height))
                } else {
                    beatPath.move(to: CGPoint(x: x, y: 0))
                    beatPath.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            context.stroke(beatPath, with: .color(.white.opacity(0.2)), lineWidth: 0.75)
            context.stroke(barPath, with: .color(.white.opacity(0.45)), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }

    private func sectionBands(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(sections) { section in
                let sectionX = CGFloat(section.startTime / duration) * width
                let sectionWidth = CGFloat((section.endTime - section.startTime) / duration) * width
                let isSelected = section.stableId == selectedSectionId

                Rectangle()
                    .fill(section.color.opacity(isSelected ? 0.25 : 0.1))
                    .overlay(
                        Rectangle()
                            .strokeBorder(section.color, lineWidth: isSelected ? 2 : 0)
                    )
                    .frame(width: sectionWidth, height: height)
                    .offset(x: sectionX)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    /// Label badges rendered in a separate layer above the waveform bars so the
    /// bars don't obscure the section titles.
    private func sectionLabels(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(sections) { section in
                let sectionX = CGFloat(section.startTime / duration) * width
                let sectionWidth = CGFloat((section.endTime - section.startTime) / duration) * width
                let isSelected = section.stableId == selectedSectionId
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
                    .padding(.top, 8)
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
                    isDisabled: isOptionHeld,
                    onDragChanged: { targetX in
                        let newTime = Float(targetX / width) * duration
                        let snap = !NSEvent.modifierFlags.contains(.option)
                        vm.moveBoundary(beforeSectionId: section.stableId, toTime: newTime, snapToBeat: snap)
                    },
                    onDragStarted: { onBoundaryDragChange?(true) },
                    onDragEnded: { onBoundaryDragChange?(false) }
                )
            }
        }
    }

    private func waveformBars(width: CGFloat, height: CGFloat) -> some View {
        // Played-overlay width depends on currentTime, but lives OUTSIDE the
        // bar-rendering Canvas — so the gray and blue envelope tiles are not
        // re-rasterized on every 60 Hz playhead tick. Only the cheap mask
        // rectangle's width changes; SwiftUI's compositor adjusts the clip
        // region without rebuilding the underlying tile textures.
        let playedX = duration > 0 ? CGFloat(currentTime / duration) * width : 0
        return ZStack(alignment: .leading) {
            WaveformBarsLayer(peaks: peaks, totalWidth: width, height: height, color: Color.gray.opacity(0.5))
                .equatable()
            WaveformBarsLayer(peaks: peaks, totalWidth: width, height: height, color: .blue)
                .equatable()
                .mask(alignment: .leading) {
                    Rectangle().frame(width: max(0, playedX), height: height)
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
        let tintColor: Color = isLoopEnabled ? .blue : .gray
        let tintOpacity: Double = isLoopEnabled ? 0.08 : 0.05
        return Rectangle()
            .fill(tintColor.opacity(tintOpacity))
            .frame(width: max(0, endX - startX), height: height)
            .offset(x: startX)
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

/// Stable bar layer extracted from `WaveformView` so SwiftUI's diff can skip
/// re-rendering the heavy tiled Canvas when only `currentTime` changes in the
/// parent. With `.equatable()`, SwiftUI compares props memberwise — and since
/// peaks/width/height/color don't change per playhead tick, the underlying
/// `TiledCanvas` tiles keep their cached textures.
struct WaveformBarsLayer: View, Equatable {
    let peaks: [Float]
    let totalWidth: CGFloat
    let height: CGFloat
    let color: Color

    static func == (lhs: WaveformBarsLayer, rhs: WaveformBarsLayer) -> Bool {
        lhs.totalWidth == rhs.totalWidth &&
        lhs.height == rhs.height &&
        lhs.color == rhs.color &&
        lhs.peaks == rhs.peaks   // Array == short-circuits on buffer-identity (COW)
    }

    var body: some View {
        TiledCanvas(totalWidth: totalWidth, height: height) { context, size, xRange in
            guard !peaks.isEmpty else { return }
            let midY = size.height / 2
            let n = peaks.count

            let segments = max(1, min(Int(size.width), n))
            let peakPerSegment = CGFloat(n) / CGFloat(segments)
            let segmentWidth = size.width / CGFloat(segments)

            let firstSeg = max(0, Int(floor(xRange.lowerBound / segmentWidth)) - 1)
            let lastSeg = min(segments, Int(ceil(xRange.upperBound / segmentWidth)) + 1)
            guard lastSeg > firstSeg else { return }

            var samples: [(x: CGFloat, half: CGFloat)] = []
            samples.reserveCapacity(lastSeg - firstSeg)
            for s in firstSeg..<lastSeg {
                let x = (CGFloat(s) + 0.5) * segmentWidth
                var pk: Float = 0
                if peakPerSegment >= 1 {
                    let fromIdx = Int(CGFloat(s) * peakPerSegment)
                    let toIdx = min(n, max(fromIdx + 1, Int(CGFloat(s + 1) * peakPerSegment)))
                    for i in fromIdx..<toIdx { pk = max(pk, peaks[i]) }
                } else {
                    let pIdx = (CGFloat(s) + 0.5) * peakPerSegment
                    let i0 = max(0, min(n - 1, Int(pIdx)))
                    let i1 = min(n - 1, i0 + 1)
                    let frac = Float(pIdx - CGFloat(i0))
                    pk = peaks[i0] * (1 - frac) + peaks[i1] * frac
                }
                samples.append((x, CGFloat(pk) * size.height * 0.48))
            }

            var env = Path()
            env.move(to: CGPoint(x: samples[0].x, y: midY - samples[0].half))
            for s in samples.dropFirst() {
                env.addLine(to: CGPoint(x: s.x, y: midY - s.half))
            }
            for s in samples.reversed() {
                env.addLine(to: CGPoint(x: s.x, y: midY + s.half))
            }
            env.closeSubpath()

            context.fill(env, with: .color(color))
        }
    }
}

