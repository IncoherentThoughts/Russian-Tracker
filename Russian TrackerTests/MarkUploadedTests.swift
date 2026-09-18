import Foundation
import SwiftData
import Testing
@testable import Russian_Tracker

/// `StudyStore.markUploaded` against an in-memory store: an upload only
/// settles the values it actually sent.
@MainActor
struct MarkUploadedTests {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    private func makeStore() throws -> (StudyStore, ModelContainer) {
        let container = try ModelContainer(
            for: StudySession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = StudyStore()
        store.modelContext = container.mainContext
        return (store, container)
    }

    @Test func editDuringUploadKeepsNeedsUpload() throws {
        let (store, container) = try makeStore()
        _ = container
        store.upsertSession(date: day, duration: 600,
                            breakdown: [.grammar: 300, .immersion: 200, .anki: 100])

        // Send: capture what goes out, as `SyncClient.flush` does.
        let pending = store.sessionsNeedingUpload()
        #expect(pending.count == 1)
        let sent = pending.map { (session: $0, sentAt: $0.updatedAt) }

        // The user edits the day while the upload is in flight.
        Thread.sleep(forTimeInterval: 0.01)
        store.upsertSession(date: day, duration: 1_200,
                            breakdown: [.grammar: 600, .immersion: 400, .anki: 200])

        // The upload of the older value succeeds.
        store.markUploaded(sent)

        let session = try #require(store.session(for: day))
        #expect(session.needsUpload == true)
        #expect(session.duration == 1_200)
        #expect(session.duration(for: .grammar) == 600)
        #expect(store.sessionsNeedingUpload().count == 1)
    }

    @Test func unchangedRowIsSettled() throws {
        let (store, container) = try makeStore()
        _ = container
        store.upsertSession(date: day, duration: 600,
                            breakdown: [.grammar: 600, .immersion: 0, .anki: 0])

        let sent = store.sessionsNeedingUpload().map { (session: $0, sentAt: $0.updatedAt) }
        store.markUploaded(sent)

        let session = try #require(store.session(for: day))
        #expect(session.needsUpload == false)
        #expect(store.sessionsNeedingUpload().isEmpty)
    }
}
