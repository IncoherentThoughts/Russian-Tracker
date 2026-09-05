import Foundation
import AppIntents
#if os(iOS)
import ActivityKit
/// `LiveActivityIntent` (iOS) lets the system run the intent in-process from
/// a Live Activity button; on macOS a plain `AppIntent` serves widgets and
/// Control Center the same way.
typealias ClockIntent = LiveActivityIntent
#else
typealias ClockIntent = AppIntent
#endif

/// Lives in both the main app target and the widget extension target (via
/// project.pbxproj membership exceptions). LiveActivityIntents fired from a
/// Live Activity button are dispatched by iOS through the app's process, so
/// the intent class must be visible to the main app — not only the widget.
struct ToggleTimerIntent: ClockIntent {
    static let openAppWhenRun = false
    static var title: LocalizedStringResource = "Toggle Russian Timer"
    static var description = IntentDescription("Starts or pauses the Russian study timer.")

    func perform() async throws -> some IntentResult {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return .result() }
        var snap = ClockSnapshot(suite: suite)
        let now = Date()
        if let day = snap.rollover(now: now) {
            ClockSnapshot.enqueue(day, in: suite)
        }
        if snap.isRunning {
            snap.pause(at: now, device: ClockSnapshot.deviceID(in: suite))
        } else {
            snap.start(at: now, device: ClockSnapshot.deviceID(in: suite))
        }
        snap.write(to: suite)
        await presentLiveActivity(for: snap, allowRequest: snap.isRunning)
        notifyApp()
        return .result()
    }
}

// MARK: - Live Activity helpers shared by the intents

#if os(iOS)
/// Push `snap` to every on-screen activity. A `.stale` activity is still on
/// screen (just flagged old), so it is refreshed too; update() with a fresh
/// staleDate brings it back to .active. When nothing is on screen and
/// `allowRequest` is set, a fresh activity is requested instead.
private func presentLiveActivity(for snap: ClockSnapshot, allowRequest: Bool) async {
    let content = ActivityContent(
        state: snap.liveActivityState,
        staleDate: Date.now.addingTimeInterval(liveActivityIdleTimeout)
    )
    let activities = Activity<RussianTimerAttributes>.activities
    let updatable = activities.filter {
        $0.activityState == .active || $0.activityState == .stale
    }
    if !updatable.isEmpty {
        for activity in updatable {
            await activity.update(content)
        }
    } else if allowRequest {
        for ghost in activities {
            await ghost.end(nil, dismissalPolicy: .immediate)
        }
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                _ = try Activity<RussianTimerAttributes>.request(
                    attributes: RussianTimerAttributes(),
                    content: content
                )
            } catch {
                print("[Intent] Live Activity request failed: \(error)")
            }
        }
    }
}

#else
/// No Live Activity on macOS; the Menu Bar Item and widget re-read the suite.
private func presentLiveActivity(for snap: ClockSnapshot, allowRequest: Bool) async {}
#endif

/// Tell the running app to adopt the state just written to the suite, so its
/// in-memory `TimerManager` does not diverge from the widget. Delivered to all
/// processes, including the app's own when it is foregrounded.
private func notifyApp() {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(timerStateChangedNotification as CFString),
        nil,
        nil,
        true
    )
}

// MARK: - Study type as an intent parameter

nonisolated extension StudyType: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Study Type" }

    nonisolated static var caseDisplayRepresentations: [StudyType: DisplayRepresentation] {
        [
            .grammar:   "Grammar",
            .immersion: "Immersion",
            .output:    "Output",
        ]
    }
}

// MARK: - Set study type from the Live Activity

/// Switches the active study type from the Lock Screen or Dynamic Island.
///
/// Live Activities only accept `Button(intent:)` and `Toggle(intent:)` — no
/// `Menu`, no `Picker` — so the three-dot switch is literally three buttons,
/// each carrying this intent with a different `mode`.
///
/// Performs the same split as `TimerManager.setMode(_:)`: bank the in-flight
/// slice against the outgoing type, re-anchor the start date to now, and leave
/// the clock running. Because the elapsed base and the anchor move together,
/// the widget's `Text(timerInterval:)` keeps ticking without a visible jump.
struct SetStudyModeIntent: ClockIntent {
    static let openAppWhenRun = false
    static var title: LocalizedStringResource = "Set Study Type"
    static var description = IntentDescription("Switches which kind of Russian study the timer is counting.")

    @Parameter(title: "Study Type") var mode: StudyType

    init() {}

    init(mode: StudyType) {
        self.mode = mode
    }

    func perform() async throws -> some IntentResult {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return .result() }
        var snap = ClockSnapshot(suite: suite)
        guard mode != snap.mode else { return .result() }
        let now = Date()
        if let day = snap.rollover(now: now) {
            ClockSnapshot.enqueue(day, in: suite)
        }
        snap.setMode(mode, at: now, device: ClockSnapshot.deviceID(in: suite))
        snap.write(to: suite)
        await presentLiveActivity(for: snap, allowRequest: false)
        notifyApp()
        return .result()
    }
}
