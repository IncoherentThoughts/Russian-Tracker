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

// MARK: - Study type

/// The kind of study a stretch of time counts as. The timer itself is always a
/// single running clock; this only decides which bucket its seconds land in.
///
/// Shared with the widget extension so the Live Activity can both display the
/// active type and switch it via `SetStudyModeIntent`.
nonisolated enum StudyType: String, CaseIterable, Codable, Hashable, Identifiable {
    case grammar
    case immersion
    case output

    var id: String { rawValue }

    /// Shown only on the Stats screen. The dots on the Timer screen and the
    /// Live Activity are deliberately unlabeled.
    var displayName: String {
        switch self {
        case .grammar:   return "Grammar"
        case .immersion: return "Immersion"
        case .output:    return "Output"
        }
    }
}

// MARK: - Shared UserDefaults keys

/// Every key written to the app-group suite, in one place.
///
/// These are read by three separate processes — the app, the widget extension,
/// and the intents iOS dispatches from the Lock Screen. They used to be private
/// to `TimerManager`, which forced the intents to hardcode the same strings;
/// with per-type buckets there are now thirteen keys and that duplication would
/// be a standing invitation for the app and the Live Activity to silently read
/// different values.
nonisolated enum TimerKey {
    static let dailyElapsed   = "dailyElapsed"
    static let totalElapsed   = "totalElapsed"
    static let lastResetDate  = "lastResetDate"
    static let timerRunning   = "timerRunning"
    static let timerStartedAt = "timerStartedAt"
    static let dailyGoal      = "dailyGoal"
    static let currentMode    = "currentMode"

    /// Seconds credited to `type` for the current study day.
    static func daily(_ type: StudyType) -> String { "daily_" + type.rawValue }

    /// Seconds credited to `type` for all time.
    static func total(_ type: StudyType) -> String { "total_" + type.rawValue }
}

extension UserDefaults {
    /// The active study type, defaulting to grammar when unset or unrecognised.
    nonisolated var studyMode: StudyType {
        get { StudyType(rawValue: string(forKey: TimerKey.currentMode) ?? "") ?? .grammar }
        set { set(newValue.rawValue, forKey: TimerKey.currentMode) }
    }
}

#if os(iOS)
import ActivityKit

struct RussianTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var dailyElapsed: TimeInterval
        var isRunning: Bool
        var timerStartedAt: Date?
        var dailyGoal: TimeInterval
        var mode: StudyType
    }
}
#endif
