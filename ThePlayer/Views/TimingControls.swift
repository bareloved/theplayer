import SwiftUI

struct TimingControls: View {
    let bpm: Float
    let timeSignature: TimeSignature
    let downbeatOffset: Int
    let isSettingDownbeat: Bool
    let hasBpmOverride: Bool
    let hasTimeSigOverride: Bool
    let hasDownbeatOverride: Bool

    let onSetBpm: (Float) -> Void
    let onResetBpm: () -> Void
    let onSetTimeSignature: (TimeSignature) -> Void
    let onResetTimeSignature: () -> Void
    let onShiftDownbeat: (Int) -> Void  // ±1
    let onResetDownbeat: () -> Void
    let onToggleSetDownbeat: () -> Void

    @State private var editingBpm = false
    @State private var bpmText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            if editingBpm {
                TextField("BPM", text: $bpmText, onCommit: commitBpm)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .font(.caption)
            } else {
                Text("\(Int(bpm.rounded())) BPM")
                    .font(.caption.monospaced())
                    .foregroundStyle(hasBpmOverride ? .blue : .primary)
                    .onTapGesture { beginEditingBpm() }
                    .contextMenu {
                        Button("Reset to auto-detected", action: onResetBpm).disabled(!hasBpmOverride)
                    }
            }
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

            Button(action: { onShiftDownbeat(-1) }) { Image(systemName: "chevron.left") }
                .buttonStyle(.bordered).controlSize(.mini)
                .help("Shift downbeat earlier")
            Button(action: { onShiftDownbeat(1) }) { Image(systemName: "chevron.right") }
                .buttonStyle(.bordered).controlSize(.mini)
                .help("Shift downbeat later")
            Button(action: onToggleSetDownbeat) {
                Image(systemName: "scope")
            }
            .buttonStyle(.bordered).controlSize(.mini)
            .tint(isSettingDownbeat ? .cyan : nil)
            .help(isSettingDownbeat ? "Click a beat on the waveform" : "Set downbeat by clicking a beat")
            .contextMenu {
                Button("Reset to auto-detected", action: onResetDownbeat).disabled(!hasDownbeatOverride)
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
