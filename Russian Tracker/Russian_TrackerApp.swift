//
//  Russian_TrackerApp.swift
//  Russian Tracker
//
//  Created by Evan Williams on 2/27/26.
//

import SwiftUI
import SwiftData

@main
struct Russian_TrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var timerManager = TimerManager()
    @State private var studyStore = StudyStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(timerManager)
                .environment(studyStore)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: StudySession.self) { result in
            if case .success(let container) = result {
                studyStore.modelContext = container.mainContext
                studyStore.recalibrateTotalIfNeeded(timer: timerManager)
                timerManager.persistSession = { [weak studyStore] date, duration, breakdown in
                    studyStore?.upsertSession(date: date, duration: duration, breakdown: breakdown)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                timerManager.onForeground()
            case .background, .inactive:
                timerManager.onBackground()
            @unknown default:
                break
            }
        }
    }
}
