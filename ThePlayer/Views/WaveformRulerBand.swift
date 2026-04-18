import AppKit
import SwiftUI

/// Visible ruler band drawn above the waveform. Shows bar numbers (1, 2, 3, ...)
/// starting at `firstDownbeatTime`, with beat tick marks between bars.
/// Owns:
///   - the draggable downbeat triangle
///   - the Ableton-style vertical-drag-to-zoom gesture
struct WaveformRulerBand: View {
    let duration: Float
    let bpm: Float
    let firstDownbeatTime: Float
    let timeSignature: TimeSignature
    let totalWidth: CGFloat
    let geoWidth: CGFloat
    let bandHeight: CGFloat
    @Binding var zoomLevel: CGFloat
    let scrollController: ScrollController

    private enum DragMode { case undecided, zoom, pan }

    @State private var dragMode: DragMode = .undecided
    @State private var dragStartZoom: CGFloat?
    @State private var dragAnchorFraction: CGFloat?
    @State private var dragCursorXInViewport: CGFloat?
    @State private var dragStartScrollOriginX: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background + zoom-drag gesture layer.
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(width: totalWidth, height: bandHeight)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
                }
                .gesture(zoomDrag)

            // Tick marks + bar labels.
            TiledCanvas(totalWidth: totalWidth, height: bandHeight) { context, size, xRange in
                drawTicksAndLabels(in: &context, size: size, xRange: xRange)
            }
            .allowsHitTesting(false)
        }
        .frame(width: totalWidth, height: bandHeight)
    }

    private var zoomDrag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if dragMode == .undecided {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) >= 3 else { return }
                    dragMode = dx > dy ? .pan : .zoom

                    if dragMode == .zoom {
                        dragStartZoom = zoomLevel
                        let startContentX = value.startLocation.x
                        let totalAtStart = geoWidth * zoomLevel
                        dragAnchorFraction = totalAtStart > 0 ? startContentX / totalAtStart : 0
                        dragCursorXInViewport = startContentX - scrollController.scrollOriginX
                    } else {
                        dragStartScrollOriginX = scrollController.scrollOriginX
                        NSCursor.closedHand.set()
                    }
                }

                switch dragMode {
                case .pan:
                    guard let startOrigin = dragStartScrollOriginX else { return }
                    let maxOrigin = max(0, totalWidth - geoWidth)
                    let newOrigin = min(max(startOrigin - value.translation.width, 0), maxOrigin)
                    scrollController.setScrollOriginX(newOrigin)
                case .zoom:
                    guard
                        let startZoom = dragStartZoom,
                        let anchor = dragAnchorFraction,
                        let cursorX = dragCursorXInViewport,
                        geoWidth > 0
                    else { return }

                    let newZoom = WaveformZoomMath.zoomFromDrag(
                        startZoom: startZoom,
                        translationY: value.translation.height
                    )
                    zoomLevel = newZoom

                    let newOrigin = WaveformZoomMath.scrollOriginForAnchor(
                        anchorFraction: anchor,
                        cursorXInViewport: cursorX,
                        geoWidth: geoWidth,
                        newZoom: newZoom
                    )
                    DispatchQueue.main.async {
                        scrollController.setScrollOriginX(newOrigin)
                    }
                case .undecided:
                    break
                }
            }
            .onEnded { _ in
                if dragMode == .pan { NSCursor.openHand.set() }
                dragMode = .undecided
                dragStartZoom = nil
                dragAnchorFraction = nil
                dragCursorXInViewport = nil
                dragStartScrollOriginX = nil
            }
    }

    private func drawTicksAndLabels(in context: inout GraphicsContext, size: CGSize, xRange: ClosedRange<CGFloat>) {
        guard duration > 0, bpm > 0 else { return }
        let bpb = timeSignature.beatsPerBar
        guard bpb > 0 else { return }
        let beatDuration: Float = 60.0 / bpm
        let barDuration: Float = beatDuration * Float(bpb)
        guard barDuration > 0 else { return }

        let w = size.width
        let h = size.height
        // Label text can extend ~24pt to the right of its anchor x.
        let pad: CGFloat = 32
        let xLo = xRange.lowerBound - pad
        let xHi = xRange.upperBound + pad
        let barTickColor = GraphicsContext.Shading.color(.white.opacity(0.55))
        let beatTickColor = GraphicsContext.Shading.color(.white.opacity(0.22))
        let preDownbeatTickColor = GraphicsContext.Shading.color(.white.opacity(0.2))

        // Pixel width of one bar / one beat at current zoom.
        let barPxWidth = CGFloat(barDuration / duration) * w
        let beatPxWidth = CGFloat(beatDuration / duration) * w

        // Choose power-of-two strides so labels / ticks never crowd.
        let labelStride = niceStride(minPx: 32, itemPx: barPxWidth)
        let barTickStride = niceStride(minPx: 6, itemPx: barPxWidth)
        let drawBeatTicks = beatPxWidth >= 6

        // Bars at/after firstDownbeatTime — labeled 1, 2, 3, ...
        var barIndex = 1
        var t = firstDownbeatTime
        while t < duration {
            if t >= 0 {
                let x = CGFloat(t / duration) * w
                if x > xHi { break }
                if x >= xLo {
                    let zeroBased = barIndex - 1
                    if zeroBased % barTickStride == 0 {
                        var tick = Path()
                        tick.move(to: CGPoint(x: x, y: h * 0.55))
                        tick.addLine(to: CGPoint(x: x, y: h))
                        context.stroke(tick, with: barTickColor, lineWidth: 1)
                    }
                    if zeroBased % labelStride == 0 {
                        let label = Text("\(barIndex)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundColor(.white.opacity(0.85))
                        context.draw(label, at: CGPoint(x: x + 3, y: 1), anchor: .topLeading)
                    }
                }
            }
            barIndex += 1
            t += barDuration
        }

        // Beat ticks between bars, at/after firstDownbeatTime — only when zoomed in enough.
        if drawBeatTicks {
            var tb = firstDownbeatTime
            while tb < duration {
                let tbX = CGFloat(tb / duration) * w
                if tbX > xHi { break }
                if tbX + barPxWidth >= xLo {
                    for b in 1..<bpb {
                        let bt = tb + Float(b) * beatDuration
                        if bt >= 0, bt < duration {
                            let x = CGFloat(bt / duration) * w
                            if x < xLo || x > xHi { continue }
                            var tick = Path()
                            tick.move(to: CGPoint(x: x, y: h * 0.75))
                            tick.addLine(to: CGPoint(x: x, y: h))
                            context.stroke(tick, with: beatTickColor, lineWidth: 0.75)
                        }
                    }
                }
                tb += barDuration
            }
        }

        // Bars + beats before firstDownbeatTime (no labels, dimmer, same stride).
        var backIndex = 1
        var tBack = firstDownbeatTime - barDuration
        while tBack >= 0 {
            let x = CGFloat(tBack / duration) * w
            if x < xLo - barPxWidth { break }
            if x <= xHi {
                if backIndex % barTickStride == 0, x >= xLo {
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: h * 0.55))
                    tick.addLine(to: CGPoint(x: x, y: h))
                    context.stroke(tick, with: preDownbeatTickColor, lineWidth: 1)
                }
                if drawBeatTicks {
                    for b in 1..<bpb {
                        let bt = tBack + Float(b) * beatDuration
                        if bt >= 0, bt < duration {
                            let bx = CGFloat(bt / duration) * w
                            if bx < xLo || bx > xHi { continue }
                            var btick = Path()
                            btick.move(to: CGPoint(x: bx, y: h * 0.75))
                            btick.addLine(to: CGPoint(x: bx, y: h))
                            context.stroke(btick, with: preDownbeatTickColor, lineWidth: 0.75)
                        }
                    }
                }
            }
            backIndex += 1
            tBack -= barDuration
        }
    }

    /// Smallest power-of-two stride such that `stride * itemPx >= minPx`.
    private func niceStride(minPx: CGFloat, itemPx: CGFloat) -> Int {
        guard itemPx > 0 else { return 1 }
        var s = 1
        while CGFloat(s) * itemPx < minPx { s *= 2 }
        return s
    }
}

