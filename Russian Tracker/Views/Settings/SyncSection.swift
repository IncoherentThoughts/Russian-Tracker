import SwiftUI

/// The Account group in Settings (ADR 0003): sign in once with an email and
/// a one-time code, then it just shows who is signed in and a way out.
struct SyncSection: View {
    @Environment(SyncClient.self) private var sync

    @State private var email = ""
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroupView(label: "Account") {
                switch sync.step {
                case .signedOut:
                    signedOutRows
                case .codeSent(let address):
                    codeRows(address)
                case .signedIn(let address):
                    signedInRows(address)
                }
            }
            if let error = sync.lastError {
                Text(error)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.rosyCopper)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var signedOutRows: some View {
        SettingsRow(icon: "envelope", label: "Email") {
            field("you@example.com", text: $email, isEmail: true)
        }
        SettingsDivider()
        SettingsRow(
            icon: "paperplane",
            label: sync.busy ? "Sending…" : "Send sign-in code",
            chevron: true,
            action: { Task { await sync.sendCode(to: email) } }
        )
    }

    @ViewBuilder
    private func codeRows(_ address: String) -> some View {
        SettingsRow(icon: "envelope", label: "Email") {
            Text(address)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.bronzeMuted)
                .lineLimit(1)
        }
        SettingsDivider()
        SettingsRow(icon: "number", label: "Code") {
            field("123456", text: $code, isEmail: false)
        }
        SettingsDivider()
        SettingsRow(
            icon: "checkmark.circle",
            label: sync.busy ? "Verifying…" : "Verify",
            chevron: true,
            action: { Task { await sync.verify(code: code) } }
        )
        SettingsDivider()
        SettingsRow(
            icon: "arrow.uturn.backward",
            label: "Use a different email",
            action: { code = ""; sync.cancelCode() }
        )
    }

    @ViewBuilder
    private func signedInRows(_ address: String) -> some View {
        SettingsRow(icon: "person.crop.circle", label: "Signed in") {
            Text(address)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.bronzeMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        SettingsDivider()
        SettingsRow(
            icon: "rectangle.portrait.and.arrow.right",
            label: "Sign out",
            destructive: true,
            action: { Task { await sync.signOut() } }
        )
    }

    private func field(_ placeholder: String, text: Binding<String>, isEmail: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(.toffeeInk)
            .autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(isEmail ? .emailAddress : .numberPad)
            .textInputAutocapitalization(.never)
            .textContentType(isEmail ? .emailAddress : .oneTimeCode)
            #endif
            .frame(maxWidth: 200)
    }
}
