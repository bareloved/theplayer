import SwiftUI

struct TimingControls: View {
    let bpm: Float
    let timeSignature: TimeSignature
    let hasBpmOverride: Bool
    let hasTimeSigOverride: Bool

    let onSetBpm: (Float) -> Void
    let onResetBpm: () -> Void
    let onSetTimeSignature: (TimeSignature) -> Void
    let onResetTimeSignature: () -> Void

    let isClickEnabled: Bool
    @Binding var clickVolume: Double
    let onToggleClick: () -> Void

    @State private var editingBpm = false
    @State private var bpmText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            if editingBpm {
                TextField("BPM", text: $bpmText, onCommit: commitBpm)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .font(.caption)
                    .onChange(of: bpmText) { _, newValue in
                        // Digits only (allow up to 3 characters → max 999 BPM).
                        let filtered = String(newValue.filter { $0.isNumber }.prefix(3))
                        if filtered != newValue { bpmText = filtered }
                    }
            } else {
                Button(action: { beginEditingBpm() }) {
                    Text("\(Int(bpm.rounded())) BPM")
                        .font(.caption.monospaced())
                        .foregroundStyle(hasBpmOverride ? .blue : .primary)
                        .underline(true, color: .secondary)
                }
                .buttonStyle(.plain)
                .help("Click to type a BPM value")
                .contextMenu {
                    Button("Reset to auto-detected", action: onResetBpm).disabled(!hasBpmOverride)
                }
                .onHover { hovering in
                    if hovering { NSCursor.iBeam.set() } else { NSCursor.arrow.set() }
                }
            }
            Button("−1") { onSetBpm(bpm - 1) }
                .buttonStyle(.bordered).controlSize(.mini)
                .help("Decrease BPM by 1")
            Button("+1") { onSetBpm(bpm + 1) }
                .buttonStyle(.bordered).controlSize(.mini)
                .help("Increase BPM by 1")
            Button("÷2") { onSetBpm(bpm / 2) }
                .buttonStyle(.bordered).controlSize(.mini)
            Button("×2") { onSetBpm(bpm * 2) }
                .buttonStyle(.bordered).controlSize(.mini)

            Divider().frame(height: 14)

            Menu(timeSignature.displayString) {
                ForEach(TimeSignature.presets, id: \.self) { ts in
                    Button(ts.displayString) { onSetTimeSignature(ts) }
                }
                Divider()
                Button("Reset to auto-detected", action: onResetTimeSignature).disabled(!hasTimeSigOverride)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.caption)
            .foregroundStyle(hasTimeSigOverride ? .blue : .primary)

            Divider().frame(height: 14)

            Button(action: onToggleClick) {
                Image(systemName: isClickEnabled ? "metronome.fill" : "metronome")
            }
            .buttonStyle(.bordered).controlSize(.mini)
            .tint(isClickEnabled ? Color.orange : nil)
            .help(isClickEnabled ? "Disable click track" : "Enable click track")

            if isClickEnabled {
                Slider(value: $clickVolume, in: 0...1)
                    .frame(width: 60)
                Text("\(Int(clickVolume * 100))%")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }
        }
    }

    private func beginEditingBpm() {
        bpmText = String(Int(bpm.rounded()))
        editingBpm = true
    }

    private func commitBpm() {
        if let v = Float(bpmText), v > 0 { onSetBpm(v) }
        editingBpm = false
    }
}
