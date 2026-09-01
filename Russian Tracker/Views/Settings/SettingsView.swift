import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(TimerManager.self) private var timer
    @Environment(StudyStore.self) private var store

    @State private var showResetDailyAlert = false
    @State private var showResetTotalAlert1 = false
    @State private var showResetTotalAlert2 = false
    @State private var showManualEdit = false
    @State private var showAdvanced = false
    @State private var dailyGoalHours: Int = 4

    // Backup & Restore
    @State private var exportFile: ExportFile?
    @State private var showExportError = false
    @State private var exportError = ""
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var importPreviewText = ""
    @State private var showImportConfirm = false
    @State private var showImportError = false
    @State private var importError = ""

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Settings").pageTitleStyle()
            Spacer()
            Text("v \(appVersion)").eyebrowStyle()
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    private var timerGroup: some View {
        SettingsGroupView(label: "Timer") {
            SettingsRow(icon: "target", label: "Daily goal") {
                InlineStepper(
                    value: dailyGoalHours,
                    range: 1...10,
                    display: "\(dailyGoalHours)h"
                ) { newValue in
                    dailyGoalHours = newValue
                    UserDefaults(suiteName: appGroupSuite)?.set(
                        Double(newValue) * 3600, forKey: "dailyGoal"
                    )
                }
            }
            SettingsDivider()
            SettingsRow(
                icon: "arrow.clockwise",
                label: "Reset daily timer",
                chevron: true,
                action: { showResetDailyAlert = true }
            )
            SettingsDivider()
            SettingsRow(
                icon: "trash",
                label: "Reset total timer",
                chevron: true,
                destructive: true,
                action: { showResetTotalAlert1 = true }
            )
        }
    }

    private var advancedGroup: some View {
        SettingsGroupView {
            SettingsRow(
                icon: "gearshape",
                label: "Advanced",
                chevron: true,
                action: { showAdvanced = true }
            )
        }
    }

    private var backupGroup: some View {
        SettingsGroupView(label: "Backup & Restore") {
            SettingsRow(
                icon: "square.and.arrow.up",
                label: "Export stats",
                chevron: true,
                action: { performExport() }
            )
            SettingsDivider()
            SettingsRow(
                icon: "square.and.arrow.down",
                label: "Import stats",
                chevron: true,
                action: { showImporter = true }
            )
        }
    }

    private var aboutGroup: some View {
        SettingsGroupView(label: "About") {
            SettingsRow(icon: "info.circle", label: "Version") {
                Text(appVersion)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.bronzeMuted)
            }
        }
    }

    private func performExport() {
        do {
            let url = try store.exportBackupFile(timer: timer)
            exportFile = ExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                timerGroup
                advancedGroup
                backupGroup
                aboutGroup
            }
            .padding(.horizontal, 22)
            .padding(.top, 62)
            .padding(.bottom, 120)
        }
        .background(Color.eggshell.ignoresSafeArea())
        .onAppear {
            let g = UserDefaults(suiteName: appGroupSuite)?.double(forKey: "dailyGoal") ?? 0
            dailyGoalHours = g > 0 ? Int(g / 3600) : 4
        }
        .tint(.rosyCopper)
        .alert("Reset Daily Timer?", isPresented: $showResetDailyAlert) {
            Button("Reset", role: .destructive) {
                timer.resetDaily()
                store.upsertSession(date: Date(), duration: 0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today's study time will be reset to 0:00:00.")
        }
        .alert("Reset All-Time Total?", isPresented: $showResetTotalAlert1) {
            Button("Continue", role: .destructive) {
                showResetTotalAlert2 = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently erase your all-time study total. Are you sure?")
        }
        .alert("This Cannot Be Undone", isPresented: $showResetTotalAlert2) {
            Button("Reset Everything", role: .destructive) {
                timer.resetTotal()
                store.deleteAllSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your entire study history total will be permanently deleted.")
        }
        .sheet(isPresented: $showManualEdit) {
            ManualEditView()
                .environment(timer)
                .environment(store)
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedSheet(showManualEdit: $showManualEdit)
                .environment(timer)
                .environment(store)
        }
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    importPreviewText = try store.importPreview(from: url)
                    pendingImportURL = url
                    showImportConfirm = true
                } catch {
                    importError = "Could not read backup: \(error.localizedDescription)"
                    showImportError = true
                }
            case .failure(let error):
                importError = error.localizedDescription
                showImportError = true
            }
        }
        .alert("Restore Backup?", isPresented: $showImportConfirm) {
            Button("Restore", role: .destructive) {
                guard let url = pendingImportURL else { return }
                pendingImportURL = nil
                do {
                    try store.applyBackup(from: url, timer: timer)
                } catch {
                    importError = "Import failed: \(error.localizedDescription)"
                    showImportError = true
                }
            }
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
        } message: {
            Text(importPreviewText)
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError)
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError)
        }
    }
}

// MARK: - Settings primitives

private struct SettingsGroupView<Content: View>: View {
    var label: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label {
                Text(label)
                    .eyebrowStyle()
                    .padding(.horizontal, 6)
            }
            VStack(spacing: 0) {
                content()
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
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, 58)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    var iconWeight: Font.Weight = .regular
    let label: String
    var chevron: Bool = false
    var destructive: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String,
        iconWeight: Font.Weight = .regular,
        label: String,
        chevron: Bool = false,
        destructive: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconWeight = iconWeight
        self.label = label
        self.chevron = chevron
        self.destructive = destructive
        self.action = action
        self.trailing = trailing
    }

    private var primaryColor: Color {
        destructive ? .rosyCopper : .toffeeInk
    }

    private var iconColor: Color {
        destructive ? .rosyCopper : .toffeeBrown
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: iconWeight))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)

                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(primaryColor)

                Spacer(minLength: 8)

                trailing()

                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.lightBronze)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

private struct InlineStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let display: String
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus") {
                if value > range.lowerBound { onChange(value - 1) }
            }
            divider
            Text(display)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.toffeeInk)
                .frame(minWidth: 34)
            divider
            stepButton(systemName: "plus") {
                if value < range.upperBound { onChange(value + 1) }
            }
        }
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.eggshell)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.toffeeInk)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(width: 1, height: 16)
    }
}

// MARK: - Advanced sheet (lightweight host for ManualEditView entry)

private struct AdvancedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showManualEdit: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SettingsGroupView(label: "Editing") {
                    SettingsRow(
                        icon: "pencil.and.list.clipboard",
                        label: "Manual day edit",
                        chevron: true,
                        action: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                showManualEdit = true
                            }
                        }
                    )
                }
                .padding(.horizontal, 22)

                Spacer()
            }
            .padding(.top, 16)
            .background(Color.eggshell.ignoresSafeArea())
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.rosyCopper)
                }
            }
        }
    }
}

// MARK: - Export helpers

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
    SettingsView()
        .environment(TimerManager())
        .environment(StudyStore())
}
