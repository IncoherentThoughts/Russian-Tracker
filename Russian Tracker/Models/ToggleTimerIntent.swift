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
        let isRunning = suite?.bool(forKey: "timerRunning") ?? false
        let goalRaw = suite?.double(forKey: "dailyGoal") ?? 0
        let dailyGoal = goalRaw > 0 ? goalRaw : 14400

        print("[ToggleIntent] fire — currently isRunning=\(isRunning)")

        let newIsRunning: Bool
        let newStartedAt: Date?
        let newDailyElapsed: Double

        if isRunning {
            let stored = suite?.double(forKey: "dailyElapsed") ?? 0
            if let startedAt = suite?.object(forKey: "timerStartedAt") as? Date {
                let interval = max(0, Date().timeIntervalSince(startedAt))
                let daily = stored + interval
                let total = (suite?.double(forKey: "totalElapsed") ?? 0) + interval
                suite?.set(daily, forKey: "dailyElapsed")
                suite?.set(total, forKey: "totalElapsed")
                suite?.removeObject(forKey: "timerStartedAt")
                newDailyElapsed = daily
            } else {
                newDailyElapsed = stored
            }
            suite?.set(false, forKey: "timerRunning")
            newIsRunning = false
            newStartedAt = nil
        } else {
            let startDate = Date()
            suite?.set(startDate, forKey: "timerStartedAt")
            suite?.set(true, forKey: "timerRunning")
            newIsRunning = true
            newStartedAt = startDate
            newDailyElapsed = suite?.double(forKey: "dailyElapsed") ?? 0
        }

        let newState = RussianTimerAttributes.ContentState(
            dailyElapsed: newDailyElapsed,
            isRunning: newIsRunning,
            timerStartedAt: newStartedAt,
            dailyGoal: dailyGoal
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
#endif
