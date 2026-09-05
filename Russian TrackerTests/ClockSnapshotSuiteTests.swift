import Foundation
import Testing
@testable import Russian_Tracker

/// Round-trips through an isolated UserDefaults suite, including the
/// migration from the pre-sync key layout.
struct ClockSnapshotSuiteTests {
    func freshSuite() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func roundTripsThroughTheSuite() {
        let suite = freshSuite()
        var s = ClockSnapshot()
        s.studyDay = Calendar.current.startOfDay(for: Date())
        s.mode = .output
        s.dailyBase = 42
        s.dailyByType = [.output: 42]
        s.dailyGoal = 7200
        s.start(at: Date(), device: "dev")
        s.write(to: suite)
        #expect(ClockSnapshot(suite: suite) == s)
    }

    @Test func migratesLegacyLastResetDateIntoStudyDay() {
        let suite = freshSuite()
        let legacy = Date().addingTimeInterval(-86400 * 3)
        suite.set(legacy, forKey: TimerKey.legacyLastResetDate)
        suite.set(120.0, forKey: TimerKey.dailyElapsed)
        let s = ClockSnapshot(suite: suite)
        #expect(s.studyDay == Calendar.current.startOfDay(for: legacy))
        #expect(s.dailyBase == 120)
    }

    @Test func queuesAndDrainsDepartingDays() {
        let suite = freshSuite()
        let day = DepartingDay(date: Date(), duration: 10, breakdown: [.grammar: 10])
        ClockSnapshot.enqueue(day, in: suite)
        ClockSnapshot.enqueue(day, in: suite)
        #expect(ClockSnapshot.pendingDepartingDays(in: suite).count == 2)
        ClockSnapshot.clearPendingDepartingDays(in: suite)
        #expect(ClockSnapshot.pendingDepartingDays(in: suite).isEmpty)
    }
}
