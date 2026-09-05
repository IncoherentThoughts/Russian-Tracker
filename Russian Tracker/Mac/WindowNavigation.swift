#if os(macOS)
import Observation

/// The main window's selected tab, shared between the menu commands
/// (⌘1/⌘2/⌘3) and `MainTabView`. Injected into the environment by
/// `Russian_TrackerApp`; the tab view follows it and reports clicks on the
/// capsule bar back into it so the menu checkmarks stay right.
@Observable
final class WindowNavigation {
    var selectedTab: Tab = .timer

    /// The order the key commands use: ⌘1 Timer, ⌘2 Stats, ⌘3 Settings.
    static let commandOrder: [Tab] = [.timer, .stats, .settings]

    func select(_ tab: Tab) {
        selectedTab = tab
    }
}

extension Tab {
    /// Menu item title for the Go menu.
    var menuTitle: String {
        switch self {
        case .stats:    return "Stats"
        case .timer:    return "Timer"
        case .settings: return "Settings"
        }
    }
}
#endif
