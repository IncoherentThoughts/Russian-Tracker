import Foundation

#if os(iOS)
import ActivityKit
import AppIntents

/// Lives in both the main app target and the widget extension target (via
/// project.pbxproj membership exceptions). LiveActivityIntents fired from a
/// Live Activity button are dispatched by iOS through the app's process, so
/// the intent class must be visible to the main app — not only the widget.
struct ToggleTimerIntent: LiveActivityIntent {
    static let openAppWhenRun = false
    static var title: LocalizedStringResource = "Toggle Russian Timer"
    static var description = IntentDescription("Starts or pauses the Russian study timer.")

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: appGroupSuite)
        let isRunning = suite?.bool(forKey: TimerKey.timerRunning) ?? false
        let goalRaw = suite?.double(forKey: TimerKey.dailyGoal) ?? 0
        let dailyGoal = goalRaw > 0 ? goalRaw : 14400
        let mode = suite?.studyMode ?? .grammar

        print("[ToggleIntent] fire — currently isRunning=\(isRunning) mode=\(mode.rawValue)")

        let newIsRunning: Bool
        let newStartedAt: Date?
        let newDailyElapsed: Double

        if isRunning {
            let stored = suite?.double(forKey: TimerKey.dailyElapsed) ?? 0
            if let startedAt = suite?.object(forKey: TimerKey.timerStartedAt) as? Date {
                let interval = max(0, Date().timeIntervalSince(startedAt))
                let daily = stored + interval
                let total = (suite?.double(forKey: TimerKey.totalElapsed) ?? 0) + interval
                suite?.set(daily, forKey: TimerKey.dailyElapsed)
                suite?.set(total, forKey: TimerKey.totalElapsed)
                suite?.removeObject(forKey: TimerKey.timerStartedAt)
                // Credit the active type too — otherwise time paused from the
                // Lock Screen lands in the totals but in no type, and the ring
                // silently drifts below the all-time number.
                creditElapsed(interval, to: mode, in: suite)
                newDailyElapsed = daily
            } else {
                newDailyElapsed = stored
            }
            suite?.set(false, forKey: TimerKey.timerRunning)
            newIsRunning = false
            newStartedAt = nil
        } else {
            let startDate = Date()
            suite?.set(startDate, forKey: TimerKey.timerStartedAt)
            suite?.set(true, forKey: TimerKey.timerRunning)
            newIsRunning = true
            newStartedAt = startDate
            newDailyElapsed = suite?.double(forKey: TimerKey.dailyElapsed) ?? 0
        }

        let newState = RussianTimerAttributes.ContentState(
            dailyElapsed: newDailyElapsed,
            isRunning: newIsRunning,
            timerStartedAt: newStartedAt,
            dailyGoal: dailyGoal,
            mode: mode
        )
        let dismissAt = Date.now.addingTimeInterval(liveActivityIdleTimeout)
        let content = ActivityContent(state: newState, staleDate: dismissAt)

        let activities = Activity<RussianTimerAttributes>.activities
        // A `.stale` activity is still on screen (just flagged old), so it must
        // be refreshed too — otherwise a pause tap on a stale widget would do
        // nothing and leave it showing the running state. update() with a fresh
        // staleDate also brings it back to .active.
        let updatable = activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        print("[ToggleIntent] updatable=\(updatable.count) total=\(activities.count) → newIsRunning=\(newIsRunning)")

        // Update in place — smooth for both pause and resume since the
        // activity stays on screen across state transitions. Only request a
        // fresh one when resuming with nothing on screen to update.
        if !updatable.isEmpty {
            for activity in updatable {
                await activity.update(content)
            }
        } else if newIsRunning {
            for ghost in activities {
                await ghost.end(nil, dismissalPolicy: .immediate)
            }
            let authInfo = ActivityAuthorizationInfo()
            if authInfo.areActivitiesEnabled {
                do {
                    _ = try Activity<RussianTimerAttributes>.request(
                        attributes: RussianTimerAttributes(),
                        content: content
                    )
                } catch {
                    print("[ToggleIntent] request failed: \(error)")
                }
            }
        }

        // Tell the running app to adopt the state we just wrote, so its
        // in-memory TimerManager and on-screen timer don't diverge from the
        // widget. Delivered to all processes — including the app's own when it
        // is foregrounded (e.g. a Dynamic Island tap while using the app).
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(timerStateChangedNotification as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}

// MARK: - Per-type crediting (shared by the intents)

/// Add `interval` to a type's daily and all-time buckets in the shared suite.
/// Mirrors `TimerManager.credit(_:to:)` — the intents run in a different
/// process and cannot reach the app's in-memory manager, so the suite is the
/// only common ground. Both sides read and write the same `TimerKey` names.
nonisolated func creditElapsed(_ interval: TimeInterval, to type: StudyType, in suite: UserDefaults?) {
    guard interval > 0, let suite else { return }
    suite.set(suite.double(forKey: TimerKey.daily(type)) + interval, forKey: TimerKey.daily(type))
    suite.set(suite.double(forKey: TimerKey.total(type)) + interval, forKey: TimerKey.total(type))
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
struct SetStudyModeIntent: LiveActivityIntent {
    static let openAppWhenRun = false
    static var title: LocalizedStringResource = "Set Study Type"
    static var description = IntentDescription("Switches which kind of Russian study the timer is counting.")

    @Parameter(title: "Study Type") var mode: StudyType

    init() {}

    init(mode: StudyType) {
        self.mode = mode
    }

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: appGroupSuite)
        let oldMode = suite?.studyMode ?? .grammar
        guard mode != oldMode else { return .result() }

        let isRunning = suite?.bool(forKey: TimerKey.timerRunning) ?? false
        let goalRaw = suite?.double(forKey: TimerKey.dailyGoal) ?? 0
        let dailyGoal = goalRaw > 0 ? goalRaw : 14400

        var dailyElapsed = suite?.double(forKey: TimerKey.dailyElapsed) ?? 0
        var startedAt = suite?.object(forKey: TimerKey.timerStartedAt) as? Date

        if isRunning, let start = startedAt {
            let now = Date()
            let interval = max(0, now.timeIntervalSince(start))
            dailyElapsed += interval
            suite?.set(dailyElapsed, forKey: TimerKey.dailyElapsed)
            suite?.set((suite?.double(forKey: TimerKey.totalElapsed) ?? 0) + interval,
                       forKey: TimerKey.totalElapsed)
            creditElapsed(interval, to: oldMode, in: suite)
            suite?.set(now, forKey: TimerKey.timerStartedAt)
            startedAt = now
        }

        suite?.studyMode = mode
        print("[SetModeIntent] \(oldMode.rawValue) → \(mode.rawValue), running=\(isRunning)")

        let newState = RussianTimerAttributes.ContentState(
            dailyElapsed: dailyElapsed,
            isRunning: isRunning,
            timerStartedAt: startedAt,
            dailyGoal: dailyGoal,
            mode: mode
        )
        let content = ActivityContent(
            state: newState,
            staleDate: Date.now.addingTimeInterval(liveActivityIdleTimeout)
        )

        // Same updatable filter as ToggleTimerIntent: a `.stale` activity is
        // still on screen, so it has to be refreshed or the dots would show the
        // old selection after a tap.
        let updatable = Activity<RussianTimerAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        for activity in updatable {
            await activity.update(content)
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(timerStateChangedNotification as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}
#endif
