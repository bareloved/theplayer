import SwiftUI

struct TransportBar: View {
    @Bindable var audioEngine: AudioEngine
    @Binding var loopRegion: LoopRegion?
    @Binding var isSettingLoop: Bool
    @Binding var snapToGrid: Bool
    @Binding var snapDivision: SnapDivision

    var body: some View {
        ZStack {
            // Bottom layer: left-anchored speed, right-anchored everything else
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
                }

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

            // Centered transport — pinned to geometric middle via ZStack
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
