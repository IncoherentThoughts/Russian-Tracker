#if os(macOS)
import AppKit
import SwiftUI

/// The Mac app is a menu bar agent (`LSUIElement`): it has no Dock icon and
/// no app menu until the main window is opened. This delegate flips the
/// activation policy to `.regular` while that window is open — so the window
/// gets a Dock tile, an app menu and ⌘Q — and back to `.accessory` when it
/// closes, so closing the window returns the app to the menu bar instead of
/// quitting it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The scene id of the single main window (see `Russian_TrackerApp`).
    static let mainWindowID = "main"

    private var closeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Safety net for the red close button: the SwiftUI content's
        // `onDisappear` also calls `mainWindowDidClose`, but the notification
        // arrives even if the view is torn down some other way.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  Self.isMainWindow(window) else { return }
            Task { @MainActor in self?.mainWindowDidClose() }
        }

        // Global hotkeys are installed in `Russian_TrackerApp.init` (see `Hotkeys`).
    }

    /// Closing the last window must never quit a menu bar agent.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopening from the Dock (only possible while the window is open) just
    /// brings the window forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    // MARK: - Main window lifecycle

    /// Called when the main window's content appears. Gives the app a Dock
    /// icon and brings it to the front so the window is actually visible
    /// (an accessory app's windows open behind the current app otherwise).
    func mainWindowDidOpen() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// Called when the main window closes. Back to a plain menu bar item.
    func mainWindowDidClose() {
        // The window may still be in `NSApp.windows` during `willClose`, so
        // check on the next turn of the run loop.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mainWindow == nil else { return }
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Bring an already-open main window to the front. Opening a closed one
    /// is done by SwiftUI (`openWindow`) — see `MenuBarPopoverView`.
    func showMainWindow() {
        guard mainWindow != nil else { return }
        mainWindowDidOpen()
    }

    /// The main window if it is currently open. SwiftUI stamps the scene id
    /// onto the window's identifier (`main`, or `main-AppWindow-1`).
    var mainWindow: NSWindow? {
        NSApp.windows.first { Self.isMainWindow($0) && $0.isVisible }
    }

    nonisolated static func isMainWindow(_ window: NSWindow) -> Bool {
        guard let id = window.identifier?.rawValue else { return false }
        return id == mainWindowID || id.hasPrefix(mainWindowID + "-")
    }
}
#endif
