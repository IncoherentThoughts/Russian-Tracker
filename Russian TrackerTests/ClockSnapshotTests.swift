import Foundation
import Testing
@testable import Russian_Tracker

/// Pure tests of the Clock State value type: the conflict rule, the Rollover,
/// and the derived figures. No SwiftData, no UserDefaults.
struct ClockSnapshotTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func day(_ y: Int, _ mo: Int, _ d: Int) -> Date {
        cal.startOfDay(for: date(y, mo, d, 12))
    }

    // MARK: - Study Day arithmetic

    @Test func studyDayStartsAtFourAM() {
        #expect(ClockSnapshot.studyDayStart(for: date(2026, 9, 5, 3, 59), calendar: cal) == day(2026, 9, 4))
        #expect(ClockSnapshot.studyDayStart(for: date(2026, 9, 5, 4, 0), calendar: cal) == day(2026, 9, 5))
        #expect(ClockSnapshot.boundary(after: day(2026, 9, 4), calendar: cal) == date(2026, 9, 5, 4))
    }

    // MARK: - Actions bank time

    @Test func pauseBanksTheRunIntoTheActiveType() {
        var s = ClockSnapshot()
        s.studyDay = day(2026, 9, 5)
        s.mode = .immersion
        s.start(at: date(2026, 9, 5, 9), device: "a")
        s.pause(at: date(2026, 9, 5, 10), device: "a")
        #expect(s.dailyBase == 3600)
        #expect(s.dailyByType[.immersion] == 3600)
        #expect(s.isRunning == false)
        #expect(s.lastActionAt == date(2026, 9, 5, 10))
    }

    @Test func modeSwitchSplitsARunWithoutJumpingTheDisplay() {
        var s = ClockSnapshot()
        s.studyDay = day(2026, 9, 5)
        s.start(at: date(2026, 9, 5, 9), device: "a")
        let before = s.daily(at: date(2026, 9, 5, 9, 30))
        s.setMode(.anki, at: date(2026, 9, 5, 9, 30), device: "a")
        #expect(s.daily(at: date(2026, 9, 5, 9, 30)) == before)
        #expect(s.dailyByType[.grammar] == 1800)
        #expect(s.daily(for: .anki, at: date(2026, 9, 5, 10)) == 1800)
        #expect(s.isRunning)
    }

    // MARK: - Conflict rule (ADR 0001, Q10 scenario)

    @Test func laterActionWinsAndKeepsBankedMinutes() {
        var shared = ClockSnapshot()
        shared.studyDay = day(2026, 9, 5)
        shared.start(at: date(2026, 9, 5, 9), device: "mac")

        var mac = shared
        mac.pause(at: date(2026, 9, 5, 10), device: "mac")       // offline

        var phone = shared
        phone.pause(at: date(2026, 9, 5, 10, 2), device: "phone")

        let merged = ClockSnapshot.merged(local: mac, remote: phone)
        #expect(merged == phone)
        #expect(merged.dailyBase == 3720)   // 9:00–10:02 counted once
    }

    @Test func tieBreaksTowardTheStateThatRolledForward() {
        var a = ClockSnapshot()
        a.studyDay = day(2026, 9, 4)
        a.lastActionAt = date(2026, 9, 4, 22)
        var b = a
        _ = b.rollover(now: date(2026, 9, 5, 7), calendar: cal)
        #expect(ClockSnapshot.merged(local: a, remote: b).studyDay == day(2026, 9, 5))
        #expect(ClockSnapshot.merged(local: b, remote: a).studyDay == day(2026, 9, 5))
    }

    // MARK: - Rollover

    @Test func rolloverSplitsARunningClockAtTheBoundary() {
        var s = ClockSnapshot()
        s.studyDay = day(2026, 9, 4)
        s.dailyBase = 600
        s.dailyByType[.grammar] = 600
        s.start(at: date(2026, 9, 5, 3), device: "a")

        let departing = s.rollover(now: date(2026, 9, 5, 7), calendar: cal)
        #expect(departing?.date == day(2026, 9, 4))
        #expect(departing?.duration == 4200.0)
        #expect(departing?.breakdown[.grammar] == 4200.0)
        #expect(s.studyDay == day(2026, 9, 5))
        #expect(s.dailyBase == 0)
        #expect(s.runStartedAt == date(2026, 9, 5, 4))
        #expect(s.daily(at: date(2026, 9, 5, 7)) == 3 * 3600)
        #expect(s.isRunning)
    }

    @Test func rolloverIsIdempotentAndDoesNotStampAnAction() {
        var s = ClockSnapshot()
        s.studyDay = day(2026, 9, 4)
        s.dailyBase = 100
        s.lastActionAt = date(2026, 9, 4, 20)
        #expect(s.rollover(now: date(2026, 9, 5, 7), calendar: cal) != nil)
        let after = s
        #expect(s.rollover(now: date(2026, 9, 5, 7), calendar: cal) == nil)
        #expect(s == after)
        #expect(s.lastActionAt == date(2026, 9, 4, 20))
    }

    @Test func rolloverKeepsARunThatBeganAfterTheBoundary() {
        // An intent started the Clock at 5am before anyone rolled over.
        var s = ClockSnapshot()
        s.studyDay = day(2026, 9, 4)
        s.dailyBase = 900
        s.start(at: date(2026, 9, 5, 5), device: "a")
        let departing = s.rollover(now: date(2026, 9, 5, 6), calendar: cal)
        #expect(departing?.duration == 900.0)
        #expect(s.runStartedAt == date(2026, 9, 5, 5))
        #expect(s.daily(at: date(2026, 9, 5, 6)) == 3600)
    }

    @Test func freshInstallAdoptsTodayWithoutDeparting() {
        var s = ClockSnapshot()
        #expect(s.rollover(now: date(2026, 9, 5, 12), calendar: cal) == nil)
        #expect(s.studyDay == day(2026, 9, 5))
    }

    // MARK: - Manual edit and reset

    @Test func manualEditClampsTypedBuckets() {
        var s = ClockSnapshot()
        s.studyDay = day(2026, 9, 5)
        s.dailyBase = 3600
        s.dailyByType = [.grammar: 3000, .anki: 600]
        s.setManualDaily(1800, at: date(2026, 9, 5, 12), device: "a")
        #expect(s.dailyBase == 1800)
        #expect(s.dailyByType[.grammar] == 1800)
        #expect(s.dailyByType[.anki] == 600)
    }

    @Test func resetDailyKeepsARunningClockRunningFromNow() {
        var s = ClockSnapshot()
        s.studyDay = day(2026, 9, 5)
        s.start(at: date(2026, 9, 5, 9), device: "a")
        s.resetDaily(at: date(2026, 9, 5, 10), device: "a")
        #expect(s.isRunning)
        #expect(s.daily(at: date(2026, 9, 5, 10)) == 0)
        #expect(s.daily(at: date(2026, 9, 5, 11)) == 3600)
    }
}
