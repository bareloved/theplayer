import SwiftUI

struct SidebarView: View {
    let sections: [AudioSection]
    let bpm: Float?
    let timeSignature: TimeSignature
    let duration: Float
    let sampleRate: Double
    let onSectionTap: (AudioSection) -> Void
    var onRename: ((UUID, String) -> Void)? = nil
    var onDelete: ((UUID) -> Void)? = nil

    @Binding var selectedSection: AudioSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sections.isEmpty {
                ContentUnavailableView {
                    Label("No Sections", systemImage: "music.note.list")
                } description: {
                    Text("Open an audio file to analyze")
                }
                .frame(maxHeight: .infinity)
            } else {
                Text("Sections")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            SectionRow(
                                section: section,
                                index: index + 1,
                                beatsPerBar: timeSignature.beatsPerBar,
                                isSelected: selectedSection == section,
                                onTap: { onSectionTap(section) },
                                onRename: onRename.map { cb in { cb(section.stableId, $0) } },
                                onDelete: onDelete.map { cb in { cb(section.stableId) } }
                            )
                        }
                    }
                }
            }

            Spacer()

            if duration > 0 {
                trackInfoFooter
            }
        }
    }

    private var trackInfoFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Track Info")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                if let bpm {
                    Text("\(Int(bpm)) BPM")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }

                Text(formatDuration(duration) + " · \(Int(sampleRate / 1000))kHz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func formatDuration(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

private struct SectionRow: View {
    let section: AudioSection
    let index: Int
    let beatsPerBar: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onRename: ((String) -> Void)?
    let onDelete: (() -> Void)?

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(section.color)
                        .frame(width: 4)
                    TextField("Label", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .focused($renameFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { isRenaming = false }
                        .onChange(of: renameFocused) { _, focused in
                            if !focused && isRenaming { commitRename() }
                        }
                    Text("\(index)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onAppear {
                    renameText = section.label
                    DispatchQueue.main.async { renameFocused = true }
                }
            } else {
                Button(action: onTap) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(section.color)
                            .frame(width: 4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.label)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("\(formatTime(section.startTime)) – \(formatTime(section.endTime)) · \(section.barCount(beatsPerBar: beatsPerBar)) bars")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(index)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isSelected ? section.color.opacity(0.15) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if onRename != nil {
                        Button("Rename...") {
                            renameText = section.label
                            isRenaming = true
                        }
                    }
                    if let onDelete {
                        Divider()
                        Button("Delete", role: .destructive) { onDelete() }
                    }
                }
            }
        }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != section.label {
            onRename?(trimmed)
        }
        isRenaming = false
    }

    private func formatTime(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
