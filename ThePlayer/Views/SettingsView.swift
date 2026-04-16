import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                shortcutRow("Play / Pause", key: "Space")
                shortcutRow("Seek Backward", key: "←")
                shortcutRow("Seek Forward", key: "→")
                shortcutRow("Speed Up (+5%)", key: "↑")
                shortcutRow("Speed Down (-5%)", key: "↓")
                shortcutRow("Pitch Up (+1 semitone)", key: "]")
                shortcutRow("Pitch Down (-1 semitone)", key: "[")
                shortcutRow("Toggle Loop", key: "L")
                shortcutRow("Jump to Section 1-9", key: "1 – 9")
                shortcutRow("Clear Loop & Selection", key: "Esc")
                shortcutRow("Open File", key: "⌘O")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }

    private func shortcutRow(_ action: String, key: String) -> some View {
        HStack {
            Text(action)
            Spacer()
            Text(key)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
