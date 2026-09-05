#if os(macOS)
import AppKit
import Foundation

/// Keeps the Clock's Study Day current on the Mac, where the app may sit in
/// the menu bar for weeks without ever going through a foreground transition.
///
/// Three triggers, all funnelled into `TimerManager.onForeground()`, which
/// reconciles with the shared suite and performs the Rollover if a 4am
/// boundary has passed:
/// - a `Timer` armed for the next 4am boundary (re-armed after each firing);
/// - the machine waking from sleep (a boundary may have passed while asleep,
///   and a sleeping Mac does not fire timers);
/// - any of the app's windows becoming key — the main window or the popover
///   panel — so what the user sees is fresh the moment they look.
///
/// Clock or time-zone changes re-arm the boundary timer, since the wall-clock
/// instant of "next 4am" moved.
final class MacRolloverScheduler {
    private let timer: TimerManager
    private var boundaryTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(timer: TimerManager) {
        self.timer = timer
        scheduleNextBoundary()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fire(reason: "wake") }
        })

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fire(reason: "window") }
        })
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.fire(reason: "clock change") }
            })
        }
    }

    /// Stop the timer and observers. The scheduler normally lives as long as
    /// the process, so this is here for completeness rather than for use.
    func stop() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - Private

    private func fire(reason: String) {
        timer.onForeground()
        // Re-arm in every case: after a wake the pending timer's fire date may
        // be in the past, and after a clock change it is simply wrong.
        scheduleNextBoundary()
    }

    private func scheduleNextBoundary() {
        boundaryTimer?.invalidate()
        let now = Date()
        let currentDay = ClockSnapshot.studyDayStart(for: now)
        var fireAt = ClockSnapshot.boundary(after: currentDay)
        if fireAt <= now {
            // Should not happen (the current Study Day's boundary is always
            // ahead of `now`), but never arm a timer in the past.
            fireAt = ClockSnapshot.boundary(after: ClockSnapshot.studyDayStart(for: fireAt))
        }
        // A second past the boundary so `rollover(now:)` sees the new day.
        let t = Timer(fire: fireAt.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire(reason: "boundary") }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        boundaryTimer = t
    }
}
#endif
