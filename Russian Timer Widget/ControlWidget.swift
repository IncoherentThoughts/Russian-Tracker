import WidgetKit
import SwiftUI
import AppIntents
#if os(iOS)
import ActivityKit
#endif

// Control Center tile: one toggle that starts or pauses the Clock.
// Controls exist on iOS 18+ and — per the SDK — macOS 26+ (Control Center
// widgets arrived on the Mac with Tahoe), hence the availability gates.
//
// `ControlWidgetToggle` needs a `SetValueIntent`, which `ToggleTimerIntent`
// is not (that one is a `LiveActivityIntent` dispatched through the app on
// iOS). `SetClockRunningIntent` below performs the same Clock Action in the
// suite, but only when the requested value differs from the current state —
// a toggle that is already in the requested position is a no-op, matching
// the Clock's own "start when running is a no-op" rule.

// MARK: - Control

@available(iOS 18.0, macOS 26.0, *)
struct RussianTimerControl: ControlWidget {
    static let kind = "RussianTimerControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ClockRunningProvider()) { isRunning in
            ControlWidgetToggle(
                "Russian Timer",
                isOn: isRunning,
                action: SetClockRunningIntent()
            ) { isOn in
                Label(isOn ? "Running" : "Paused", systemImage: isOn ? "pause.fill" : "book.fill")
                    .controlWidgetActionHint(isOn ? "Pause" : "Start")
            }
            .tint(Color.rosyCopper)
        }
        .displayName("Russian Timer")
        .description("Start or pause the Russian study timer.")
    }
}

/// Reads whether the Clock is running straight from the suite.
@available(iOS 18.0, macOS 26.0, *)
struct ClockRunningProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return false }
        return ClockSnapshot(suite: suite).isRunning
    }
}

// MARK: - Intent

/// Sets the Clock to running (`true`) or paused (`false`). Same suite /
/// Rollover / write / notify sequence as `ToggleTimerIntent`; duplicated
/// here because that file's helpers are private to it.
struct SetClockRunningIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Russian Timer Running"
    static let description = IntentDescription("Starts or pauses the Russian study timer.")
    static let openAppWhenRun = false

    @Parameter(title: "Running")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return .result() }
        var snap = ClockSnapshot(suite: suite)
        guard snap.isRunning != value else { return .result() }
        let now = Date()
        if let day = snap.rollover(now: now) {
            ClockSnapshot.enqueue(day, in: suite)
        }
        if value {
            snap.start(at: now, device: ClockSnapshot.deviceID(in: suite))
        } else {
            snap.pause(at: now, device: ClockSnapshot.deviceID(in: suite))
        }
        snap.write(to: suite)
        await refreshLiveActivity(for: snap)
        notifyAppOfClockChange()
        return .result()
    }
}

#if os(iOS)
/// Keep an on-screen Live Activity honest. Requesting a new one is left to
/// the app (`TimerManager.start`) — extensions cannot summon it.
private func refreshLiveActivity(for snap: ClockSnapshot) async {
    let content = ActivityContent(
        state: snap.liveActivityState,
        staleDate: Date.now.addingTimeInterval(liveActivityIdleTimeout)
    )
    for activity in Activity<RussianTimerAttributes>.activities
    where activity.activityState == .active || activity.activityState == .stale {
        await activity.update(content)
    }
}
#else
private func refreshLiveActivity(for snap: ClockSnapshot) async {}
#endif

/// Same Darwin notification `ToggleTimerIntent` posts: the running app
/// adopts the suite (`TimerManager.reconcileFromSharedState`) and reloads
/// the widgets and controls.
private func notifyAppOfClockChange() {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(timerStateChangedNotification as CFString),
        nil,
        nil,
        true
    )
}
