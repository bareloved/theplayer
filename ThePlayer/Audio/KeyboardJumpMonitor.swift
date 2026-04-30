// ThePlayer/Audio/KeyboardJumpMonitor.swift
import AppKit
import Foundation

/// Snapshot of state needed to handle a keypress. Re-fetched on every event
/// (via the closure passed to `KeyboardJumpMonitor`), so the monitor never
/// holds stale snap / analysis values.
struct JumpContext {
    let snapToGrid: Bool
    let analysis: TrackAnalysis?
    let duration: Float
}

/// Owns an `NSEvent.addLocalMonitorForEvents` handler that translates
/// arrow-key presses (with optional modifiers) into seeks on `AudioEngine`.
/// Mapping (Snap on / off):
///
///     (none)      1 bar  / 1 s
///     shift       2 bars / 2 s
///     option      4 bars / 5 s
///     cmd         8 bars / 15 s
///     cmd+shift  16 bars / 30 s
///
/// Any other modifier combination is passed through untouched. Text-input
/// first responders (search fields, rename fields) are passed through too.
@MainActor
final class KeyboardJumpMonitor {
    private var token: Any?
    private let audioEngine: AudioEngine
    private let context: () -> JumpContext

    init(audioEngine: AudioEngine, context: @escaping () -> JumpContext) {
        self.audioEngine = audioEngine
        self.context = context
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    // MARK: - Private

    private static let keyCodeLeftArrow: UInt16 = 0x7B
    private static let keyCodeRightArrow: UInt16 = 0x7C

    private func handle(_ event: NSEvent) -> NSEvent? {
        let direction: JumpDirection
        switch event.keyCode {
        case Self.keyCodeLeftArrow:  direction = .backward
        case Self.keyCodeRightArrow: direction = .forward
        default: return event
        }

        // Pass through if a text input has focus.
        if let responder = NSApp.keyWindow?.firstResponder {
            if responder is NSText { return event }
        }

        // Only handle the five claimed modifier combos. Strip caps lock / numpad / fn.
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        let bars: Int
        let seconds: Float
        switch mods {
        case []:                  bars = 1;  seconds = 1
        case [.shift]:            bars = 2;  seconds = 2
        case [.option]:           bars = 4;  seconds = 5
        case [.command]:          bars = 8;  seconds = 15
        case [.command, .shift]:  bars = 16; seconds = 30
        default: return event
        }

        let ctx = context()
        let target: Float?
        if ctx.snapToGrid {
            guard let analysis = ctx.analysis else {
                // Snap-ON requires analysis. Consume the event so there is no beep,
                // but do not move the playhead.
                return nil
            }
            target = JumpMath.nextBarTime(
                from: audioEngine.currentTime,
                direction: direction,
                bars: bars,
                bpm: analysis.bpm,
                beatsPerBar: analysis.timeSignature.beatsPerBar,
                firstBeatTime: analysis.firstDownbeatTime,
                duration: ctx.duration
            )
        } else {
            target = JumpMath.nextSecondTime(
                from: audioEngine.currentTime,
                direction: direction,
                seconds: seconds,
                duration: ctx.duration
            )
        }

        if let t = target {
            audioEngine.seek(to: t)
        }
        return nil  // consume — no system beep
    }
}
