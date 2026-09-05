import Foundation
import AppIntents

// App-target only (not in the widget's membership exceptions): the widget
// does not need the App Shortcuts provider or the Start/Pause intents.

// MARK: - Start

/// Starts the Clock. Starting a Clock that is already running is a no-op
/// (CONTEXT.md), so this never re-anchors a run that is in progress.
struct StartTimerIntent: AppIntent {
    static let openAppWhenRun = false
    static var title: LocalizedStringResource = "Start Russian Timer"
    static var description = IntentDescription("Starts the Russian study timer if it is not already running.")

    func perform() async throws -> some IntentResult {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return .result() }
        var snap = ClockSnapshot(suite: suite)
        let now = Date()
        if let day = snap.rollover(now: now) {
            ClockSnapshot.enqueue(day, in: suite)
        }
        guard !snap.isRunning else { return .result() }
        snap.start(at: now, device: ClockSnapshot.deviceID(in: suite))
        snap.write(to: suite)
        await presentLiveActivity(for: snap, allowRequest: true)
        notifyApp()
        return .result()
    }
}

// MARK: - Pause

/// Pauses the Clock. A no-op when it is already paused.
struct PauseTimerIntent: AppIntent {
    static let openAppWhenRun = false
    static var title: LocalizedStringResource = "Pause Russian Timer"
    static var description = IntentDescription("Pauses the Russian study timer if it is running.")

    func perform() async throws -> some IntentResult {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return .result() }
        var snap = ClockSnapshot(suite: suite)
        let now = Date()
        if let day = snap.rollover(now: now) {
            ClockSnapshot.enqueue(day, in: suite)
        }
        guard snap.isRunning else { return .result() }
        snap.pause(at: now, device: ClockSnapshot.deviceID(in: suite))
        snap.write(to: suite)
        await presentLiveActivity(for: snap, allowRequest: false)
        notifyApp()
        return .result()
    }
}

// MARK: - App Shortcuts (Siri, Spotlight, the Shortcuts app)

/// The four Clock Actions exposed to Siri and the Shortcuts app without any
/// user setup. Phrases must contain `\(.applicationName)`.
struct RussianShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start my Russian timer in \(.applicationName)",
                "Start \(.applicationName)",
                "Start studying in \(.applicationName)",
            ],
            shortTitle: "Start Timer",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseTimerIntent(),
            phrases: [
                "Pause my Russian timer in \(.applicationName)",
                "Pause \(.applicationName)",
                "Stop studying in \(.applicationName)",
            ],
            shortTitle: "Pause Timer",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ToggleTimerIntent(),
            phrases: [
                "Toggle \(.applicationName)",
                "Toggle my Russian timer in \(.applicationName)",
            ],
            shortTitle: "Toggle Timer",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: SetStudyModeIntent(),
            phrases: [
                "Switch \(.applicationName) to \(\.$mode)",
                "Set \(.applicationName) study type to \(\.$mode)",
                "Study \(\.$mode) in \(.applicationName)",
            ],
            shortTitle: "Set Study Type",
            systemImageName: "book.fill"
        )
    }
}
