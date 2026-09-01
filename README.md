# Russian Timer

A minimal, distraction-free iOS app for tracking daily and cumulative Russian study time, split across three study types — grammar, immersion, and output. Built for self-directed language learners who want a frictionless way to log hours without any gamification or pressure.

---

## Features

### Timer
- **Daily timer** — large, centered display tracking today's study time. Resets automatically at 4:00 AM in the device's local timezone.
- **All-time total** — cumulative hours across all study sessions, displayed below the daily timer.
- Single tap to start/pause. No reset button on the main screen.
- Timer persists across app kills and background — tracked by start timestamp, not a live counter.
- Timer continues running while backgrounded; elapsed time is computed on return to foreground.

### Statistics
- **Last 7 Days** bar chart — today highlighted in accent color
- **Last 8 Weeks** area/line chart — rolling weekly totals
- **Monthly Heatmap** — GitHub-style grid colored by study intensity
- **All-Time Ring** — donut chart bucketing total hours (0–50h, 50–100h, 100–200h, 200h+)
- **Streak counter** — consecutive days with at least 1 minute of study
- **Daily average** — average per calendar day over the last 30 days
- **Best Day** — highest single-day session ever recorded

### Settings
- **Daily Goal** stepper (1–10 hours) — controls the Live Activity progress bar target
- **Reset Daily Timer** — single confirmation
- **Reset Total Timer** — double confirmation (cannot be undone)
- **Manual Day Edit** — pick any past date and set a custom duration (useful if you forgot to start the timer or left it running overnight)
- **Export Stats** — saves all sessions and timer state to a dated JSON file, shared via the system share sheet (Files, AirDrop, etc.)
- **Import Stats** — restores a previous export, with a preview of what's being restored before overwriting

### iOS Live Activity
- Appears on the Lock Screen and Dynamic Island automatically when the timer starts
- Shows live-counting elapsed time and a progress bar toward the daily goal
- Play/Pause button controls the timer directly from the Lock Screen (no app open required)
- Dynamic Island: compact, expanded (long-press), and minimal presentations

---

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift (latest stable) |
| UI | SwiftUI (100%) |
| Persistence | SwiftData (session history) + shared UserDefaults (timer state) |
| Charts | Swift Charts (native, no third-party libraries) |
| Live Activity | ActivityKit + AppIntents (`ToggleTimerIntent`) |
| Minimum target | iOS 17+ |

---

## Project Structure

```
Russian Tracker/
├── Russian_TrackerApp.swift          # App entry point, scene lifecycle hooks
├── Theme.swift                    # All color tokens (also in widget target)
├── Models/
│   ├── StudySession.swift         # @Model — one record per calendar day
│   ├── StudyStore.swift           # Business logic: stats, charts, backup/restore
│   ├── TimerManager.swift         # @Observable timer state + Live Activity management
│   └── RussianTimerAttributes.swift  # ActivityKit attributes (shared with widget target)
└── Views/
    ├── MainTabView.swift           # Root container + custom bottom nav bar
    ├── Timer/
    │   ├── TimerView.swift         # Landing screen
    │   └── TimerDisplay.swift      # Reusable HH:MM:SS display component
    ├── Stats/
    │   ├── StatsView.swift
    │   └── Charts/
    │       ├── DailyBarChart.swift
    │       ├── WeeklyLineChart.swift
    │       ├── MonthlyHeatmap.swift
    │       └── TotalRingChart.swift
    └── Settings/
        ├── SettingsView.swift
        └── ManualEditView.swift

Russian Timer Widget/
├── RussianTimerWidget.swift          # ActivityConfiguration + DynamicIsland + ToggleTimerIntent
└── WidgetBundle.swift
```

---

## Setup

1. Clone the repo and open `Russian Tracker.xcodeproj` in Xcode.
2. Set your development team in **Signing & Capabilities** for both the `Russian Tracker` and `Russian Timer Widget` targets.
3. Verify the App Group `group.evan.russiantimer` is configured in **Signing & Capabilities** for both targets.
4. Build and run on a physical device (iOS 17+). The Live Activity cannot be tested in Simulator.

> `NSSupportsLiveActivities` is already set to `YES` in the main app's `Info.plist`.

---

## Key Implementation Notes

**Timer persistence** — The timer stores a start timestamp (`timerStartedAt`) rather than elapsed seconds. On every app foreground, `computedDaily = dailyElapsed + (now − timerStartedAt)`. This means the timer is accurate even after hours in the background.

**4 AM reset** — On each foreground, `TimerManager` checks whether a 4 AM boundary has passed since the last reset. If it has, the current day's elapsed time is rolled into the all-time total, `dailyElapsed` is reset to 0, and (if the timer was running across the boundary) `timerStartedAt` is re-anchored to 4 AM so the new day starts clean.

**Shared state (app ↔ widget)** — Both targets read/write the same `UserDefaults(suiteName: "group.evan.russiantimer")` suite. The `appGroupSuite` constant is defined in `RussianTimerAttributes.swift`, which is included in both Xcode targets.

**Live Activity toggle** — `ToggleTimerIntent` runs entirely in the widget extension process. It reads and writes directly to the shared UserDefaults suite and pushes an updated `ActivityContent` to the Live Activity, so the lock screen reflects the new state immediately without opening the app.

**Backup format** — Exports are plain JSON files containing all `StudySession` records plus `dailyElapsed`, `totalElapsed`, and `lastResetDate`. Importing restores all sessions to SwiftData and writes the timer values back to UserDefaults, then calls `onForeground()` to rehydrate in-memory state (including re-running the 4 AM boundary check for cross-day restores).

---

## Color Palette

| Token | Hex | Usage |
|---|---|---|
| `eggshell` | `#F8F2DC` | App background |
| `toffeeBrown` | `#9E6240` | Primary text, icons, nav bar |
| `lightBronze` | `#DEA47E` | Secondary/muted labels, inactive elements |
| `rosyCopper` | `#CD4631` | Active states, progress bars, accent buttons |
| `skyReflection` | `#81ADC8` | Streak, best-day, achievement callouts |

All colors are defined in `Theme.swift` and referenced by name. No hardcoded hex values in view code.

---

## Stretch Goals

- [ ] Apple Watch complication mirroring the Live Activity
- [ ] iCloud sync via CloudKit
- [ ] Daily reminder notification
- [ ] Export study data as CSV
- [ ] macOS menu bar mini-timer
- [ ] Siri Shortcut: "Start my Russian timer"
