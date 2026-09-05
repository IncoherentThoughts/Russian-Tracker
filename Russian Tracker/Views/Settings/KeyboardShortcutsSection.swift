#if os(macOS)
import SwiftUI
import KeyboardShortcuts

/// The "Keyboard Shortcuts" group in Settings: one recorder per global hotkey
/// (see `Mac/Hotkeys.swift`). Rows mirror `SettingsRow` so the group sits
/// flush with the rest of the page; the recorder itself is the package's
/// native control, tinted to the palette.
struct KeyboardShortcutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard Shortcuts")
                .eyebrowStyle()
                .padding(.horizontal, 6)

            VStack(spacing: 0) {
                shortcutRow(icon: "playpause", label: "Start / Pause", name: .toggleClock)
                divider
                shortcutRow(icon: "text.book.closed", label: "Grammar", name: .setGrammar)
                divider
                shortcutRow(icon: "headphones", label: "Immersion", name: .setImmersion)
                divider
                shortcutRow(icon: "pencil.line", label: "Output", name: .setOutput)
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.eggshellDeep)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.toffeeBrown.opacity(0.06), lineWidth: 1)
            )
        }
        .padding(.top, 20)
    }

    private func shortcutRow(icon: String, label: String, name: KeyboardShortcuts.Name) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.toffeeBrown)
                .frame(width: 28, height: 28)

            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.toffeeInk)

            Spacer(minLength: 8)

            KeyboardShortcuts.Recorder(for: name)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label) shortcut")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, 58)
    }
}

#Preview {
    KeyboardShortcutsSection()
        .padding(22)
        .background(Color.eggshell)
}
#endif
