import Foundation
import SwiftData
import CoreData

// MARK: - Backup data types (shared encoding contract for export/import)

private struct StatsBackup: Codable {
    let exportDate: Date
    let dailyElapsed: TimeInterval
    let totalElapsed: TimeInterval
    let lastResetDate: Date?
    let sessions: [SessionBackup]
    /// Per-type running totals, keyed by StudyType.rawValue. Optional so a
    /// backup written before study types existed still decodes.
    var dailyByType: [String: TimeInterval]?
    var totalByType: [String: TimeInterval]?
}

private struct SessionBackup: Codable {
    let date: Date
    let duration: TimeInterval
    let isManualEdit: Bool
    var grammarDuration: TimeInterval?
    var immersionDuration: TimeInterval?
    var outputDuration: TimeInterval?
}

/// Bridges SwiftData StudySession records with business logic for charts and stats.
@Observable
final class StudyStore {
    var modelContext: ModelContext?

    init() {}

    // MARK: - Write operations (require modelContext)

    /// Create or update the StudySession for a given date.
    ///
    /// `breakdown` nil means "total only" — the manual-edit path. It leaves any
    /// existing per-type values alone but clamps them to the new total, so a
    /// day edited down to 30m can never keep an hour of grammar on the books.
    /// A non-nil breakdown replaces the typed values outright; that is the
    /// timer's path, where the breakdown is authoritative.
    func upsertSession(
        date: Date,
        duration: TimeInterval,
        breakdown: [StudyType: TimeInterval]? = nil,
        isManual: Bool = false
    ) {
        guard let context = modelContext else { return }
        let normalized = Calendar.current.startOfDay(for: date)

        let descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.date == normalized }
        )
        if let existing = try? context.fetch(descriptor).first {
            // Skip no-op writes: every save echoes back as a store change
            // notification, and an unconditional timestamp bump would loop.
            let sameBreakdown = breakdown.map { b in
                StudyType.allCases.allSatisfy { existing.duration(for: $0) == max(0, b[$0] ?? 0) }
            } ?? true
            if existing.duration == duration, existing.isManualEdit == isManual, sameBreakdown {
                return
            }
            existing.duration = duration
            existing.isManualEdit = isManual
            existing.updatedAt = Date()
            Self.apply(breakdown, to: existing, total: duration)
        } else {
            let session = StudySession(date: normalized, duration: duration, isManualEdit: isManual)
            Self.apply(breakdown, to: session, total: duration)
            context.insert(session)
        }
        do {
            try context.save()
        } catch {
            print("StudyStore: save failed — \(error)")
        }
        refreshPastTotals()
    }

    /// Writes `breakdown` onto `session`, or clamps its existing typed values
    /// to `total` when the breakdown is nil.
    private static func apply(
        _ breakdown: [StudyType: TimeInterval]?,
        to session: StudySession,
        total: TimeInterval
    ) {
        if let breakdown {
            for type in StudyType.allCases {
                session.setDuration(max(0, breakdown[type] ?? 0), for: type)
            }
        } else {
            for type in StudyType.allCases {
                session.setDuration(min(session.duration(for: type), max(0, total)), for: type)
            }
        }
    }

    func deleteAllSessions() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<StudySession>()
        let all = (try? context.fetch(descriptor)) ?? []
        for session in all {
            context.delete(session)
        }
        do {
            try context.save()
        } catch {
            print("StudyStore: deleteAllSessions failed — \(error)")
        }
        refreshPastTotals()
    }

    /// Single session lookup — used by ManualEditView to pre-fill the duration field.
    func session(for date: Date) -> StudySession? {
        guard let context = modelContext else { return nil }
        let normalized = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.date == normalized }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Clock record (synced Clock State)

    /// The `TimerManager` whose derived totals this store keeps current.
    weak var timer: TimerManager?

    /// The single synced Clock State record, created on first use. If a
    /// first sync between two devices left more than one, the record with the
    /// latest action is kept and the others removed.
    func clockRecord() -> ClockState? {
        guard let context = modelContext else { return nil }
        let all = (try? context.fetch(FetchDescriptor<ClockState>())) ?? []
        guard let winner = all.max(by: { $0.lastActionAt < $1.lastActionAt }) else {
            let fresh = ClockState()
            context.insert(fresh)
            return fresh
        }
        for loser in all where loser !== winner {
            context.delete(loser)
        }
        return winner
    }

    /// Mirror the in-memory Clock State into the synced record.
    func saveClock(_ snapshot: ClockSnapshot) {
        guard let context = modelContext, let record = clockRecord() else { return }
        if record.snapshot != snapshot {
            record.apply(snapshot)
            try? context.save()
        }
    }

    /// The synced Clock State, if a record exists.
    func loadClock() -> ClockSnapshot? {
        clockRecord()?.snapshot
    }

    // MARK: - Sync (CloudKit via SwiftData)

    /// False when the container had to fall back to a local-only store.
    var cloudSyncEnabled = false

    /// When the store last reported a change that was not ours.
    private(set) var lastRemoteChangeAt: Date?

    /// Whether this device is signed into iCloud at all.
    var iCloudSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// One muted line for Settings: the only place sync status appears.
    var syncStatusText: String {
        guard cloudSyncEnabled else { return "iCloud · unavailable on this build" }
        guard iCloudSignedIn else { return "iCloud · not signed in" }
        guard let at = lastRemoteChangeAt else { return "iCloud · waiting for first sync" }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        return "iCloud · synced \(rel.localizedString(for: at, relativeTo: Date()))"
    }

    @ObservationIgnored private var remoteChangeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var remoteChangeTask: Task<Void, Never>?

    /// Listen for store changes. CloudKit imports and our own saves both post
    /// this; the handler is idempotent so it does not matter which it was.
    func startObservingRemoteChanges() {
        guard remoteChangeObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRemoteReconcile() }
        }
    }

    /// Coalesce bursts of notifications (an import touches many rows) into
    /// one reconcile shortly after the last one.
    private func scheduleRemoteReconcile() {
        remoteChangeTask?.cancel()
        remoteChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.handleRemoteChange()
        }
    }

    /// Adopt whatever arrived: the Clock State by the last-action-wins rule,
    /// then Sessions by de-duplication. The timer re-persists today from the
    /// winning state, so the two can never disagree.
    func handleRemoteChange() {
        guard let timer else { return }
        let before = timer.snapshot
        if let synced = loadClock() {
            timer.adopt(synced, notify: false)
        }
        dedupeSessions()
        if timer.snapshot != before {
            lastRemoteChangeAt = Date()
        } else if lastRemoteChangeAt == nil, cloudSyncEnabled, iCloudSignedIn {
            lastRemoteChangeAt = Date()
        }
    }

    // MARK: - Derived totals (ADR 0002)

    /// Recompute the sum of every Session other than the current Study Day's
    /// (which the Clock covers) and hand it to the timer, which caches it for
    /// the widgets and intents.
    func refreshPastTotals() {
        guard let timer else { return }
        let sessions = fetchAllSessions().filter { $0.date != timer.studyDay }
        let total = sessions.reduce(0) { $0 + $1.duration }
        var byType: [StudyType: TimeInterval] = [:]
        for type in StudyType.allCases {
            byType[type] = sessions.reduce(0) { $0 + $1.duration(for: type) }
        }
        timer.setPastTotals(total: total, byType: byType)
    }

    // MARK: - Merge hygiene

    /// Keep one Session per date: the most recently updated wins. Sessions
    /// dated on or after the current Study Day are left to the timer, which
    /// re-persists today from the winning Clock State.
    func dedupeSessions() {
        guard let context = modelContext else { return }
        let all = fetchAllSessions()
        var seen: [Date: StudySession] = [:]
        var removed = false
        for session in all {
            if let kept = seen[session.date] {
                let loser = kept.updatedAt >= session.updatedAt ? session : kept
                let winner = loser === kept ? session : kept
                context.delete(loser)
                seen[session.date] = winner
                removed = true
            } else {
                seen[session.date] = session
            }
        }
        if removed {
            try? context.save()
        }
        refreshPastTotals()
    }

    // MARK: - Backup & Restore

    /// Fetches all sessions and encodes them + current timer state into a dated JSON file
    /// in the system temp directory. Returns the file URL for sharing.
    func exportBackupFile(timer: TimerManager) throws -> URL {
        let sessions = fetchAllSessions()

        let backup = StatsBackup(
            exportDate: Date(),
            dailyElapsed: timer.computedDaily,
            totalElapsed: timer.computedTotal,
            lastResetDate: timer.studyDay > .distantPast ? timer.studyDay : nil,
            sessions: sessions.map {
                SessionBackup(
                    date: $0.date,
                    duration: $0.duration,
                    isManualEdit: $0.isManualEdit,
                    grammarDuration: $0.grammarDuration,
                    immersionDuration: $0.immersionDuration,
                    outputDuration: $0.outputDuration
                )
            },
            dailyByType: Self.rawKeyed(timer.currentDayBreakdown()),
            totalByType: Self.rawKeyed(timer.allTimeBreakdown())
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "russian-stats-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Parses a backup file and returns a human-readable summary for the confirmation alert.
    /// Call this before `applyBackup` so the user sees what they're restoring.
    func importPreview(from url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(StatsBackup.self, from: data)
        let dateStr = backup.exportDate.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
        let hours = String(format: "%.1f", backup.totalElapsed / 3600)
        return "Backup from \(dateStr)\n\(backup.sessions.count) sessions · \(hours)h total\n\nThis will permanently overwrite all current stats."
    }

    /// Restores all sessions and timer state from a backup file.
    ///
    /// Pauses the timer, replaces the Sessions, then installs a paused Clock
    /// State carrying the backup's day. The restore is stamped as a Clock
    /// Action so it wins over whatever stale state other devices still hold.
    func applyBackup(from url: URL, timer: TimerManager) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(StatsBackup.self, from: data)

        if timer.isRunning { timer.pause() }

        deleteAllSessions()
        guard let context = modelContext else { return }
        for s in backup.sessions {
            context.insert(StudySession(
                date: s.date,
                duration: s.duration,
                isManualEdit: s.isManualEdit,
                grammarDuration: s.grammarDuration ?? 0,
                immersionDuration: s.immersionDuration ?? 0,
                outputDuration: s.outputDuration ?? 0
            ))
        }
        try? context.save()

        var restored = ClockSnapshot()
        restored.studyDay = backup.lastResetDate.map { Calendar.current.startOfDay(for: $0) }
            ?? ClockSnapshot.studyDayStart(for: Date())
        restored.dailyBase = backup.dailyElapsed
        // A pre-study-type backup carries no buckets, in which case they stay
        // empty rather than showing the old app's numbers.
        for type in StudyType.allCases {
            if let v = backup.dailyByType?[type.rawValue], v > 0 {
                restored.dailyByType[type] = v
            }
        }
        restored.dailyGoal = timer.dailyGoal
        restored.mode = timer.mode
        restored.lastActionAt = Date()
        timer.adopt(restored, notify: true)
        refreshPastTotals()
    }

    // MARK: - Private helpers

    private static func rawKeyed(_ breakdown: [StudyType: TimeInterval]) -> [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: breakdown.map { ($0.key.rawValue, $0.value) })
    }

    private func fetchAllSessions() -> [StudySession] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<StudySession>(sortBy: [SortDescriptor(\StudySession.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Stats
    // All methods below accept a pre-fetched [StudySession] from @Query in the calling view.
    // This lets SwiftUI's reactive system (not a manual `lastUpdated` flag) drive re-renders.

    func bestDay(from sessions: [StudySession]) -> StudySession? {
        sessions.max(by: { $0.duration < $1.duration })
    }

    func streak(from sessions: [StudySession]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateSet = Set(sessions.filter { $0.duration >= 60 }.map { $0.date })

        var count = 0
        var check = today
        // If today has no study time yet, start from yesterday
        if !dateSet.contains(today) {
            check = calendar.date(byAdding: .day, value: -1, to: today)!
        }
        while dateSet.contains(check) {
            count += 1
            check = calendar.date(byAdding: .day, value: -1, to: check)!
        }
        return count
    }

    func dailyAverage(from sessions: [StudySession], days: Int = 30) -> TimeInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))!
        let recent = sessions.filter { $0.date >= start }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.duration } / Double(days)
    }

    // MARK: - Chart data

    func lastNDays(_ n: Int, from sessions: [StudySession]) -> [(date: Date, duration: TimeInterval)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sessionMap = Dictionary(sessions.map { ($0.date, $0.duration) }, uniquingKeysWith: { $1 })
        return (0..<n).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            return (date, sessionMap[date] ?? 0)
        }
    }

    func lastNWeeks(_ n: Int, from sessions: [StudySession]) -> [(weekStart: Date, duration: TimeInterval)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<n).reversed().map { offset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeekStart)!
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
            let total = sessions
                .filter { $0.date >= weekStart && $0.date <= weekEnd }
                .reduce(0) { $0 + $1.duration }
            return (weekStart, total)
        }
    }

    /// Dense day grid for the current month. Carries each day's dominant study
    /// type alongside its total so the heatmap can tint by type while still
    /// scaling intensity by hours.
    func currentMonthDays(
        from sessions: [StudySession]
    ) -> [(date: Date, duration: TimeInterval, dominantType: StudyType?)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let monthInterval = calendar.dateInterval(of: .month, for: today) else { return [] }
        let daysInMonth = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 30
        let sessionMap = Dictionary(
            sessions.map { ($0.date, (duration: $0.duration, dominant: $0.dominantType)) },
            uniquingKeysWith: { $1 }
        )
        return (0..<daysInMonth).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monthInterval.start)!
            let entry = sessionMap[date]
            return (date, entry?.duration ?? 0, entry?.dominant)
        }
    }
}
