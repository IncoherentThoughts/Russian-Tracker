import SwiftUI

struct ManualEditView: View {
    @Environment(TimerManager.self) private var timer
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var hours: Int = 0
    @State private var minutes: Int = 0

    private var durationSeconds: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker(
                        "Study Date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(.rosyCopper)
                    .onChange(of: selectedDate) { _, newDate in
                        if let existing = store.session(for: newDate) {
                            hours = Int(existing.duration) / 3600
                            minutes = (Int(existing.duration) % 3600) / 60
                        } else {
                            hours = 0
                            minutes = 0
                        }
                    }
                }

                Section("Duration") {
                    Stepper("Hours: \(hours)", value: $hours, in: 0...23)
                    Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59, step: 5)

                    HStack {
                        Text("Total")
                            .foregroundColor(.lightBronze)
                        Spacer()
                        Text(durationSeconds.compactFormatted)
                            .fontWeight(.medium)
                    }
                }
            }
            .navigationTitle("Manual Edit")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSession()
                    }
                    .disabled(durationSeconds > 86340)
                }
            }
        }
        .tint(.rosyCopper)
    }

    private func saveSession() {
        let previousDuration = store.session(for: selectedDate)?.duration ?? 0
        store.upsertSession(date: selectedDate, duration: durationSeconds, isManual: true)
        timer.applyManualEdit(date: selectedDate, duration: durationSeconds, previousDuration: previousDuration)
        dismiss()
    }
}

#Preview {
    ManualEditView()
        .environment(TimerManager())
        .environment(StudyStore())
}
