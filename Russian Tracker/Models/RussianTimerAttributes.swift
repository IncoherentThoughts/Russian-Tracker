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
    case anki

    var id: String { rawValue }

    /// Reads a stored raw value, accepting the pre-rename name of `.anki`.
    init?(stored raw: String) {
        if raw == "output" { self = .anki; return }
        self.init(rawValue: raw)
    }

    /// Shown only on the Stats screen. The dots on the Timer screen and the
    /// Live Activity are deliberately unlabeled.
    var displayName: String {
        switch self {
        case .grammar:   return "Grammar"
        case .immersion: return "Immersion"
        case .anki:    return "Anki"
        }
    }
}

// MARK: - Shared UserDefaults keys

/// Every key written to the app-group suite, in one place.
///
/// These are read by three separate processes — the app, the widget extension,
/// and the intents the system dispatches from the Lock Screen — so the names
/// live here rather than being duplicated per process. The suite is the local
/// cache of the Clock State (see `ClockSnapshot`); the synced copy lives in
/// Supabase (ADR 0003).
nonisolated enum TimerKey {
    static let dailyElapsed     = "dailyElapsed"
    static let timerRunning     = "timerRunning"
    static let timerStartedAt   = "timerStartedAt"
    static let dailyGoal        = "dailyGoal"
    static let currentMode      = "currentMode"
    static let studyDay         = "studyDay"
    static let lastActionAt     = "lastActionAt"
    static let lastActionDevice = "lastActionDevice"
    static let deviceID         = "deviceID"
    static let pendingSessions  = "pendingSessions"

    /// Sync bookkeeping (ADR 0003): the Clock has changes not yet uploaded,
    /// a global reset is waiting to reach the server, and which Account has
    /// already received this device's initial upload.
    static let syncClockDirty       = "syncClockDirty"
    static let syncPendingDeleteAll = "syncPendingDeleteAll"
    static let syncUploadedFor      = "syncUploadedFor"
    static let syncLastPulledAt     = "syncLastPulledAt"

    /// Sum of every Session before the current Study Day, cached by the app
    /// so the widgets and intents can show an All-Time Total without SwiftData.
    static let pastTotal        = "pastTotal"

    /// Written by the running Mac app every minute while the Clock is
    /// running and on every Clock Action. The widget shows its stale hint
    /// when the Clock is running but this is older than three minutes,
    /// which means the app that would keep the widget current has quit.
    static let appHeartbeat     = "appHeartbeat"

    /// Pre-sync installs kept the Study Day here; read once for migration.
    static let legacyLastResetDate = "lastResetDate"

    /// Seconds credited to `type` for the current Study Day.
    static func daily(_ type: StudyType) -> String { "daily_" + type.rawValue }

    /// Cached sum of `type` across every Session before the current Study Day.
    static func pastTotal(_ type: StudyType) -> String { "pastTotal_" + type.rawValue }
}

extension UserDefaults {
    /// The active study type, defaulting to grammar when unset or unrecognised.
    nonisolated var studyMode: StudyType {
        get { StudyType(stored: string(forKey: TimerKey.currentMode) ?? "") ?? .grammar }
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

nonisolated extension ClockSnapshot {
    /// What the Live Activity needs to render this Clock State.
    var liveActivityState: RussianTimerAttributes.ContentState {
        RussianTimerAttributes.ContentState(
            dailyElapsed: dailyBase,
            isRunning: isRunning,
            timerStartedAt: runStartedAt,
            dailyGoal: dailyGoal,
            mode: mode
        )
    }
}
#endif
