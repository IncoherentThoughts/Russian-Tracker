import Foundation
import Observation
import Supabase
#if os(macOS)
import AppKit
#endif

// MARK: - Rows

/// `public.clock_state`, one row per Account.
nonisolated struct ClockRow: Codable, Equatable {
    var user_id: String
    var is_running: Bool
    var run_started_at: String?
    var mode: String
    var study_day: String
    var daily_base: Double
    var daily_grammar: Double
    var daily_immersion: Double
    var daily_anki: Double
    var daily_goal: Double
    var last_action_at: String
    var last_action_device: String

    init(_ s: ClockSnapshot, userID: String) {
        user_id = userID
        is_running = s.isRunning
        run_started_at = s.runStartedAt.map(SyncDate.string)
        mode = s.mode.rawValue
        study_day = SyncDate.string(s.studyDay)
        daily_base = s.dailyBase
        daily_grammar = s.dailyByType[.grammar] ?? 0
        daily_immersion = s.dailyByType[.immersion] ?? 0
        daily_anki = s.dailyByType[.anki] ?? 0
        daily_goal = s.dailyGoal
        last_action_at = SyncDate.string(s.lastActionAt)
        last_action_device = s.lastActionDevice
    }

    var snapshot: ClockSnapshot {
        var s = ClockSnapshot()
        s.isRunning = is_running
        s.runStartedAt = run_started_at.flatMap(SyncDate.date)
        s.mode = StudyType(stored: mode) ?? .grammar
        s.studyDay = SyncDate.date(study_day) ?? .distantPast
        s.dailyBase = daily_base
        s.dailyByType = [.grammar: daily_grammar, .immersion: daily_immersion, .anki: daily_anki]
            .filter { $0.value > 0 }
        s.dailyGoal = daily_goal
        s.lastActionAt = SyncDate.date(last_action_at) ?? .distantPast
        s.lastActionDevice = last_action_device
        return s
    }
}

/// `public.sessions`, primary key (`user_id`, `date`).
nonisolated struct SessionRow: Codable, Equatable {
    var user_id: String
    var date: String
    var duration: Double
    var grammar: Double
    var immersion: Double
    var anki: Double
    var is_manual_edit: Bool
    var updated_at: String

    var day: Date? { SyncDate.day(date) }
    var updatedAt: Date { SyncDate.date(updated_at) ?? .distantPast }
    var breakdown: [StudyType: TimeInterval] {
        [.grammar: grammar, .immersion: immersion, .anki: anki]
    }
}

// MARK: - Client

/// The Account and the wire between this device and the server (ADR 0003).
///
/// Local-first: every change lands in the suite / SwiftData first and is
/// marked for upload; `flush()` sends what is pending and retries on failure.
/// `pull()` reconciles a full copy on sign-in, foreground, wake, and on a
/// timer while active. Realtime delivers other devices' changes in between.
@MainActor
@Observable
final class SyncClient {
    enum Step: Equatable {
        case signedOut
        case signedIn(email: String)
    }

    private(set) var step: Step = .signedOut
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var busy = false

    @ObservationIgnored weak var timer: TimerManager?
    @ObservationIgnored weak var store: StudyStore?

    @ObservationIgnored private let client: SupabaseClient
    @ObservationIgnored private let suite: UserDefaults
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var authTask: Task<Void, Never>?
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var listenTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var flushAgain = false
    @ObservationIgnored private var active = false

    init(suite: UserDefaults) {
        self.suite = suite
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.publishableKey,
            options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        if let at = suite.object(forKey: TimerKey.syncLastPulledAt) as? Date {
            lastSyncAt = at
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = step { return true }
        return false
    }

    /// One muted line for Settings.
    var statusText: String {
        switch step {
        case .signedOut:
            return "Not signed in"
        case .signedIn:
            if let lastError { return lastError }
            guard let at = lastSyncAt else { return "Waiting for first sync" }
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .short
            return "Synced \(rel.localizedString(for: at, relativeTo: Date()))"
        }
    }

    // MARK: Lifecycle

    /// Follow the stored session: a device that signed in once stays signed
    /// in; the SDK refreshes the token silently.
    func start() {
        guard authTask == nil else { return }
        authTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session {
                        await self.activate(session)
                    } else {
                        self.deactivate()
                    }
                case .signedOut, .userDeleted:
                    self.deactivate()
                default:
                    break
                }
            }
        }
        #if os(macOS)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.pull() }
        }
        #endif
    }

    /// App came to the foreground (iOS) or launched (both).
    func resume() {
        active = true
        guard userID != nil else { return }
        Task { await pull() }
        subscribe()
        startPeriodicPull()
    }

    /// App went to the background (iOS). The Mac app never suspends.
    func suspend() {
        active = false
        Task { await flush() }
        #if os(iOS)
        unsubscribe()
        periodicTask?.cancel()
        periodicTask = nil
        #endif
    }

    private func activate(_ session: Session) async {
        let uid = session.user.id.uuidString.lowercased()
        let email = session.user.email ?? ""
        if userID == uid {
            if case .signedIn = step { return }
        }
        userID = uid
        step = .signedIn(email: email)
        lastError = nil
        active = true
        await pull()
        subscribe()
        startPeriodicPull()
    }

    private func deactivate() {
        userID = nil
        unsubscribe()
        periodicTask?.cancel()
        periodicTask = nil
        retryTask?.cancel()
        retryTask = nil
        step = .signedOut
    }

    // MARK: Auth

    /// Email + password, once per device. Signing in with an address that
    /// has no Account yet creates it; "Confirm email" is off on the project,
    /// so no email is sent and the session starts immediately.
    func signIn(email rawEmail: String, password: String) async {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else {
            lastError = "Enter an email address"
            return
        }
        guard password.count >= 6 else {
            lastError = "Password needs at least 6 characters"
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await client.auth.signIn(email: email, password: password)
            lastError = nil
        } catch {
            // No such Account yet: create it with these credentials.
            do {
                let result = try await client.auth.signUp(email: email, password: password)
                if result.session == nil {
                    lastError = "Account created; confirm the email, then sign in"
                } else {
                    lastError = nil
                }
            } catch let signUpError {
                lastError = Self.describe(Self.prefer(error, over: signUpError))
            }
        }
        // `authStateChanges` delivers `.signedIn` and activates.
    }

    /// When both sign-in and sign-up fail, the sign-in error is the useful
    /// one for an existing Account (wrong password); otherwise the sign-up's.
    private static func prefer(_ signIn: Error, over signUp: Error) -> Error {
        let text = signUp.localizedDescription.lowercased()
        return text.contains("already") ? signIn : signUp
    }

    func signOut() async {
        busy = true
        defer { busy = false }
        await flush()
        try? await client.auth.signOut()
        suite.removeObject(forKey: TimerKey.syncUploadedFor)
        deactivate()
        lastError = nil
    }

    // MARK: Local changes → server

    /// A Clock Action happened here. Upload soon.
    func clockChanged() {
        suite.set(true, forKey: TimerKey.syncClockDirty)
        scheduleFlush()
    }

    /// A Session was written locally and marked `needsUpload`.
    func sessionsChanged() {
        scheduleFlush()
    }

    /// A global reset: the Account's Sessions go away on the server too.
    func deleteAllRemote() {
        suite.set(true, forKey: TimerKey.syncPendingDeleteAll)
        scheduleFlush()
    }

    private func scheduleFlush() {
        Task { await flush() }
    }

    /// Send what is pending, in order: the reset, the Clock, the Sessions.
    /// Runs one at a time; a request that arrives mid-flush queues another.
    func flush() async {
        guard let uid = userID, let timer, let store else { return }
        if flushing { flushAgain = true; return }
        flushing = true
        defer {
            flushing = false
            if flushAgain { flushAgain = false; Task { await flush() } }
        }
        do {
            if suite.bool(forKey: TimerKey.syncPendingDeleteAll) {
                try await client.from("sessions").delete().eq("user_id", value: uid).execute()
                suite.set(false, forKey: TimerKey.syncPendingDeleteAll)
            }
            if suite.bool(forKey: TimerKey.syncClockDirty) {
                let row = ClockRow(timer.snapshot, userID: uid)
                try await client.from("clock_state").upsert(row, onConflict: "user_id").execute()
                suite.set(false, forKey: TimerKey.syncClockDirty)
            }
            let pending = store.sessionsNeedingUpload()
            if !pending.isEmpty {
                let rows = pending.map { s in
                    SessionRow(
                        user_id: uid,
                        date: SyncDate.dayString(s.date),
                        duration: s.duration,
                        grammar: s.grammarDuration,
                        immersion: s.immersionDuration,
                        anki: s.ankiDuration,
                        is_manual_edit: s.isManualEdit,
                        updated_at: SyncDate.string(s.updatedAt)
                    )
                }
                try await client.from("sessions").upsert(rows, onConflict: "user_id,date").execute()
                store.markUploaded(pending)
            }
            lastError = nil
            retryTask?.cancel()
            retryTask = nil
        } catch {
            lastError = "Sync failed · " + Self.describe(error)
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            await self.flush()
        }
    }

    // MARK: Server → local

    /// Full reconcile: the Clock by last-action-wins, Sessions by
    /// `SessionSyncPlan`. Then upload whatever this device still holds.
    func pull() async {
        guard let uid = userID, let timer, let store else { return }
        do {
            let clocks: [ClockRow] = try await client.from("clock_state")
                .select().eq("user_id", value: uid).execute().value
            if let remote = clocks.first?.snapshot {
                timer.adopt(remote, notify: false)
                if timer.snapshot != remote {
                    suite.set(true, forKey: TimerKey.syncClockDirty)
                }
            } else {
                suite.set(true, forKey: TimerKey.syncClockDirty)
            }

            let rows: [SessionRow] = try await client.from("sessions")
                .select().eq("user_id", value: uid).execute().value
            let initial = suite.string(forKey: TimerKey.syncUploadedFor) != uid
            let local = store.allSessions()
            let plan = SessionSyncPlan.make(
                local: local.map { .init(date: $0.date, updatedAt: $0.updatedAt, needsUpload: $0.needsUpload) },
                remote: rows.compactMap { r in r.day.map { .init(date: $0, updatedAt: r.updatedAt) } },
                initialUpload: initial
            )
            let rowsByDay = Dictionary(rows.compactMap { r in r.day.map { ($0, r) } },
                                       uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
            for date in plan.adoptRemote {
                if let r = rowsByDay[date] { store.applyRemote(r) }
            }
            for date in plan.deleteLocal { store.deleteSession(on: date) }
            store.markNeedsUpload(dates: Set(plan.upload))
            suite.set(uid, forKey: TimerKey.syncUploadedFor)
            store.refreshPastTotals()

            lastSyncAt = Date()
            suite.set(lastSyncAt, forKey: TimerKey.syncLastPulledAt)
            lastError = nil
        } catch {
            lastError = "Sync failed · " + Self.describe(error)
        }
        await flush()
    }

    private func startPeriodicPull() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, self.active else { continue }
                await self.pull()
            }
        }
    }

    // MARK: Realtime

    private func subscribe() {
        guard channel == nil, let uid = userID else { return }
        let ch = client.channel("sync-\(uid)")
        let clockChanges = ch.postgresChange(AnyAction.self, schema: "public", table: "clock_state")
        let sessionChanges = ch.postgresChange(AnyAction.self, schema: "public", table: "sessions")
        channel = ch
        listenTasks = [
            Task { [weak self] in
                for await change in clockChanges {
                    guard !Task.isCancelled else { return }
                    self?.handleClockChange(change)
                }
            },
            Task { [weak self] in
                for await change in sessionChanges {
                    guard !Task.isCancelled else { return }
                    self?.handleSessionChange(change)
                }
            },
            Task {
                await ch.subscribe()
            },
        ]
    }

    private func unsubscribe() {
        for task in listenTasks { task.cancel() }
        listenTasks = []
        if let ch = channel {
            channel = nil
            Task { await ch.unsubscribe() }
        }
    }

    private func handleClockChange(_ change: AnyAction) {
        guard let timer else { return }
        let record: [String: AnyJSON]
        switch change {
        case .insert(let a): record = a.record
        case .update(let a): record = a.record
        default: return
        }
        guard let row = try? Self.decode(ClockRow.self, from: record) else { return }
        let remote = row.snapshot
        timer.adopt(remote, notify: false)
        if timer.snapshot != remote {
            suite.set(true, forKey: TimerKey.syncClockDirty)
            scheduleFlush()
        }
        lastSyncAt = Date()
    }

    private func handleSessionChange(_ change: AnyAction) {
        guard let store else { return }
        switch change {
        case .insert(let a):
            if let row = try? Self.decode(SessionRow.self, from: a.record) { store.applyRemote(row) }
        case .update(let a):
            if let row = try? Self.decode(SessionRow.self, from: a.record) { store.applyRemote(row) }
        case .delete(let a):
            if let raw = a.oldRecord["date"]?.stringValue, let day = SyncDate.day(raw) {
                store.deleteSession(on: day, unlessPending: true)
            }
        default:
            break
        }
        store.refreshPastTotals()
        lastSyncAt = Date()
    }

    private static func decode<T: Decodable>(_ type: T.Type, from record: [String: AnyJSON]) throws -> T {
        let data = try JSONEncoder().encode(record)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func describe(_ error: Error) -> String {
        let text = error.localizedDescription
        return text.count > 80 ? String(text.prefix(77)) + "…" : text
    }
}
