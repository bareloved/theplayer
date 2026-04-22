import SwiftUI

struct SectionInspector: View {
    @Bindable var viewModel: SectionsViewModel
    let selectedSectionId: UUID?
    let onLabelCommit: (String) -> Void
    let onColorPick: (Int) -> Void

    @State private var draftLabel: String = ""

    private var section: AudioSection? {
        guard let id = selectedSectionId else { return nil }
        return viewModel.sections.first(where: { $0.stableId == id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Section")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let section {
                HStack {
                    TextField("Label", text: $draftLabel, onCommit: {
                        onLabelCommit(draftLabel)
                    })
                    .textFieldStyle(.roundedBorder)

                    Menu {
                        ForEach(SectionLabelPresets.labels, id: \.self) { preset in
                            Button(preset) {
                                draftLabel = preset
                                onLabelCommit(preset)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .onAppear { draftLabel = section.label }
                .onChange(of: section.stableId) { _, _ in draftLabel = section.label }

                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { idx in
                        Circle()
                            .fill(colorForIndex(idx))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white, lineWidth: section.colorIndex == idx ? 2 : 0)
                            )
                            .onTapGesture { onColorPick(idx) }
                    }
                }

                Text("\(formatTime(section.startTime)) – \(formatTime(section.endTime))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            } else {
                Text("Select a section to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func colorForIndex(_ idx: Int) -> Color {
        let palette: [Color] = [.blue, .green, .red, .yellow, .purple, .orange, .cyan, .pink]
        return palette[idx % palette.count]
    }

    private func formatTime(_ s: Float) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return "\(m):\(String(format: "%02d", sec))"
    }
}
