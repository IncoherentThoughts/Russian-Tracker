//
//  Russian_TrackerApp.swift
//  Russian Tracker
//
//  Created by Evan Williams on 2/27/26.
//

import SwiftUI
import SwiftData
#if os(macOS)
import Security
#endif

@main
struct Russian_TrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(services.timer)
                .environment(services.store)
                .preferredColorScheme(.light)
        }
        .modelContainer(services.container)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                services.timer.onForeground()
            case .background, .inactive:
                services.timer.onBackground()
            @unknown default:
                break
            }
        }
    }
}

/// Builds the model container and wires the timer, the store, and sync
/// together once, before the first scene appears.
///
/// The container uses the private CloudKit database (ADR 0001). If that is
/// unavailable — no iCloud entitlement on this build — it falls back to the
/// same local store without sync, so the app keeps working and the sync line
/// in Settings says why.
@MainActor
final class AppServices {
    let container: ModelContainer
    let timer: TimerManager
    let store: StudyStore

    init() {
        let schema = Schema([StudySession.self, ClockState.self])
        // CloudKit traps (it does not throw) when the process lacks the iCloud
        // entitlement, so the choice is made up front rather than by catching.
        var cloudEnabled = Self.hasICloudEntitlement
        var built: ModelContainer?
        if cloudEnabled {
            let cloud = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            do {
                built = try ModelContainer(for: schema, configurations: [cloud])
            } catch {
                print("[Sync] CloudKit container unavailable, using local store: \(error)")
                cloudEnabled = false
            }
        }
        if built == nil {
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                built = try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Could not open the local store: \(error)")
            }
        }
        guard let built else { fatalError("unreachable") }
        container = built
        timer = TimerManager()
        store = StudyStore()
        store.modelContext = container.mainContext
        store.cloudSyncEnabled = cloudEnabled
        store.timer = timer

        timer.persistSession = { [weak store] date, duration, breakdown in
            store?.upsertSession(date: date, duration: duration, breakdown: breakdown)
        }
        timer.onStateChanged = { [weak store] snapshot in
            store?.saveClock(snapshot)
        }
        // The synced record may be newer than the suite (a remote change
        // imported while the app was not running).
        if let synced = store.loadClock() {
            timer.adopt(synced, notify: true)
        } else {
            store.saveClock(timer.snapshot)
        }
        store.dedupeSessions()
        store.startObservingRemoteChanges()
    }

    /// Whether this process was signed with the iCloud entitlement. Unsigned
    /// command-line builds and test hosts are not; Xcode-run builds are.
    static var hasICloudEntitlement: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task, "com.apple.developer.icloud-services" as CFString, nil
        )
        return value != nil
        #else
        // iOS builds are always signed by Xcode, entitlements included.
        return true
        #endif
    }
}
