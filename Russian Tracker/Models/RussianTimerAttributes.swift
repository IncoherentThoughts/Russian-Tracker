import Foundation

/// Shared across the main app target and the widget extension target.
let appGroupSuite = "group.evan.russiantimer"

/// Idle timeout for the Live Activity. After this many seconds without
/// engagement (start/pause, app foreground, or Lock Screen button tap) the
/// activity auto-dismisses. Shared so the app and widget intent agree.
let liveActivityIdleTimeout: TimeInterval = 30 * 60

/// Darwin notification name posted by `ToggleTimerIntent` after it mutates the
/// shared timer state from a Live Activity button. The running app observes it
/// (`CFNotificationCenterGetDarwinNotifyCenter`) and reconciles its in-memory
/// `TimerManager` immediately — without this bridge the app only re-reads the
/// shared suite on foreground, so widget toggles silently diverge while the app
/// is open. Plain CFString name; carries no payload (state lives in the suite).
let timerStateChangedNotification = "group.evan.russiantimer.stateChanged"

#if os(iOS)
import ActivityKit

struct RussianTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var dailyElapsed: TimeInterval
        var isRunning: Bool
        var timerStartedAt: Date?
        var dailyGoal: TimeInterval
    }
}
#endif
