import Foundation

/// The default Daily Goal: four hours.
nonisolated let defaultDailyGoal: TimeInterval = 4 * 3600

/// The Clock State as a plain value (see CONTEXT.md).
///
/// This is the one representation every process shares: the app keeps it in
/// memory, the intents and widgets read and write it through the app-group
/// suite, and the app mirrors it to Supabase (ADR 0003). All
/// Clock Actions are mutating methods here, so the app and the intents cannot
/// drift apart in how they bank time.
///
/// Two invariants:
/// - Every Clock Action banks the in-flight run before changing anything, so
///   a later action from another device can never discard counted minutes
///   that this device had already seen.
/// - `lastActionAt` is stamped only by user actions (start, pause, mode
///   switch, resets, edits, goal). Rollover does not stamp it: it is a pure
///   function of the state and the wall clock, so two devices that both roll
///   over produce the same state and neither should outrank a real action.
nonisolated struct ClockSnapshot: Equatable, Codable {
    var isRunning: Bool = false
    var runStartedAt: Date? = nil
    var mode: StudyType = .grammar
    /// Start-of-day date of the Study Day the daily counters belong to.
    var studyDay: Date = .distantPast
    /// Seconds banked for the current Study Day, excluding the in-flight run.
    var dailyBase: TimeInterval = 0
    var dailyByType: [StudyType: TimeInterval] = [:]
    var dailyGoal: TimeInterval = defaultDailyGoal
    var lastActionAt: Date = .distantPast
    var lastActionDevice: String = ""

    // MARK: - Derived values

    func inFlight(at now: Date) -> TimeInterval {
        guard isRunning, let start = runStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    func daily(at now: Date) -> TimeInterval {
        dailyBase + inFlight(at: now)
    }

    func daily(for type: StudyType, at now: Date) -> TimeInterval {
        (dailyByType[type] ?? 0) + (mode == type ? inFlight(at: now) : 0)
    }

    func breakdown(at now: Date) -> [StudyType: TimeInterval] {
        Dictionary(uniqueKeysWithValues: StudyType.allCases.map { ($0, daily(for: $0, at: now)) })
    }

    // MARK: - Clock Actions

    mutating func start(at now: Date, device: String) {
        guard !isRunning else { return }
        isRunning = true
        runStartedAt = now
        stamp(now, device)
    }

    mutating func pause(at now: Date, device: String) {
        guard isRunning else { return }
        bank(at: now)
        isRunning = false
        runStartedAt = nil
        stamp(now, device)
    }

    /// Splits a running session at this instant: everything before is credited
    /// to the outgoing type, everything after to the incoming one.
    mutating func setMode(_ newMode: StudyType, at now: Date, device: String) {
        guard newMode != mode else { return }
        bank(at: now)
        mode = newMode
        stamp(now, device)
    }

    /// Zeroes today's counters. A running Clock keeps running from now.
    mutating func resetDaily(at now: Date, device: String) {
        dailyBase = 0
        dailyByType = [:]
        if isRunning { runStartedAt = now }
        stamp(now, device)
    }

    /// A Manual Edit of the current Study Day. The total becomes `duration`;
    /// typed buckets are clamped so no type can exceed the new total.
    mutating func setManualDaily(_ duration: TimeInterval, at now: Date, device: String) {
        bank(at: now)
        dailyBase = max(0, duration)
        for type in StudyType.allCases {
            dailyByType[type] = min(dailyByType[type] ?? 0, dailyBase)
        }
        stamp(now, device)
    }

    mutating func setDailyGoal(_ goal: TimeInterval, at now: Date, device: String) {
        dailyGoal = goal > 0 ? goal : defaultDailyGoal
        stamp(now, device)
    }

    /// Folds the in-flight run into the banked bases and re-anchors the run
    /// to `now`. Displayed totals are unchanged at the instant of the call.
    mutating func bank(at now: Date) {
        let interval = inFlight(at: now)
        guard interval > 0 else { return }
        dailyBase += interval
        dailyByType[mode, default: 0] += interval
        runStartedAt = now
    }

    private mutating func stamp(_ now: Date, _ device: String) {
        lastActionAt = now
        lastActionDevice = device
    }

    // MARK: - Rollover

    /// Moves the counters to the current Study Day if a 4am boundary has
    /// passed. Returns the departing day's figures for persistence as a
    /// Session, or nil when there was nothing to depart.
    ///
    /// Idempotent: calling it again with the same `now` returns nil and changes
    /// nothing, so any number of devices can run it in any order.
    mutating func rollover(now: Date, calendar: Calendar = .current) -> DepartingDay? {
        let current = Self.studyDayStart(for: now, calendar: calendar)
        if studyDay == .distantPast {
            studyDay = current
            return nil
        }
        guard studyDay < current else { return nil }

        let boundary = Self.boundary(after: studyDay, calendar: calendar)
        var pre: TimeInterval = 0
        if isRunning, let start = runStartedAt, start < boundary {
            pre = boundary.timeIntervalSince(start)
        }
        var departing = dailyByType
        if pre > 0 { departing[mode, default: 0] += pre }
        let day = DepartingDay(date: studyDay, duration: dailyBase + pre, breakdown: departing)

        dailyBase = 0
        dailyByType = [:]
        if isRunning, let start = runStartedAt {
            // Time after the boundary belongs to the new day. If the run began
            // after the boundary (an intent started it before anyone rolled
            // over), it already does.
            runStartedAt = max(start, boundary)
        }
        studyDay = current
        return day.duration > 0 ? day : nil
    }

    /// The start-of-day date of the Study Day containing `now`: today if it is
    /// 4am or later, otherwise yesterday.
    static func studyDayStart(for now: Date, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 4
        comps.minute = 0
        comps.second = 0
        let today4am = calendar.date(from: comps) ?? now
        let anchor = now < today4am
            ? (calendar.date(byAdding: .day, value: -1, to: today4am) ?? today4am)
            : today4am
        return calendar.startOfDay(for: anchor)
    }

    /// 4am on the day after `studyDay`: the instant that Study Day ends.
    static func boundary(after studyDay: Date, calendar: Calendar = .current) -> Date {
        let next = calendar.date(byAdding: .day, value: 1, to: studyDay) ?? studyDay
        return calendar.date(bySettingHour: 4, minute: 0, second: 0, of: next) ?? next
    }

    // MARK: - Merge

    /// Last Clock Action wins. On a tie the state that has rolled further
    /// forward wins, and failing that the local one.
    static func merged(local: ClockSnapshot, remote: ClockSnapshot) -> ClockSnapshot {
        if remote.lastActionAt > local.lastActionAt { return remote }
        if remote.lastActionAt < local.lastActionAt { return local }
        return remote.studyDay > local.studyDay ? remote : local
    }
}

/// The figures of a Study Day that just ended, waiting to become a Session.
nonisolated struct DepartingDay: Equatable, Codable {
    let date: Date
    let duration: TimeInterval
    let breakdown: [StudyType: TimeInterval]
}

// MARK: - App-group suite persistence

nonisolated extension ClockSnapshot {
    /// Reads the Clock State from the shared suite. Understands the pre-sync
    /// layout too: `lastResetDate` becomes the Study Day when `studyDay` is
    /// absent, so an existing install carries its day over untouched.
    init(suite: UserDefaults) {
        isRunning = suite.bool(forKey: TimerKey.timerRunning)
        runStartedAt = suite.object(forKey: TimerKey.timerStartedAt) as? Date
        mode = suite.studyMode
        if let day = suite.object(forKey: TimerKey.studyDay) as? Date {
            studyDay = day
        } else if let legacy = suite.object(forKey: TimerKey.legacyLastResetDate) as? Date {
            studyDay = Calendar.current.startOfDay(for: legacy)
        }
        dailyBase = suite.double(forKey: TimerKey.dailyElapsed)
        for type in StudyType.allCases {
            let v = suite.double(forKey: TimerKey.daily(type))
            if v > 0 { dailyByType[type] = v }
        }
        let goal = suite.double(forKey: TimerKey.dailyGoal)
        dailyGoal = goal > 0 ? goal : defaultDailyGoal
        lastActionAt = suite.object(forKey: TimerKey.lastActionAt) as? Date ?? .distantPast
        lastActionDevice = suite.string(forKey: TimerKey.lastActionDevice) ?? ""
    }

    func write(to suite: UserDefaults) {
        suite.set(isRunning, forKey: TimerKey.timerRunning)
        if let runStartedAt {
            suite.set(runStartedAt, forKey: TimerKey.timerStartedAt)
        } else {
            suite.removeObject(forKey: TimerKey.timerStartedAt)
        }
        suite.studyMode = mode
        suite.set(studyDay, forKey: TimerKey.studyDay)
        suite.set(dailyBase, forKey: TimerKey.dailyElapsed)
        for type in StudyType.allCases {
            suite.set(dailyByType[type] ?? 0, forKey: TimerKey.daily(type))
        }
        suite.set(dailyGoal, forKey: TimerKey.dailyGoal)
        suite.set(lastActionAt, forKey: TimerKey.lastActionAt)
        suite.set(lastActionDevice, forKey: TimerKey.lastActionDevice)
    }

    /// A stable id for this device, created on first use. Lives in the suite
    /// so the app and its extensions agree.
    static func deviceID(in suite: UserDefaults) -> String {
        if let id = suite.string(forKey: TimerKey.deviceID) { return id }
        let id = UUID().uuidString
        suite.set(id, forKey: TimerKey.deviceID)
        return id
    }

    // MARK: Departing days queued for the app

    /// Intents cannot reach SwiftData, so a Rollover they perform leaves the
    /// departing day here for the app to persist as a Session.
    static func enqueue(_ day: DepartingDay, in suite: UserDefaults) {
        var pending = pendingDepartingDays(in: suite)
        pending.append(day)
        suite.set(try? JSONEncoder().encode(pending), forKey: TimerKey.pendingSessions)
    }

    static func pendingDepartingDays(in suite: UserDefaults) -> [DepartingDay] {
        guard let data = suite.data(forKey: TimerKey.pendingSessions) else { return [] }
        return (try? JSONDecoder().decode([DepartingDay].self, from: data)) ?? []
    }

    static func clearPendingDepartingDays(in suite: UserDefaults) {
        suite.removeObject(forKey: TimerKey.pendingSessions)
    }
}
