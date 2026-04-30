import SwiftUI

struct TransportBar: View {
    @Bindable var audioEngine: AudioEngine
    @Binding var loopRegion: LoopRegion?
    @Binding var isLoopEnabled: Bool
    @Binding var snapToGrid: Bool
    let isInSetlist: Bool
    let onNextInSetlist: () -> Void
    let timingControls: AnyView?
    @State private var showEmptyHint: Bool = false
    @State private var showSnapHint: Bool = false
    @State private var snapHintTask: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 8) {
            utilityRow
            mainRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Top row — utility controls (A-B, Snap). Centered.
    private var utilityRow: some View {
        HStack(spacing: 12) {
            Button(action: toggleLoopEnabled) {
                Label("Loop", systemImage: "repeat")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(loopRegion != nil && isLoopEnabled ? .blue : .secondary)
            .help("Shift+drag waveform to set loop")
            .popover(isPresented: $showEmptyHint, arrowEdge: .top) {
                Text("Shift+drag the waveform to set a loop")
                    .font(.caption)
                    .padding(8)
            }

            Button(action: { snapToGrid.toggle() }) {
                Label("Snap", systemImage: "grid")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(snapToGrid ? .purple : .secondary)
            .popover(isPresented: $showSnapHint, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snap on:  ←/→ 1 bar · ⇧ 2 · ⌥ 4 · ⌘ 8 · ⌘⇧ 16")
                    Text("Snap off: ←/→ 1 s · ⇧ 2 s · ⌥ 5 s · ⌘ 15 s · ⌘⇧ 30 s")
                }
                .font(.caption)
                .padding(8)
            }
            .onHover { hovering in
                snapHintTask?.cancel()
                if hovering {
                    let task = DispatchWorkItem { showSnapHint = true }
                    snapHintTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
                } else {
                    showSnapHint = false
                }
            }

            if isInSetlist {
                Button(action: onNextInSetlist) {
                    Label("Next", systemImage: "forward.end.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }

            if let timingControls { timingControls }
        }
    }

    /// Bottom row — Speed on left, transport dead-center via ZStack, Pitch on right.
    private var mainRow: some View {
        ZStack {
            HStack {
                SpeedPitchControl(
                    label: "Speed",
                    value: $audioEngine.speed,
                    range: 0.25...2.0,
                    step: 0.05,
                    unit: "%",
                    color: .blue,
                    formatter: { "\(Int($0 * 100))" },
                    defaultValue: 1.0,
                    snapPoints: [0.5, 1.0, 1.5],
                    sliderWidth: 160
                )

                Spacer()

                SpeedPitchControl(
                    label: "Pitch",
                    value: $audioEngine.pitch,
                    range: -12...12,
                    step: 1.0,
                    unit: " st",
                    color: .green,
                    formatter: { v in v >= 0 ? "+\(Int(v))" : "\(Int(v))" },
                    defaultValue: 0,
                    snapPoints: [0],
                    sliderWidth: 160
                )
            }

            HStack(spacing: 16) {
                Button(action: { audioEngine.skipBackward() }) {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: { audioEngine.togglePlayPause() }) {
                    Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Button(action: { audioEngine.skipForward() }) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleLoopEnabled() {
        if loopRegion == nil {
            // No region yet — show a transient hint and auto-dismiss after 2s.
            showEmptyHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showEmptyHint = false
            }
            return
        }
        isLoopEnabled.toggle()
    }
}
