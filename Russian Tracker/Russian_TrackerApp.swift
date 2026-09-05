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
    @State private var services: AppServices

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var navigation = WindowNavigation()
    /// Held for the life of the process; it re-arms itself after each firing.
    @State private var rollover: MacRolloverScheduler
    #endif

    init() {
        let services = AppServices()
        _services = State(initialValue: services)
        #if os(macOS)
        _rollover = State(initialValue: MacRolloverScheduler(timer: services.timer))
        Hotkeys.install(timer: services.timer)
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        macScenes
        #else
        WindowGroup {
            MainTabView()
                .environment(services.timer)
                .environment(services.store)
                .preferredColorScheme(.light)
        }
        .modelContainer(services.container)
        .onChange(of: scenePhase) { _, newPhase in
            handle(newPhase)
        }
        #endif
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            services.timer.onForeground()
        case .background, .inactive:
            services.timer.onBackground()
        @unknown default:
            break
        }
    }
}

// MARK: - macOS scenes

#if os(macOS)
private extension Russian_TrackerApp {
    /// The Mac app is a menu bar agent: the Menu Bar Item is always there,
    /// and the single main window (same three screens, fixed 420×780) opens
    /// from the popover or the Dock. `Window` rather than `WindowGroup` so
    /// "Open Russian Tracker" reuses the window when it is already open.
    @SceneBuilder
    var macScenes: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(services.timer)
                .environment(services.store)
                .modelContainer(services.container)
        } label: {
            MenuBarLabel()
                .environment(services.timer)
        }
        .menuBarExtraStyle(.window)

        Window("Russian Tracker", id: AppDelegate.mainWindowID) {
            MainTabView()
                .frame(width: 420, height: 780)
                .environment(services.timer)
                .environment(services.store)
                .environment(navigation)
                .preferredColorScheme(.light)
                .onAppear {
                    appDelegate.mainWindowDidOpen()
                    services.timer.onForeground()
                }
                .onDisappear { appDelegate.mainWindowDidClose() }
        }
        .modelContainer(services.container)
        .defaultSize(width: 420, height: 780)
        .windowResizability(.contentSize)
        .onChange(of: scenePhase) { _, newPhase in
            handle(newPhase)
        }
        .commands {
            // ⌘1 Timer, ⌘2 Stats, ⌘3 Settings. The window follows
            // `navigation`; the capsule tab bar writes back into it.
            CommandMenu("Go") {
                ForEach(Array(WindowNavigation.commandOrder.enumerated()), id: \.element) { index, tab in
                    Button {
                        navigation.select(tab)
                    } label: {
                        if navigation.selectedTab == tab {
                            Label(tab.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(tab.menuTitle)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            // A single-window agent has nothing to make new.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
#endif

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

    /// Whether this build carries the iCloud entitlement. Controlled by the
    /// `RT_CLOUDKIT` build setting (YES selects the `.entitlements` files with
    /// iCloud + push and defines `CLOUDKIT_SYNC`; NO selects the `.local`
    /// variants). Personal developer teams cannot sign iCloud, so NO is the
    /// default until the paid program is active. On macOS the signed
    /// entitlement is double-checked because CloudKit traps without it.
    static var hasICloudEntitlement: Bool {
        #if !CLOUDKIT_SYNC
        return false
        #elseif os(macOS)
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
