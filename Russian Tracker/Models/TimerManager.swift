import Foundation
import Observation
import WidgetKit
#if os(iOS)
import ActivityKit
#endif

/// Owns the in-memory Clock State and performs every Clock Action.
///
/// The state itself is a `ClockSnapshot`. After each action the manager
/// writes it to the app-group suite (for intents and widgets), persists
/// today's Session, and hands the snapshot to `onStateChanged` so the app can
/// upload it (ADR 0003).
///
/// All-time figures are derived (ADR 0002): `pastTotal` is the cached sum of
/// every Session before the current Study Day, refreshed by `StudyStore`.
@Observable
final class TimerManager {
    // MARK: - Observed state (drives UI)
    private(set) var snapshot: ClockSnapshot
    private(set) var tick: Int = 0
    private(set) var pastTotal: TimeInterval = 0
    private(set) var pastByType: [StudyType: TimeInterval] = [:]

    var isRunning: Bool { snapshot.isRunning }
    var mode: StudyType { snapshot.mode }
    var studyDay: Date { snapshot.studyDay }
    var dailyGoal: TimeInterval { snapshot.dailyGoal }

    // MARK: - Hooks (set by Russian_TrackerApp once the store exists)

    /// Writes a Session for a Study Day. Departing days are queued in the suite
    /// until this is set, then drained.
    var persistSession: ((Date, TimeInterval, [StudyType: TimeInterval]) -> Void)? {
        didSet { drainPendingSessions() }
    }

    /// Called after every Clock Action with the new state. The app uploads it.
    var onStateChanged: ((ClockSnapshot) -> Void)?

    // MARK: - Private
    private var displayTimer: Timer?
    /// Seconds of display ticks since the last heartbeat (macOS).
    private var heartbeatTicks = 0
    private let suite: UserDefaults
    private let deviceID: String
    #if os(iOS)
    private var liveActivity: Activity<RussianTimerAttributes>?
    #endif

    // MARK: - Init
    init() {
        suite = UserDefaults(suiteName: appGroupSuite) ?? .standard
        deviceID = ClockSnapshot.deviceID(in: suite)
        snapshot = ClockSnapshot(suite: suite)
        pastTotal = suite.double(forKey: TimerKey.pastTotal)
        for type in StudyType.allCases {
            pastByType[type] = suite.double(forKey: TimerKey.pastTotal(type))
        }
        performRolloverIfNeeded()
        snapshot.write(to: suite)
        writeHeartbeat()
        if snapshot.isRunning { startDisplayTimer() }
        registerForStateChanges()
        refreshWidgets()
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - Computed display values

    var computedDaily: TimeInterval {
        _ = tick
        return snapshot.daily(at: Date())
    }

    var computedTotal: TimeInterval {
        pastTotal + computedDaily
    }

    func computedDaily(for type: StudyType) -> TimeInterval {
        _ = tick
        return snapshot.daily(for: type, at: Date())
    }

    func computedTotal(for type: StudyType) -> TimeInterval {
        (pastByType[type] ?? 0) + computedDaily(for: type)
    }

    func currentDayBreakdown() -> [StudyType: TimeInterval] {
        _ = tick
        return snapshot.breakdown(at: Date())
    }

    func allTimeBreakdown() -> [StudyType: TimeInterval] {
        Dictionary(uniqueKeysWithValues: StudyType.allCases.map { ($0, computedTotal(for: $0)) })
    }

    // MARK: - Lifecycle

    /// Call on app background/inactive. Nothing to bank — displayed time is
    /// always base plus in-flight — but today's Session should be current.
    func onBackground() {
        persistCurrentDaySession()
    }

    /// Call on every app foreground (and on wake / the 4am timer on macOS):
    /// adopt anything the intents wrote, roll over if needed, refresh.
    func onForeground() {
        reconcileFromSharedState()
        #if os(iOS)
        if let active = Activity<RussianTimerAttributes>.activities
            .first(where: { $0.activityState == .active }) {
            liveActivity = active
            Task { await active.update(contentForCurrentState()) }
        }
        #endif
    }

    // MARK: - Cross-process sync (intent → app)

    private func registerForStateChanges() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let manager = Unmanaged<TimerManager>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { manager.reconcileFromSharedState() }
            },
            timerStateChangedNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Adopt the state in the shared suite (written by an intent or by this
    /// app earlier), merge it with what we hold, and roll over if needed.
    /// An intent's action has not reached the synced record yet, so this
    /// notifies.
    func reconcileFromSharedState() {
        let shared = ClockSnapshot(suite: suite)
        adopt(shared, notify: true)
    }

    /// Merge `incoming` (from the suite or from the synced record) with the
    /// current state by the last-action-wins rule, then bring the day up to
    /// date. `notify` decides whether the merged state is pushed back out to
    /// the synced record — false when the state came from there.
    func adopt(_ incoming: ClockSnapshot, notify: Bool) {
        let merged = ClockSnapshot.merged(local: snapshot, remote: incoming)
        let changed = merged != snapshot
        snapshot = merged
        let rolled = performRolloverIfNeeded()
        snapshot.write(to: suite)
        writeHeartbeat()
        drainPendingSessions()
        syncDisplayTimer()
        persistCurrentDaySession()
        tick += 1
        if (changed || rolled) && notify {
            onStateChanged?(snapshot)
        }
        refreshWidgets()
        #if os(iOS)
        if changed || rolled { updateLiveActivityInPlace() }
        #endif
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        performRolloverIfNeeded()
        snapshot.start(at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        presentRunningActivity()
        #endif
    }

    func pause() {
        guard isRunning else { return }
        performRolloverIfNeeded()
        snapshot.pause(at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        updateLiveActivityInPlace()
        #endif
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Switch the active Study Type, splitting a running session at this
    /// moment. The clock itself never stops and the digits never jump.
    func setMode(_ newMode: StudyType) {
        guard newMode != mode else { return }
        performRolloverIfNeeded()
        snapshot.setMode(newMode, at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        updateLiveActivityInPlace()
        #endif
    }

    func setDailyGoal(hours: Int) {
        snapshot.setDailyGoal(TimeInterval(hours) * 3600, at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        updateLiveActivityInPlace()
        #endif
    }

    // MARK: - Resets

    func resetDaily() {
        performRolloverIfNeeded()
        snapshot.resetDaily(at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        endLiveActivity()
        if isRunning { presentRunningActivity() }
        #endif
    }

    /// Zero today and forget the cached past totals. The caller deletes the
    /// Sessions; the derived All-Time Total is then zero everywhere.
    func resetTotal() {
        resetDaily()
        setPastTotals(total: 0, byType: [:])
    }

    // MARK: - Manual edit support

    /// A Manual Edit for the current Study Day changes the Clock; edits of
    /// other days only touch Sessions and reach the total via `setPastTotals`.
    func applyManualEdit(date: Date, duration: TimeInterval) {
        performRolloverIfNeeded()
        guard Calendar.current.startOfDay(for: date) == snapshot.studyDay else { return }
        snapshot.setManualDaily(duration, at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        updateLiveActivityInPlace()
        #endif
    }

    // MARK: - Derived totals cache

    /// Set by `StudyStore` whenever Sessions change.
    func setPastTotals(total: TimeInterval, byType: [StudyType: TimeInterval]) {
        pastTotal = total
        pastByType = byType
        suite.set(total, forKey: TimerKey.pastTotal)
        for type in StudyType.allCases {
            suite.set(byType[type] ?? 0, forKey: TimerKey.pastTotal(type))
        }
        refreshWidgets()
    }

    // MARK: - Private helpers

    /// Write the state everywhere after a Clock Action.
    private func commit() {
        snapshot.write(to: suite)
        writeHeartbeat()
        syncDisplayTimer()
        persistCurrentDaySession()
        tick += 1
        onStateChanged?(snapshot)
        refreshWidgets()
    }

    // MARK: - Widgets

    /// Ask WidgetKit to re-read the suite. The timeline widget uses
    /// `.policy(.never)`, so this is the only way it learns about a change;
    /// the Control Center toggle likewise re-queries its value.
    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, macOS 26.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }

    /// macOS only: stamp the suite so the widget can tell the app is alive.
    /// A quit Mac app leaves the widget frozen (no Live Activity there), and
    /// the widget uses this to show "Open Russian Tracker to sync".
    private func writeHeartbeat() {
        #if os(macOS)
        suite.set(Date(), forKey: TimerKey.appHeartbeat)
        heartbeatTicks = 0
        #endif
    }

    /// Called once per second by the display timer while the Clock runs.
    private func displayTick() {
        tick += 1
        #if os(macOS)
        heartbeatTicks += 1
        if heartbeatTicks >= 60 {
            writeHeartbeat()
            // The widget schedules its stale hint 3 minutes past the last
            // heartbeat; reloading moves that deadline forward.
            refreshWidgets()
        }
        #endif
    }

    /// Runs the Rollover; any departing day is queued for persistence.
    @discardableResult
    private func performRolloverIfNeeded() -> Bool {
        let before = snapshot.studyDay
        if let day = snapshot.rollover(now: Date()) {
            ClockSnapshot.enqueue(day, in: suite)
            drainPendingSessions()
        }
        return snapshot.studyDay != before
    }

    private func drainPendingSessions() {
        guard let persistSession else { return }
        let pending = ClockSnapshot.pendingDepartingDays(in: suite)
        guard !pending.isEmpty else { return }
        ClockSnapshot.clearPendingDepartingDays(in: suite)
        for day in pending {
            persistSession(day.date, day.duration, day.breakdown)
        }
    }

    private func persistCurrentDaySession() {
        guard snapshot.studyDay > .distantPast else { return }
        let now = Date()
        let duration = snapshot.daily(at: now)
        guard duration > 0 else { return }
        persistSession?(snapshot.studyDay, duration, snapshot.breakdown(at: now))
    }

    private func syncDisplayTimer() {
        stopDisplayTimer()
        if isRunning { startDisplayTimer() }
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.displayTick() }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Live Activity management

    #if os(iOS)
    private func contentForCurrentState() -> ActivityContent<RussianTimerAttributes.ContentState> {
        let dismissAt = Date.now.addingTimeInterval(liveActivityIdleTimeout)
        return ActivityContent(state: snapshot.liveActivityState, staleDate: dismissAt)
    }

    /// Bring the Live Activity to a running .active state. Updates an existing
    /// active activity in place (smooth crossfade) or requests a fresh one if
    /// none exists (e.g. after the previous one fell out of dismissal grace).
    private func presentRunningActivity() {
        let allActivities = Activity<RussianTimerAttributes>.activities
        if let active = allActivities.first(where: { $0.activityState == .active }) {
            liveActivity = active
            Task { await active.update(contentForCurrentState()) }
            return
        }
        for ghost in allActivities {
            Task { await ghost.end(nil, dismissalPolicy: .immediate) }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            liveActivity = try Activity<RussianTimerAttributes>.request(
                attributes: RussianTimerAttributes(),
                content: contentForCurrentState()
            )
        } catch {
            print("[LiveActivity] request failed: \(error)")
        }
    }

    /// Smoothly update the Live Activity in place. Used for pause, resume and
    /// remote changes so no transition triggers a teardown/recreate flicker.
    private func updateLiveActivityInPlace() {
        let active = Activity<RussianTimerAttributes>.activities
            .first(where: { $0.activityState == .active || $0.activityState == .stale })
        guard let active else { return }
        liveActivity = active
        Task { await active.update(contentForCurrentState()) }
    }

    /// End every Live Activity, not just the one held in `liveActivity` — an
    /// activity started from the Lock Screen is owned by a different launch.
    private func endLiveActivity() {
        var final = snapshot
        final.isRunning = false
        final.runStartedAt = nil
        final.dailyBase = 0
        let content = ActivityContent(state: final.liveActivityState, staleDate: .now)
        let activities = Activity<RussianTimerAttributes>.activities
        Task {
            for activity in activities {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
        liveActivity = nil
    }
    #endif
}

// MARK: - TimeInterval formatting
extension TimeInterval {
    /// HH:MM:SS format
    var timerFormatted: String {
        let total = Int(max(0, self))
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// H:MM format for compact display
    var compactFormatted: String {
        let total = Int(max(0, self))
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm", minutes)
    }
}
