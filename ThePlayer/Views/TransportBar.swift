import SwiftUI

struct TransportBar: View {
    @Bindable var audioEngine: AudioEngine
    @Binding var loopRegion: LoopRegion?
    @Binding var isSettingLoop: Bool
    @Binding var snapToGrid: Bool
    @Binding var snapDivision: SnapDivision
    let isInSetlist: Bool
    let onNextInSetlist: () -> Void
    let onToggleSectionEditor: () -> Void
    let isSectionEditing: Bool

    var body: some View {
        VStack(spacing: 8) {
            utilityRow
            mainRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Top row — utility controls (A-B, Snap, Bars picker). Centered.
    private var utilityRow: some View {
        HStack(spacing: 12) {
            Button(action: toggleLoopMode) {
                Label(isSettingLoop ? "Click waveform..." : "A-B", systemImage: "repeat")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(isSettingLoop ? .orange : (loopRegion != nil ? .blue : .secondary))

            Button(action: { snapToGrid.toggle() }) {
                Label("Snap", systemImage: "grid")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(snapToGrid ? .purple : .secondary)

            HStack(spacing: 4) {
                Text("Bars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("", selection: $snapDivision) {
                    ForEach(SnapDivision.allCases) { div in
                        Text(div.shortLabel).tag(div)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .opacity(snapToGrid ? 1 : 0)
            .disabled(!snapToGrid)
            .allowsHitTesting(snapToGrid)

            if isInSetlist {
                Button(action: onNextInSetlist) {
                    Label("Next", systemImage: "forward.end.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }

            Button(action: onToggleSectionEditor) {
                Image(systemName: isSectionEditing ? "pencil.circle.fill" : "pencil.circle")
            }
            .buttonStyle(.plain)
            .help(isSectionEditing ? "Exit section editor" : "Edit sections")
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
                    formatter: { "\(Int($0 * 100))" }
                )

                Spacer()

                SpeedPitchControl(
                    label: "Pitch",
                    value: $audioEngine.pitch,
                    range: -12...12,
                    step: 1.0,
                    unit: " st",
                    color: .green,
                    formatter: { v in v >= 0 ? "+\(Int(v))" : "\(Int(v))" }
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

    private func toggleLoopMode() {
        if loopRegion != nil {
            loopRegion = nil
            isSettingLoop = false
        } else {
            isSettingLoop = true
        }
    }
}
