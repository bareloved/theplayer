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
    let onSetDownbeat: ((Float) -> Void)?
    let onSeek: (Float) -> Void

    private enum DragMode { case undecided, zoom, scrub }

    @State private var dragMode: DragMode = .undecided
    @State private var dragStartZoom: CGFloat?
    @State private var dragAnchorFraction: CGFloat?
    @State private var dragCursorXInViewport: CGFloat?

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
            Canvas { context, size in
                drawTicksAndLabels(in: context, size: size)
            }
            .frame(width: totalWidth, height: bandHeight)
            .allowsHitTesting(false)

            // Downbeat triangle — child gesture wins over the band's zoom drag.
            if duration > 0, firstDownbeatTime >= 0, firstDownbeatTime < duration {
                DownbeatArrowHandle(
                    firstDownbeatTime: firstDownbeatTime,
                    duration: duration,
                    parentWidth: totalWidth,
                    parentHeight: bandHeight,
                    onSetDownbeat: onSetDownbeat
                )
            }
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
                    dragMode = dx > dy ? .scrub : .zoom

                    if dragMode == .zoom {
                        dragStartZoom = zoomLevel
                        let startContentX = value.startLocation.x
                        let totalAtStart = geoWidth * zoomLevel
                        dragAnchorFraction = totalAtStart > 0 ? startContentX / totalAtStart : 0
                        dragCursorXInViewport = startContentX - scrollController.scrollOriginX
                    }
                }

                switch dragMode {
                case .scrub:
                    guard totalWidth > 0, duration > 0 else { return }
                    let fraction = Float(value.location.x / totalWidth)
                    let time = max(0, min(duration, fraction * duration))
                    onSeek(time)
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
                dragMode = .undecided
                dragStartZoom = nil
                dragAnchorFraction = nil
                dragCursorXInViewport = nil
            }
    }

    private func drawTicksAndLabels(in context: GraphicsContext, size: CGSize) {
        guard duration > 0, bpm > 0 else { return }
        let bpb = timeSignature.beatsPerBar
        guard bpb > 0 else { return }
        let beatDuration: Float = 60.0 / bpm
        let barDuration: Float = beatDuration * Float(bpb)
        guard barDuration > 0 else { return }

        let w = size.width
        let h = size.height
        let barTickColor = GraphicsContext.Shading.color(.white.opacity(0.55))
        let beatTickColor = GraphicsContext.Shading.color(.white.opacity(0.22))
        let preDownbeatTickColor = GraphicsContext.Shading.color(.white.opacity(0.2))

        // Bars at/after firstDownbeatTime — labeled 1, 2, 3, ...
        var barIndex = 1
        var t = firstDownbeatTime
        while t < duration {
            if t >= 0 {
                let x = CGFloat(t / duration) * w
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 0))
                tick.addLine(to: CGPoint(x: x, y: h))
                context.stroke(tick, with: barTickColor, lineWidth: 1)

                let label = Text("\(barIndex)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
                context.draw(label, at: CGPoint(x: x + 3, y: 1), anchor: .topLeading)
            }
            barIndex += 1
            t += barDuration
        }

        // Beat ticks between bars, at/after firstDownbeatTime.
        var tb = firstDownbeatTime
        while tb < duration {
            for b in 1..<bpb {
                let bt = tb + Float(b) * beatDuration
                if bt >= 0, bt < duration {
                    let x = CGFloat(bt / duration) * w
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: h * 0.55))
                    tick.addLine(to: CGPoint(x: x, y: h))
                    context.stroke(tick, with: beatTickColor, lineWidth: 0.75)
                }
            }
            tb += barDuration
        }

        // Bars + beats before firstDownbeatTime (no labels, dimmer).
        var tBack = firstDownbeatTime - barDuration
        while tBack >= 0 {
            let x = CGFloat(tBack / duration) * w
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: 0))
            tick.addLine(to: CGPoint(x: x, y: h))
            context.stroke(tick, with: preDownbeatTickColor, lineWidth: 1)

            for b in 1..<bpb {
                let bt = tBack + Float(b) * beatDuration
                if bt >= 0, bt < duration {
                    let bx = CGFloat(bt / duration) * w
                    var btick = Path()
                    btick.move(to: CGPoint(x: bx, y: h * 0.55))
                    btick.addLine(to: CGPoint(x: bx, y: h))
                    context.stroke(btick, with: preDownbeatTickColor, lineWidth: 0.75)
                }
            }
            tBack -= barDuration
        }
    }
}

/// Single red downbeat arrow that sits on top of the ruler band and can be dragged
/// to move the first-downbeat time continuously.
struct DownbeatArrowHandle: View {
    let firstDownbeatTime: Float
    let duration: Float
    let parentWidth: CGFloat
    let parentHeight: CGFloat
    let onSetDownbeat: ((Float) -> Void)?

    @State private var dragStartTime: Float?

    var body: some View {
        let x = duration > 0 ? CGFloat(firstDownbeatTime / duration) * parentWidth : 0

        ZStack(alignment: .topLeading) {
            // Invisible hit target — extends -5..17 (width 22) around the 0..12 triangle.
            Rectangle()
                .fill(Color.clear)
                .frame(width: 22, height: max(parentHeight, 20))
                .contentShape(Rectangle())
                .offset(x: -5, y: 0)
            // Visible triangle — tip at local x = 6.
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 12, y: 0))
                p.addLine(to: CGPoint(x: 6, y: 10))
                p.closeSubpath()
            }
            .fill(Color.red)
            .frame(width: 12, height: 10)
        }
        .frame(width: 12, height: max(parentHeight, 20), alignment: .topLeading)
        .offset(x: x - 6, y: 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartTime == nil { dragStartTime = firstDownbeatTime }
                    guard parentWidth > 0, duration > 0 else { return }
                    let deltaTime = Float(value.translation.width / parentWidth) * duration
                    let newTime = (dragStartTime ?? firstDownbeatTime) + deltaTime
                    onSetDownbeat?(max(0, min(duration, newTime)))
                }
                .onEnded { _ in
                    dragStartTime = nil
                }
        )
    }
}
