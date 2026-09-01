import Foundation
import SwiftData

// MARK: - Backup data types (shared encoding contract for export/import)

private struct StatsBackup: Codable {
    let exportDate: Date
    let dailyElapsed: TimeInterval
    let totalElapsed: TimeInterval
    let lastResetDate: Date?
    let sessions: [SessionBackup]
}

private struct SessionBackup: Codable {
    let date: Date
    let duration: TimeInterval
    let isManualEdit: Bool
}

/// Bridges SwiftData StudySession records with business logic for charts and stats.
@Observable
final class StudyStore {
    var modelContext: ModelContext?

    init() {}

    // MARK: - Write operations (require modelContext)

    /// Create or update the StudySession for a given date.
    func upsertSession(date: Date, duration: TimeInterval, isManual: Bool = false) {
        guard let context = modelContext else { return }
        let normalized = Calendar.current.startOfDay(for: date)

        let descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.date == normalized }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.duration = duration
            existing.isManualEdit = isManual
        } else {
            let session = StudySession(date: normalized, duration: duration, isManualEdit: isManual)
            context.insert(session)
        }
        do {
            try context.save()
        } catch {
            print("StudyStore: save failed — \(error)")
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

    // MARK: - Data Integrity

    /// One-time recalibration to fix totalElapsed if it was corrupted by the
    /// double-counting bug in check4amBoundary (which previously added dailyElapsed
    /// to totalElapsed even though totalElapsed already included dailyElapsed).
    /// Recomputes totalElapsed as sum-of-past-sessions + today's dailyElapsed,
    /// then marks the migration done so it never runs again.
    func recalibrateTotalIfNeeded(timer: TimerManager) {
        let suite = UserDefaults(suiteName: appGroupSuite)
        let migrationKey = "totalRecalibratedV2"
        guard !(suite?.bool(forKey: migrationKey) ?? false) else { return }
        guard let context = modelContext else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.date < today }
        )
        let pastSessions = (try? context.fetch(descriptor)) ?? []
        let pastTotal = pastSessions.reduce(0) { $0 + $1.duration }
        let todayDaily = suite?.double(forKey: "dailyElapsed") ?? 0

        suite?.set(pastTotal + todayDaily, forKey: "totalElapsed")
        suite?.set(true, forKey: migrationKey)
        timer.onForeground()
    }

    // MARK: - Backup & Restore

    /// Fetches all sessions and encodes them + current timer state into a dated JSON file
    /// in the system temp directory. Returns the file URL for sharing.
    func exportBackupFile(timer: TimerManager) throws -> URL {
        let sessions = fetchAllSessions()
        let suite = UserDefaults(suiteName: appGroupSuite)
        let lastResetDate = suite?.object(forKey: "lastResetDate") as? Date

        let backup = StatsBackup(
            exportDate: Date(),
            dailyElapsed: timer.computedDaily,
            totalElapsed: timer.computedTotal,
            lastResetDate: lastResetDate,
            sessions: sessions.map {
                SessionBackup(date: $0.date, duration: $0.duration, isManualEdit: $0.isManualEdit)
            }
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
    /// Pauses the timer, replaces SwiftData records, writes UserDefaults, then rehydrates.
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
            context.insert(StudySession(date: s.date, duration: s.duration, isManualEdit: s.isManualEdit))
        }
        try? context.save()

        let suite = UserDefaults(suiteName: appGroupSuite)
        suite?.set(backup.dailyElapsed, forKey: "dailyElapsed")
        suite?.set(backup.totalElapsed, forKey: "totalElapsed")
        suite?.set(false,              forKey: "timerRunning")
        suite?.removeObject(forKey: "timerStartedAt")
        if let lastReset = backup.lastResetDate {
            suite?.set(lastReset, forKey: "lastResetDate")
        }

        // Rehydrate all in-memory timer state from the restored UserDefaults values.
        timer.onForeground()
    }

    // MARK: - Private helpers

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

    func currentMonthDays(from sessions: [StudySession]) -> [(date: Date, duration: TimeInterval)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let monthInterval = calendar.dateInterval(of: .month, for: today) else { return [] }
        let daysInMonth = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 30
        let sessionMap = Dictionary(sessions.map { ($0.date, $0.duration) }, uniquingKeysWith: { $1 })
        return (0..<daysInMonth).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monthInterval.start)!
            return (date, sessionMap[date] ?? 0)
        }
    }
}
