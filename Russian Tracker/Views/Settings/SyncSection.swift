import SwiftUI

/// The Account group in Settings (ADR 0003): sign in once with an email and
/// password, then it just shows who is signed in and a way out.
struct SyncSection: View {
    @Environment(SyncClient.self) private var sync

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroupView(label: "Account") {
                switch sync.step {
                case .signedOut:
                    signedOutRows
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
        inputRow(icon: "envelope", label: "Email") {
            field("you@example.com", text: $email, kind: .email)
        }
        SettingsDivider()
        inputRow(icon: "key", label: "Password") {
            field("••••••••", text: $password, kind: .password)
        }
        SettingsDivider()
        SettingsRow(
            icon: "person.crop.circle.badge.checkmark",
            label: sync.busy ? "Signing in…" : "Sign in",
            chevron: true,
            action: { Task { await sync.signIn(email: email, password: password); password = "" } }
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

    /// Same layout as `SettingsRow`, minus the Button: a disabled button
    /// disables the text field inside it, which made the email row inert.
    private func inputRow<Content: View>(
        icon: String, label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.toffeeBrown)
                .frame(width: 28, height: 28)
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.toffeeInk)
            Spacer(minLength: 8)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private enum FieldKind { case email, password }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, kind: FieldKind) -> some View {
        Group {
            if kind == .password {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(.toffeeInk)
            .autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(kind == .email ? .emailAddress : .default)
            .textInputAutocapitalization(.never)
            .textContentType(kind == .email ? .emailAddress : .password)
            #endif
            .frame(maxWidth: 200)
    }
}
