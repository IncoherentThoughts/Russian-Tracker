import Foundation
import Testing
@testable import Russian_Tracker

struct SessionSyncPlanTests {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }
    private func at(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n)) }

    @Test func remoteOnlyIsAdopted() {
        let plan = SessionSyncPlan.make(
            local: [],
            remote: [.init(date: day(1), updatedAt: at(10))],
            initialUpload: false
        )
        #expect(plan.adoptRemote == [day(1)])
        #expect(plan.upload.isEmpty && plan.deleteLocal.isEmpty)
    }

    @Test func laterUpdateWinsEachWay() {
        let plan = SessionSyncPlan.make(
            local: [
                .init(date: day(1), updatedAt: at(20), needsUpload: false),
                .init(date: day(2), updatedAt: at(5), needsUpload: false),
            ],
            remote: [
                .init(date: day(1), updatedAt: at(10)),
                .init(date: day(2), updatedAt: at(9)),
            ],
            initialUpload: false
        )
        #expect(plan.upload == [day(1)])
        #expect(plan.adoptRemote == [day(2)])
        #expect(plan.deleteLocal.isEmpty)
    }

    @Test func localOnlyIsDeletedUnlessPendingOrInitial() {
        let local: [SessionSyncPlan.Local] = [
            .init(date: day(1), updatedAt: at(1), needsUpload: false),
            .init(date: day(2), updatedAt: at(1), needsUpload: true),
        ]
        let plan = SessionSyncPlan.make(local: local, remote: [], initialUpload: false)
        #expect(plan.deleteLocal == [day(1)])
        #expect(plan.upload == [day(2)])

        let first = SessionSyncPlan.make(local: local, remote: [], initialUpload: true)
        #expect(first.deleteLocal.isEmpty)
        #expect(first.upload == [day(1), day(2)])
    }

    @Test func equalTimestampsAreQuiet() {
        let plan = SessionSyncPlan.make(
            local: [.init(date: day(1), updatedAt: at(10), needsUpload: false)],
            remote: [.init(date: day(1), updatedAt: at(10))],
            initialUpload: false
        )
        #expect(plan == SessionSyncPlan())
    }

    @Test func wireDatesRoundTrip() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000.25)
        #expect(SyncDate.date(SyncDate.string(instant)) == instant)
        #expect(SyncDate.date("2026-09-05 12:34:56.123456+00") != nil)
        #expect(SyncDate.date("2026-09-05T12:34:56+00:00") != nil)
        let today = Calendar.current.startOfDay(for: Date())
        #expect(SyncDate.day(SyncDate.dayString(today)) == today)
    }
}
