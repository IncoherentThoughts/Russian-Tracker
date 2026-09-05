# Plan: Mac app, cross-device Clock sync, menu bar, widget, hotkeys

Date: 2026-09-05. Vocabulary: see `CONTEXT.md`. Decisions: `docs/adr/0001`, `docs/adr/0002`.

## Decisions in force

| Area | Decision |
|---|---|
| Clock | One shared Clock per Apple ID. Later Clock Action wins. |
| Transport | Supabase (Postgres + Realtime + Auth), see ADR 0003. CloudKit dropped: personal team, no iCloud. |
| Totals | Derived from Sessions plus today. No stored counters. |
| Rollover | Idempotent; first device to see a stale Study Day performs it. |
| Offline | Silent. One muted sync line in Settings. |
| Resets | Global; second confirmation says so. |
| Mac shape | Menu bar agent. Dock icon only while the window is open. Close = back to menu bar. Quit in popover and ⌘Q. |
| Menu Bar Item | Icon; ticking elapsed time only while running. |
| Popover | Today, all-time, Start/Pause, Study Type switcher, Daily Goal bar, Open, Quit. |
| Window | Same three screens and capsule tab bar, fixed ~420×780, ⌘1/⌘2/⌘3 tabs. |
| Login item | None. |
| Widget | Notification Center, small + medium, interactive. Stale hint only when app not running. |
| Control Center | Start/Pause control. |
| Hotkeys | Global, recordable. ⌥0 toggle, ⌥1/2/3 Study Types. Menu bar is the only feedback. |
| App Shortcuts | Start, Pause, Toggle, Set Study Type. |
| Targets | iOS 17.6, macOS 15. Personal builds, App Store compliant. |

## Known limits (accepted)

- Mac-started Clock does not summon the iPhone Live Activity until the phone app opens.
- A quit Mac app leaves the widget stale until relaunch.
- iCloud needs the paid developer program. The project team (3LYN963K9A) is a personal team, so `RT_CLOUDKIT = NO` selects local-only entitlements until enrolment; flip it to YES afterwards.

## Current state of the code (facts)

- Main target already builds for native macOS except `MainTabView.swift:31` (`.page` tab style is iOS-only).
- Widget extension is iOS-only and holds only the Live Activity. No timeline widget exists.
- Clock state = 13 keys in `UserDefaults(suiteName: "group.evan.russiantimer")`. History = local SwiftData, no CloudKit.
- Intents write the suite then post a Darwin notification; `TimerManager.reconcileFromSharedState()` adopts it. This stays the in-device protocol.

---

## Phase 0 — Project setup ✅ done 2026-09-05

1. Fix the macOS compile error: wrap `.tabViewStyle(.page(...))` in `#if os(iOS)`; on macOS use a plain `TabView` with hidden tab bar or a `ZStack` switched by `selectedTab` with a slide transition.
2. Set `MACOSX_DEPLOYMENT_TARGET = 15.0` on the app target. Remove `xros` from `SUPPORTED_PLATFORMS` (unused).
3. Add iCloud capability + CloudKit container `iCloud.com.evan.russiantracker` to `Russian Tracker.entitlements`. Add Background Modes → Remote notifications on iOS so CloudKit pushes wake the app.
4. App Group on macOS: sandboxed Mac apps historically require a team-prefixed group id. Xcode 16+ accepts `group.*` for macOS with a provisioning profile. Build once on macOS with signing on; if the entitlement is rejected, add `3LYN963K9A.group.evan.russiantimer` as a second group for the Mac targets and key the suite name by platform in `RussianTimerAttributes.swift`.
5. Add SPM dependency `https://github.com/sindresorhus/KeyboardShortcuts` to the app target (macOS only; wrap imports in `#if os(macOS)`).

Exit: `xcodebuild -destination 'platform=macOS'` succeeds and the existing iOS build is unchanged.

Notes from doing it: the widget extension embed and target dependency are filtered to iOS (`platformFilters`) until Phase 5. Export on macOS uses `fileExporter`. The test action was added to the shared scheme.

## Phase 1 — Domain refactor (platform-neutral, no sync yet) ✅ done 2026-09-05

Goal: make the model sync-safe before adding sync. All of this ships to iOS too.

1. **`ClockState` SwiftData model** (`Models/ClockState.swift`), one row:
   - `isRunning: Bool`, `runStartedAt: Date?`, `mode: String` (StudyType raw), `studyDay: Date` (start-of-day of the Study Day that `dailyBase*` belongs to), `dailyBase: Double`, `dailyBaseGrammar/Immersion/Output: Double`, `dailyGoal: Double`, `lastActionAt: Date`, `lastActionDevice: String`.
   - Every field has a default (CloudKit requirement). No `@Attribute(.unique)` (CloudKit forbids it).
2. **`StudySession` CloudKit compatibility**: give `date`, `duration`, `isManualEdit` defaults; add `updatedAt: Date` for conflict resolution. Remove any unique constraint.
3. **Derived totals** (ADR 0002): delete `totalElapsed`, `total_<type>` keys and `recalibrateTotalIfNeeded`. `StudyStore` gains `allTimeTotal(sessions:) ` and per-type variants; `TimerManager.computedTotal` = cached past-Sessions sum + `computedDaily`. Cache the sum in the suite under `pastSessionsTotal` / `pastSessionsTotal_<type>` so widgets and the popover can show it without SwiftData.
4. **`TimerManager` around `ClockState`**: the manager owns an in-memory `ClockState` snapshot; `start/pause/setMode/rollover` become Clock Actions that (a) bank elapsed time, (b) stamp `lastActionAt`, (c) write the SwiftData row, (d) mirror the 13-key suite for intents/widgets, (e) call `persistSession`. Keep the public API used by views unchanged.
5. **Idempotent Rollover**: `check4amBoundary` compares `ClockState.studyDay` with the current Study Day. If stale: persist the departing Session, zero daily bases, set `studyDay`, re-anchor `runStartedAt` to 4am if running, stamp `lastActionAt`. Runs on foreground (iOS), on a 4am timer and on wake (Mac), and after every remote change.
6. **Intents** (`ToggleTimerIntent`, `SetStudyModeIntent`): keep writing the suite + Darwin notification (they cannot open the SwiftData container cheaply). Add `lastActionAt` to the suite. The app's `reconcileFromSharedState()` adopts the suite values into `ClockState` and saves, which is what makes an intent's action reach iCloud.
7. **Conflict rule**: `merge(local, remote)` for `ClockState` = the one with the later `lastActionAt`. For Sessions sharing a date, keep the later `updatedAt`, delete the rest, then re-derive today's Session from the winning `ClockState`.
8. **Tests** (`Russian TrackerTests`): rollover idempotency; last-action-wins for the Q10 scenario (pause 10:00 offline vs start 10:02); duplicate Session dedupe; derived total equals sum after reset, manual edit, and mode switch.

Exit: iOS app behaves exactly as before; tests green; no `totalElapsed` key anywhere.

Notes from doing it: the value type is `ClockSnapshot`; intents now run the same code as the app and queue departing days under `pendingSessions`. `TimerManager.adopt(_:notify:)` is the single entry point for both intent and (Phase 2) remote states. 14 unit tests in `Russian TrackerTests/ClockSnapshot*Tests.swift`.

## Phase 2 — CloudKit sync ✅ code done 2026-09-05, device verification pending

1. `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.evan.russiantracker"))` in `Russian_TrackerApp.swift`. Migrate the existing local store on first launch (SwiftData does this automatically when the schema is compatible; verify with the on-device data).
2. Observe `NSPersistentStoreRemoteChange` → run merge (Phase 1.7) → `reconcile` → refresh cached totals → `WidgetCenter.shared.reloadAllTimelines()` → update Live Activity (iOS).
3. First sync: iPhone uploads. Mac's fresh store adopts. No merge policy needed for history (only the iPhone has data).
4. Settings sync line: "iCloud · synced 2 min ago" / "iCloud · not signed in" (read `FileManager.default.ubiquityIdentityToken` and the last remote-change time). Muted `lightBronze`, no icon on the Timer screen.
5. Reset Total second confirmation text: "This deletes every session on all your devices."
6. Backup import: after `applyBackup`, stamp `lastActionAt = now` so the restore wins over stale remote state.

Exit: start on phone → Mac window shows running within seconds; pause on Mac → phone follows; both survive airplane mode per the Q10 scenario.

Notes from doing it: `AppServices` (in `Russian_TrackerApp.swift`) builds the container with the private CloudKit database and falls back to a local store if the entitlement is missing. `StudyStore.startObservingRemoteChanges()` coalesces `NSPersistentStoreRemoteChange` and runs `handleRemoteChange()`, which adopts the synced Clock State (no notify) and de-duplicates Sessions. `upsertSession` skips no-op writes so echoes of our own saves cannot loop. Sync cannot be exercised from an unsigned command-line build; the exit criteria need two signed devices.

## Phase 3 — Mac app shell

1. `Info.plist`: `LSUIElement = YES` for macOS. An `AppDelegate` (NSApplicationDelegateAdaptor) switches `NSApp.setActivationPolicy(.regular)` when the main window opens and `.accessory` when it closes. Closing the window never quits.
2. `MenuBarExtra("Russian Tracker", ...)` with `.menuBarExtraStyle(.window)`:
   - Label: app glyph; when running, append `computedDaily.timerFormatted` driven by the existing 1s tick.
   - Content: `MenuBarPopoverView` reusing `TimerDisplay`, `StudyTypeDots`, and the Live Activity's goal bar (move `GoalProgressBar` into shared code). Buttons: Open Russian Tracker (opens the WindowGroup via `openWindow`), Quit (`NSApp.terminate`).
3. Window: `.defaultSize(420, 780)`, `.windowResizability(.contentSize)`, `MainTabView` with click navigation and `⌘1/⌘2/⌘3` via `.keyboardShortcut` on hidden commands (`CommandGroup`).
4. Rollover scheduling on Mac: `Timer` firing at the next 4am + `NSWorkspace.shared.notificationCenter` `didWakeNotification` → `check4amBoundary()`.
5. Export/Import on Mac: replace `UIActivityViewController` with `.fileExporter` / `.fileImporter` (already `#if os(iOS)` guarded).

Exit: launching shows only a menu bar item; popover starts/pauses; window opens and closes without quitting.

Notes (done 2026-09-05, branch `p3-mac-shell`):
- New `Russian Tracker/Mac/`: `AppDelegate.swift` (activation policy, never quits on close, Phase 4 hotkey hook comment), `MenuBarPopoverView.swift` (also holds `MenuBarLabel`), `MacRolloverScheduler.swift` (4am `Timer` + `didWakeNotification` + window-became-key + clock/time-zone change, all → `TimerManager.onForeground()`), `WindowNavigation.swift` (selected tab shared between the Go menu and `MainTabView`).
- The main window is a `Window` (id `main`), not a `WindowGroup`, so "Open Russian Tracker" reuses it. Content is framed 420×780 with `.windowResizability(.contentSize)`.
- Go menu: ⌘1 Timer, ⌘2 Stats, ⌘3 Settings. ⌘Q also works inside the popover (Quit button carries the shortcut); Space toggles Start/Pause there.
- The popover's goal bar is fed `snapshot.dailyBase` + `runStartedAt` (same anchor as the Live Activity), so it ticks without app updates.
- Item 5 (fileExporter/fileImporter) was not part of this pass; the iOS share sheet is still `#if os(iOS)`-guarded.

## Phase 4 — Hotkeys and App Shortcuts

1. `KeyboardShortcuts.Name` for `toggleClock` (⌥0), `setGrammar` (⌥1), `setImmersion` (⌥2), `setOutput` (⌥3). Register handlers in the AppDelegate calling `TimerManager`.
2. Recorder UI: a "Keyboard Shortcuts" section in `SettingsView` under `#if os(macOS)` using `KeyboardShortcuts.Recorder`.
3. Make the intents cross-platform: move ActivityKit-specific code inside `#if os(iOS)` and add `StartTimerIntent`, `PauseTimerIntent` alongside `ToggleTimerIntent`. Add `RussianShortcuts: AppShortcutsProvider` with phrases ("Start my Russian timer", "Pause my Russian timer", "Switch Russian timer to Grammar").
4. Feedback: none beyond the Menu Bar Item changing.

Exit: ⌥0 in Safari toggles; the Menu Bar Item ticks; Shortcuts app lists the four actions.

Status (2026-09-05, branch `p4-hotkeys`): implemented.
- `Mac/Hotkeys.swift`: the four `KeyboardShortcuts.Name`s with ⌥0–⌥3 defaults and `Hotkeys.install(timer:)`. The App must call `Hotkeys.install(timer: timer)` once at launch under `#if os(macOS)`; not wired here.
- `Views/Settings/KeyboardShortcutsSection.swift`: the "Keyboard Shortcuts" group (macOS only), inserted after the Timer group in `SettingsView`.
- `Models/AppShortcuts.swift` (app target only): `StartTimerIntent`, `PauseTimerIntent`, `RussianShortcuts: AppShortcutsProvider` (Start, Pause, Toggle, Set Study Type). `presentLiveActivity`/`notifyApp` in `ToggleTimerIntent.swift` were made internal so the new intents share them.

## Phase 5 — Notification Center widget and Control Center ✅ code done 2026-09-05, device verification pending

1. Add `macosx` to the widget extension's `SUPPORTED_PLATFORMS`; guard the Live Activity and `ActivityKit` imports with `#if os(iOS)`. Add the Mac App Group entitlement (see Phase 0.4).
2. New `RussianTimerWidget` (timeline widget) in `Russian Timer Widget/TimerWidget.swift`, families `.systemSmall`, `.systemMedium`, added to `WidgetBundle`. Register it for iOS too (free Home Screen widget) but ship it only when it looks right there.
   - Provider reads the suite (`ClockState` mirror + cached totals). Timeline: one entry, `.policy(.never)`; the app calls `reloadAllTimelines()` on every Clock Action and remote change.
   - Running: `Text(timerInterval:)` anchored at `runStartedAt - dailyBase` ticks natively. Paused: static digits.
   - Small: digits, running dot, `Button(intent: ToggleTimerIntent())`. Medium: the Live Activity layout (header, `WidgetStudyTypeDots`, digits, goal bar, Play/Pause). Move those private views into a shared file.
   - Stale hint: the app writes `appHeartbeat` (Date) to the suite every 60 s while running on Mac; the widget shows "Open Russian Tracker to sync" under the digits when the heartbeat is older than 3 minutes.
3. `ControlWidget`: `ControlWidgetToggle` bound to `ToggleTimerIntent`, symbol `book.fill` / `pause.fill`, title "Russian Timer".

Exit: widget added to Notification Center starts/pauses the Clock and switches type; Control Center tile toggles.

Notes from doing it: the widget extension now builds for `iphoneos iphonesimulator macosx` (`SDKROOT = auto`, own `Russian Timer WidgetExtension.macOS.entitlements` with sandbox + App Group); the ActivityKit link and the whole Live Activity file are iOS-only. `TimerWidget.swift` holds `RussianTimerWidget` (small + medium, one `.never` entry; on macOS a second entry three minutes after the last `appHeartbeat` carries the stale hint). `TimerManager` writes `appHeartbeat` on macOS on every adopt/action and every 60 s while running, and calls `WidgetCenter.reloadAllTimelines()` + `ControlCenter.reloadAllControls()` after every state change on both platforms. `ControlWidget.swift` adds `RussianTimerControl` with its own `SetClockRunningIntent: SetValueIntent` (a `ControlWidgetToggle` needs a `SetValueIntent`, which `ToggleTimerIntent` is not). Control Center controls are iOS 18+ / macOS 26+ in the SDK (not macOS 15), so the bundle gates the control with `if #available(iOS 18.0, macOS 26.0, *)`.

## Phase 6 — Verification and docs (docs ✅ 2026-09-05; device checklist pending)

Scenario checklist, each run on real devices:
- Start on Mac, phone app open → phone shows running within seconds; pause on phone → Mac stops.
- Q10 offline conflict: Mac offline, pause 10:00; phone start 10:02; Mac reconnects → running since 10:02; 9:00–10:00 banked once.
- Rollover with both devices asleep across 4am; wake in either order → one departing Session, no double counting.
- Duplicate Sessions after both offline → one Session remains, matching the timer screen.
- Reset Total on Mac → phone history gone; backup import restores and wins.
- Widget after Quit → stale hint; relaunch → correct within seconds.
- ⌥0/⌥1/⌥2/⌥3 from another app; re-record a shortcut; verify ⌘1/2/3 in the window.
- Menu bar shows time only while running.

Docs: update `CLAUDE.md` (macOS section, storage keys, derived totals) and `README.md` (Mac features, setup for iCloud). Keep `CONTEXT.md` as glossary only.

## Files touched (summary)

- `Russian Tracker.xcodeproj/project.pbxproj` — platforms, entitlements, SPM package, widget target platforms
- `Russian Tracker/Russian Tracker.entitlements`, `Russian Timer WidgetExtension.entitlements` — iCloud, app groups
- `Models/ClockState.swift` (new), `Models/StudySession.swift`, `Models/StudyStore.swift`, `Models/TimerManager.swift`, `Models/RussianTimerAttributes.swift`, `Models/ToggleTimerIntent.swift`, `Models/AppShortcuts.swift` (new), `Models/SyncMerge.swift` (new)
- `Russian_TrackerApp.swift`, `Mac/AppDelegate.swift` (new), `Mac/MenuBarPopoverView.swift` (new), `Mac/Hotkeys.swift` (new)
- `Views/MainTabView.swift`, `Views/Settings/SettingsView.swift`
- `Russian Timer Widget/TimerWidget.swift` (new), `Russian Timer Widget/ControlWidget.swift` (new), `Russian Timer Widget/SharedWidgetViews.swift` (new), `WidgetBundle.swift`
- `Russian TrackerTests/` — new tests for Phase 1
- `docs/adr/0001`, `docs/adr/0002`, `CONTEXT.md`, `CLAUDE.md`, `README.md`

## Order and rough effort

| Phase | Depends on | Effort |
|---|---|---|
| 0 Setup | — | half a day |
| 1 Domain refactor | 0 | 2 days |
| 2 CloudKit sync | 1, paid dev program | 1–2 days |
| 3 Mac shell | 0 | 1 day |
| 4 Hotkeys/Shortcuts | 3 | half a day |
| 5 Widget + Control Center | 3, ideally 1 | 1–2 days |
| 6 Verification/docs | all | 1 day |

Phases 3–5 can proceed in parallel with 1–2 since they only consume `TimerManager`'s existing API.

---

## Phase 7 — Supabase transport (replaces Phase 2's CloudKit) 

Decisions: ADR 0003. Sign-in = email + password, once per device (email confirmation off). First device uploads; later devices merge.

1. Remove CloudKit: `ClockState` model, CloudKit container config, `NSPersistentStoreRemoteChange` observer, iCloud/push entitlements, `RT_CLOUDKIT` switch, `remote-notification` background mode.
2. Add `supabase-swift` (SPM) to the app target. `Models/SupabaseConfig.swift` holds the URL and publishable key.
3. `Models/SyncClient.swift`: auth (sign in or sign up with password, sign out, session listener), `pull()` (clock merge + Session reconcile), `flush()` (dirty clock, `needsUpload` Sessions, pending delete-all) with retry, Realtime subscription on `clock_state` and `sessions`. Pure `SessionSyncPlan.make(...)` decides reconcile actions (tested).
4. `StudySession.needsUpload`; `StudyStore` gains `applyRemoteSession`, `reconcileSessions`, and forwards changes to the client. `syncStatusText` moves to the client.
5. Settings: an Account group (email + password → signed in; status line; Sign out). Global reset copy unchanged.
6. Database migration (pasted into the Supabase SQL editor): tables, RLS policies, Realtime publication, `replica identity full` on `sessions` so deletes carry the date.

Exit: same as Phase 2's — start on phone → Mac follows; pause on Mac → phone follows on foreground; Q10 offline conflict; global reset; backup import wins.
