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
                .environment(services.sync)
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
            services.sync.resume()
        case .background:
            services.timer.onBackground()
            services.sync.suspend()
        case .inactive:
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
                .environment(services.sync)
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

/// Builds the model container and wires the timer, the store and the sync
/// client together once, before the first scene appears (ADR 0003).
@MainActor
final class AppServices {
    let container: ModelContainer
    let timer: TimerManager
    let store: StudyStore
    let sync: SyncClient

    init() {
        let schema = Schema([StudySession.self])
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Could not open the local store: \(error)")
        }
        timer = TimerManager()
        store = StudyStore()
        sync = SyncClient(suite: UserDefaults(suiteName: appGroupSuite) ?? .standard)
        store.modelContext = container.mainContext
        store.timer = timer
        store.sync = sync
        sync.timer = timer
        sync.store = store

        timer.persistSession = { [weak store] date, duration, breakdown in
            store?.upsertSession(date: date, duration: duration, breakdown: breakdown)
        }
        timer.onStateChanged = { [weak sync] _ in
            sync?.clockChanged()
        }
        store.dedupeSessions()
        sync.start()
    }
}
