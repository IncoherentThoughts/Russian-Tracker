#if os(macOS)
import AppKit
import KeyboardShortcuts

// MARK: - Shortcut names

extension KeyboardShortcuts.Name {
    /// Start or pause the Clock. Default ⌥0.
    static let toggleClock  = Self("toggleClock",  default: .init(.zero,  modifiers: [.option]))
    /// Switch the Study Type. Defaults ⌥1 / ⌥2 / ⌥3.
    static let setGrammar   = Self("setGrammar",   default: .init(.one,   modifiers: [.option]))
    static let setImmersion = Self("setImmersion", default: .init(.two,   modifiers: [.option]))
    static let setAnki    = Self("setAnki",    default: .init(.three, modifiers: [.option]))
}

// MARK: - Global hotkeys

/// System-wide keyboard shortcuts for the Clock (Phase 4).
///
/// The shortcuts are recordable from Settings → Keyboard Shortcuts and are
/// stored by the `KeyboardShortcuts` package in `UserDefaults`. Feedback is
/// the Menu Bar Item only: no sound, HUD, or notification, per the plan.
///
/// The App installs the handlers once at launch:
///
///     Hotkeys.install(timer: timer)
enum Hotkeys {
    /// Registers the key handlers against `timer`. Call once, after the
    /// `TimerManager` exists; calling again replaces the previous handlers.
    static func install(timer: TimerManager) {
        // Fire on key-up so a held ⌥0 does not toggle repeatedly; the
        // Study Type switches are idempotent, so key-down is fine there and
        // feels more immediate.
        KeyboardShortcuts.onKeyUp(for: .toggleClock) { [weak timer] in
            timer?.toggle()
        }
        KeyboardShortcuts.onKeyDown(for: .setGrammar) { [weak timer] in
            timer?.setMode(.grammar)
        }
        KeyboardShortcuts.onKeyDown(for: .setImmersion) { [weak timer] in
            timer?.setMode(.immersion)
        }
        KeyboardShortcuts.onKeyDown(for: .setAnki) { [weak timer] in
            timer?.setMode(.anki)
        }
    }
}
#endif
