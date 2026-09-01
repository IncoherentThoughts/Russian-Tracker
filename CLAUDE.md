# Russian Study Timer — Project Intelligence File

> This file is the authoritative reference for all AI-assisted development on this project.
> Read it in full before writing any code, generating any UI, or making architectural decisions.

---

## Project Overview

**App Name:** Russian Timer
**Platforms:** iOS (primary) + macOS (Catalyst or native SwiftUI)
**Purpose:** A minimal, distraction-free timer for tracking daily and cumulative Russian study time.
**Target User:** Law school applicants self-studying for the Russian who want a frictionless way to track study hours.

---

## External Skills & References

Before generating any Swift/SwiftUI code or UI design, read and apply the following skill sets:

- **iOS Swift Development:** https://skills.sh/aj-geddes/useful-ai-prompts/ios-swift-development
- **Mobile iOS Design:** https://skills.sh/wshobson/agents/mobile-ios-design

Also consult:
- `Examples/` folder — all image files in this folder represent the target UI aesthetic. Match the visual language precisely.

---

## Architecture & Tech Stack

- **Language:** Swift (latest stable)
- **UI Framework:** SwiftUI (100% — no UIKit unless absolutely required for system APIs)
- **Persistence:** SwiftData (preferred) or UserDefaults for simple key-value; Core Data as fallback
- **Live Activity:** ActivityKit (iOS Live Activity on Lock Screen + Dynamic Island)
- **Minimum Deployment Target:** iOS 17+, macOS 14+
- **Package Manager:** Swift Package Manager only

### File Structure (expected)
```
RussianTimer/
├── App/
│   ├── RussianTimerApp.swift
│   └── AppDelegate.swift (if needed)
├── Models/
│   ├── StudySession.swift       # Single session model
│   ├── StudyStore.swift         # Persistence + business logic
│   ├── TimerManager.swift       # Observable timer state + Live Activity management
│   └── RussianTimerAttributes.swift # ActivityKit ActivityAttributes (shared with extension target)
├── Views/
│   ├── MainTabView.swift        # Root tab container
│   ├── Timer/
│   │   ├── TimerView.swift      # Landing page
│   │   └── TimerDisplay.swift   # Animated timer component
│   ├── Stats/
│   │   ├── StatsView.swift
│   │   └── Charts/
│   │       ├── DailyBarChart.swift
│   │       ├── WeeklyLineChart.swift
│   │       ├── MonthlyHeatmap.swift
│   │       └── TotalRingChart.swift
│   └── Settings/
│       ├── SettingsView.swift
│       └── ManualEditView.swift
├── LiveActivity/                # Widget extension target (repurposed for Live Activity)
│   ├── RussianTimerWidget.swift    # ActivityConfiguration + DynamicIsland + ToggleTimerIntent
│   └── WidgetBundle.swift       # @main RussianWidgetBundle (widget extension target only)
├── Resources/
│   └── Assets.xcassets
└── Examples/                    # Reference images — do not ship in app bundle
```

---

## Core Features

### 1. Timer (Landing Page)
- **Daily Timer** — large, centered, prominent. Tracks study time for the current day only.
  - Resets at **4:00 AM in the user's local timezone** (use device time zone settings).
  - Cannot be reset from this screen — only from Settings.
  - Persists across app kills/restarts (store start timestamps, not elapsed seconds).
- **Total Timer** — displayed below the daily timer in smaller, muted font.
  - Shows cumulative all-time study time.
  - Never resets automatically — only via Settings with confirmation.
- **Controls:**
  - Single large **Start** button when paused → transitions to **Pause** button when running.
  - No reset button on this screen whatsoever.
- **Animations:**
  - Smooth fade/scale on start/pause state transitions.
  - Timer digits use a monospaced font to prevent layout jitter.
  - Subtle pulse animation on the timer ring or background when actively running.

### 2. Statistics Page (Right Panel)
Charts and insights the user should see (implement all of these):

| Chart | Description |
|---|---|
| **Daily Bar Chart** | Last 7 days of study time as vertical bars. Highlight today. |
| **Weekly Line Chart** | Rolling 8-week view of total hours per week. |
| **Monthly Heatmap** | GitHub-style grid — each day of the current month colored by intensity of study time. |
| **All-Time Ring / Donut** | Total hours broken into buckets (e.g., 0–50h, 50–100h, 100–200h+) or by month. |
| **Streak Counter** | Number of consecutive days with at least 1 minute of study time. Show current streak prominently at top of stats page. |
| **Daily Average** | Average daily study time over the last 30 days, displayed as a stat card. |
| **Best Day** | Highlight the single best study day ever with date and duration. |

Use Swift Charts (native) for all chart components.

### 3. Settings Page (Left Panel)
- **Daily Goal** — stepper (1–10 hours, default 4h) that sets the Live Activity progress bar target. Stored in shared UserDefaults key `"dailyGoal"`.
- **Reset Daily Timer** — resets today's timer to 0:00:00. Confirm once with an action sheet or alert.
- **Reset Total Timer** — resets all-time total to zero. Confirm **twice** (two sequential confirmation dialogs) before executing.
- **Advanced Options** (collapsible section):
  - **Manual Day Edit** — user selects a date from a date picker, then inputs a custom study duration for that day (hours + minutes). This overwrites whatever was recorded for that date. Useful if they forgot to start the timer or left it running overnight.
  - Input validation: duration must be between 0 and 23h 59m.
  - Warn user if they are editing a future date.
- **App Version** — shown at bottom of settings, non-interactive.

### 4. iOS Live Activity
- Appears automatically on the Lock Screen and Dynamic Island when the timer starts.
- Started by the main app via `ActivityKit`; does **not** require user setup like a widget.
- Shows:
  - Today's elapsed study time (live-counting large text via `Text(_:style: .timer)`)
  - A sleek horizontal progress bar (progress toward the daily goal from Settings)
  - **Play / Pause** button that controls the main app timer from the lock screen
- Uses `AppIntent` (`ToggleTimerIntent`) for interactive controls (iOS 17+)
- Shares state with main app via **App Groups** + shared `UserDefaults` suite
- Dynamic Island support: compact, expanded, and minimal presentations
- Live Activity ends automatically when the daily timer is reset; starts again when the timer starts

---

## Navigation Structure

```
MainTabView (TabView with .tabViewStyle(.page) or custom bottom nav)
├── [Left]   Settings
├── [Center] Timer (default tab on launch)
└── [Right]  Statistics
```

Bottom navigation bar with three icons — see `Examples/` for icon placement and style. Use SF Symbols. No tab labels, just icons (minimalist).

---

## UI & Design System

### Color Palette
All colors must be defined as `Color` extensions in a `Theme.swift` file and referenced by name everywhere. Never use hardcoded hex values in view code.

```swift
extension Color {
    static let toffeeBrown   = Color(hex: "#9E6240")  // primary text, icons
    static let lightBronze   = Color(hex: "#DEA47E")  // secondary — muted labels, inactive elements
    static let rosyCopper    = Color(hex: "#CD4631")  // active states, progress bars, accents
    static let eggshell      = Color(hex: "#F8F2DC")  // app background
    static let skyReflection = Color(hex: "#81ADC8")  // achievement callouts, streaks, highlights
}
```

**Usage guidelines:**
- Background: `eggshell`
- Primary text / icons: `toffeeBrown`
- Running timer accent / progress / buttons: `rosyCopper`
- Secondary/muted text: `lightBronze`
- Achievement callouts, streaks, best-day: `skyReflection`
- Card backgrounds: `Color.toffeeBrown.opacity(0.08)` — subtle warm elevation against eggshell
- Nav bar background: `toffeeBrown` — creates contrast between content area and navigation
- Never use hardcoded hex values in view code — always reference palette names
- `Theme.swift` must be in **both** the main app target and the widget extension target

### Typography
- Timer display: SF Pro Rounded, monospaced digits, large weight
- Section headers: SF Pro Display, semibold
- Body / labels: SF Pro Text, regular
- Stat numbers: SF Pro Rounded, bold

### Motion & Animation
- All transitions: `.easeInOut` with duration 0.25–0.35s
- Tab switches: `.slide` or custom matched geometry — smooth, no snapping
- Start/Pause button: subtle scale spring animation on tap (`.spring(response: 0.3, dampingFraction: 0.6)`)
- Timer digits: `.contentTransition(.numericText())` for smooth number rolling
- No excessive animations — restraint is the rule

### Spacing & Layout
- Base unit: 8pt grid
- Corner radii: 16pt for cards, 12pt for buttons
- Safe area awareness: always respect device safe areas
- Card-based layout for stats — soft shadows with low opacity

---

## Timer Logic (Critical Implementation Notes)

```swift
// TimerManager.swift — core behavior contract

// Storage keys (shared UserDefaults suite for Live Activity access)
// "dailyElapsed"         — Double (seconds) for today
// "totalElapsed"         — Double (seconds) all time
// "lastResetDate"        — Date of last 4am reset
// "timerRunning"         — Bool
// "timerStartedAt"       — Date? (when currently running session began)
// "dailyGoal"            — Double (seconds), default 14400 (4 hours)

// On every app foreground:
// 1. Check if a new 4am boundary has passed since lastResetDate
// 2. If yes: add dailyElapsed to totalElapsed, reset dailyElapsed to 0, update lastResetDate
// 3. If timerRunning == true and timerStartedAt is set:
//    add (now - timerStartedAt) to displayed time (do NOT persist yet — persist on pause or background)

// On pause / background / app kill:
// Persist current elapsed to shared UserDefaults immediately
// Update timerStartedAt = nil, timerRunning = false (or keep running flag + timestamp for background)

// Background running:
// Timer continues even when app is backgrounded — track by start timestamp, compute on return
// Do NOT use a live Timer in background — just store the start time and calculate difference on return
```

---

## Live Activity Implementation Notes

- App Group identifier: `group.evan.russiantimer`
- Live Activity reads/writes shared `UserDefaults(suiteName: "group.evan.russiantimer")`
- `RussianTimerAttributes: ActivityAttributes` struct in `RussianTimerAttributes.swift` — must be in **both** the main app target and the widget extension target (use Xcode Target Membership)
- `ToggleTimerIntent: AppIntent` lives in the widget extension target (`RussianTimerWidget.swift`)
- Main app starts Live Activity via `Activity<RussianTimerAttributes>.request(...)` on timer start
- Main app updates state via `activity.update(...)` on pause/resume/foreground
- Main app ends Live Activity via `activity.end(...)` on daily reset
- Progress bar = `dailyElapsed / dailyGoal` (clamped to 1.0)
- Default daily goal: 4 hours (14400 seconds), configurable via Settings stepper
- `NSSupportsLiveActivities` must be `YES` in the main app's `Info.plist`
- Live Activities **cannot be tested in Simulator** — require a physical device
- Dynamic Island support: compact (leading book icon + trailing timer), expanded (full view + progress bar + play/pause), minimal (book icon)

---

## macOS Considerations

- Use SwiftUI `#if os(macOS)` conditionals for platform-specific layout adjustments
- macOS version: single window, minimum size 400×600pt
- No Live Activity on macOS (not applicable) — use `#if os(iOS)` guards around all ActivityKit code
- Menu bar item optional stretch goal: show running/paused status + elapsed time in menu bar

---

## Data Model

```swift
// StudySession.swift
@Model
class StudySession {
    var date: Date          // normalized to start of day (midnight)
    var duration: TimeInterval  // total seconds for that day
    var isManualEdit: Bool  // true if user manually edited this entry
}
```

- One `StudySession` per calendar day
- Manual edits overwrite the day's entry and flag `isManualEdit = true`
- Query by date range for all chart data

---

## What NOT to Do

- Do not add a reset button to the main timer screen
- Do not use UIKit unless required for a specific system API
- Do not use third-party charting libraries — Swift Charts only
- Do not use pure white (`#FFFFFF`) as a flat background — use `eggshell` instead
- Do not use hardcoded hex values in view code — always reference `Theme.swift` palette names
- Do not add unnecessary onboarding screens, splash screens, or tooltips
- Do not make animations feel "app-store demo" flashy — subtle and purposeful only
- Do not store absolute file paths — use relative references
- Do not skip the double-confirmation on total timer reset under any circumstances
- Do not ship the `Examples/` folder in the app bundle
- Do not use WidgetKit `accessoryRectangular` — the correct feature is a Live Activity via ActivityKit

---

## Stretch Goals (Post-MVP)

- [ ] Apple Watch complication (mirrors Live Activity display)
- [ ] iCloud sync via CloudKit so stats persist across devices
- [ ] Daily study goal setting with notification reminder
- [ ] Export study data as CSV
- [ ] macOS menu bar mini-timer
- [ ] Siri Shortcut: "Start my Russian timer"

---

## Development Checklist

- [ ] `Theme.swift` with all colors defined before any view work — added to **both** targets
- [ ] `TimerManager.swift` with full background-safe timer logic
- [ ] `RussianTimerAttributes.swift` added to both app and widget extension targets in Xcode
- [ ] `NSSupportsLiveActivities` = YES in main app Info.plist
- [ ] App Group `group.evan.russiantimer` configured in both targets (Signing & Capabilities)
- [ ] 4am reset logic tested across midnight boundary
- [ ] Live Activity appears on lock screen when timer starts (physical device required)
- [ ] Dynamic Island shows compact and expanded views correctly (iPhone 14 Pro+)
- [ ] Play/Pause from lock screen (ToggleTimerIntent) correctly toggles timer
- [ ] Double-confirmation flow for total reset tested
- [ ] Manual edit validation (future date warning, 0–23:59 range)
- [ ] Daily goal stepper in Settings updates Live Activity progress bar
- [ ] All animations reviewed on real hardware for smoothness
- [ ] Dark mode: verify color palette still works (adjust if needed)
- [ ] Accessibility: VoiceOver labels on timer and buttons

---

*Last updated: 2026-03-01 — replaced WidgetKit lock screen widget with ActivityKit Live Activity.*

---

## Design Context

### Users
Law school applicants self-studying for the Russian — typically alone, often at a desk or library, in long focused sessions. The app is opened briefly to start or pause the timer, then set aside. The primary job-to-be-done is accurate passive tracking, not active engagement. Users return to the stats screen occasionally to feel a sense of progress over weeks of preparation.

### Brand Personality
**Three words: Minimal · Warm · Trustworthy**

The app should feel like a trusted, quiet companion — not a coach, not a game, not a dashboard. It does one job with total reliability and gets out of the way. The warm palette (eggshell, toffee brown, rosy copper) signals a human, academic quality rather than a cold productivity tool.

### Emotional Goals
The app should feel **invisible and frictionless** when in use. A user mid-session should barely register they opened it — tap, timer running, phone down. Nothing should demand attention or interrupt focus. Satisfaction comes from the numbers being there when you look, not from the app asking you to look.

### Aesthetic Direction
- **Light only** — always the warm eggshell background. Never adapts to system dark mode.
- Reference aesthetic (the Flow app in `Examples/`) shows a clean dark timer UI — this app takes the same structural minimalism but applies a warm, parchment-toned palette instead of cold black.
- Anti-reference: **Duolingo / gamified apps** — no streaks used as pressure, no badges, no reward animations, no level-ups. The streak stat exists as neutral data, not motivation infrastructure.
- No corporate SaaS feel (Toggl, Notion) — this is personal and quiet, not a productivity dashboard.

### Design Principles

1. **Silence is the feature.** When the timer is running, the interface should have nothing competing for attention. Animations are subtle and purposeful; nothing pulses, glows, or demands a glance.

2. **Warmth, never urgency.** Color, copy, and layout should never make a user feel behind, pressured, or guilty. Empty states are neutral. Progress bars fill quietly. No red warnings for low study time.

3. **Data as reflection, not motivation.** The Stats screen is a rearview mirror — it lets users see where they've been. Charts should feel calm and informative, not goal-pressure widgets.

4. **Trust through consistency.** The app never loses data, never resets unexpectedly, never surprises the user. Destructive actions require deliberate confirmation. This reliability is the core value proposition.

5. **One job per screen.** The Timer screen does one thing: track. Settings does one thing: configure. Stats does one thing: reflect. Nothing bleeds across. No upsells, tips, or cross-screen nudges.

*Last updated: 2026-03-14 — design context added via /teach-impeccable.*
