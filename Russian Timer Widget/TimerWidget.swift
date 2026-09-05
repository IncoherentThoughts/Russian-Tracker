import WidgetKit
import SwiftUI
import AppIntents

// The Notification Center (macOS) / Home Screen (iOS) presentation of the
// Clock. Reads the Clock State from the app-group suite; every Clock Action
// in the app calls `WidgetCenter.reloadAllTimelines()`, so the timeline is a
// single entry with `.never` policy. A running Clock ticks natively through
// `Text(timerInterval:)`, so no reloads are needed for the digits themselves.

// MARK: - Entry

struct TimerEntry: TimelineEntry {
    let date: Date
    /// Clock State rolled to the Study Day containing `date`. Never written
    /// back; the app owns the real Rollover.
    let snapshot: ClockSnapshot
    /// All-Time Total: cached past Sessions plus today at `date`.
    let allTime: TimeInterval
    /// macOS only: the Mac app has quit, so the widget cannot stay current.
    let showsStaleHint: Bool

    static let placeholder = TimerEntry(
        date: .now,
        snapshot: {
            var s = ClockSnapshot()
            s.isRunning = false
            s.dailyBase = 47 * 60 + 12
            s.dailyByType = [.grammar: 20 * 60, .immersion: 27 * 60 + 12]
            s.mode = .immersion
            return s
        }(),
        allTime: 128 * 3600 + 15 * 60,
        showsStaleHint: false
    )

    static let previewRunning = TimerEntry(
        date: .now,
        snapshot: {
            var s = ClockSnapshot()
            s.isRunning = true
            s.runStartedAt = Date.now.addingTimeInterval(-14 * 60)
            s.dailyBase = 1 * 3600 + 22 * 60 + 5
            s.mode = .grammar
            return s
        }(),
        allTime: 128 * 3600 + 15 * 60,
        showsStaleHint: false
    )

    static let previewStale = TimerEntry(
        date: .now,
        snapshot: previewRunning.snapshot,
        allTime: previewRunning.allTime,
        showsStaleHint: true
    )
}

// MARK: - Provider

struct TimerWidgetProvider: TimelineProvider {
    /// A heartbeat older than this means the Mac app is no longer running.
    static let staleAfter: TimeInterval = 3 * 60

    func placeholder(in context: Context) -> TimerEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(context.isPreview ? .placeholder : Self.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let now = Date()
        var entries = [Self.entry(at: now)]
        #if os(macOS)
        // While the app is alive it refreshes the heartbeat (and reloads us)
        // every minute, so this second entry is only ever shown after the
        // app has quit with the Clock running.
        if let hintAt = Self.staleHintDate(now: now) {
            entries.append(Self.entry(at: hintAt, forceStale: true))
        }
        #endif
        completion(Timeline(entries: entries, policy: .never))
    }

    // MARK: Reading the suite

    static func entry(at date: Date, forceStale: Bool = false) -> TimerEntry {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else {
            return TimerEntry(date: date, snapshot: ClockSnapshot(), allTime: 0, showsStaleHint: false)
        }
        let stored = ClockSnapshot(suite: suite)
        // Today's seconds count toward All-Time whichever Study Day they
        // belong to, so derive the total before rolling the display copy.
        let allTime = suite.double(forKey: TimerKey.pastTotal) + stored.daily(at: date)
        var shown = stored
        _ = shown.rollover(now: date)
        return TimerEntry(
            date: date,
            snapshot: shown,
            allTime: allTime,
            showsStaleHint: forceStale || isStale(shown, heartbeat: heartbeat(in: suite), at: date)
        )
    }

    static func heartbeat(in suite: UserDefaults) -> Date? {
        suite.object(forKey: TimerKey.appHeartbeat) as? Date
    }

    /// The stale hint exists only on macOS: on iOS the Live Activity and the
    /// intents keep the widget honest without the app's help.
    static func isStale(_ snapshot: ClockSnapshot, heartbeat: Date?, at date: Date) -> Bool {
        #if os(macOS)
        guard snapshot.isRunning else { return false }
        guard let heartbeat else { return true }
        return date.timeIntervalSince(heartbeat) > staleAfter
        #else
        return false
        #endif
    }

    /// When the running Clock's heartbeat will become stale, if it is fresh now.
    static func staleHintDate(now: Date) -> Date? {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return nil }
        let snapshot = ClockSnapshot(suite: suite)
        guard snapshot.isRunning, let beat = heartbeat(in: suite) else { return nil }
        let deadline = beat.addingTimeInterval(staleAfter + 1)
        return deadline > now ? deadline : nil
    }
}

// MARK: - Widget

struct RussianTimerWidget: Widget {
    static let kind = "RussianTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TimerWidgetProvider()) { entry in
            TimerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Russian Timer")
        .description("Today's study time. Start, pause and switch Study Type without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TimerWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                MediumTimerView(entry: entry)
            default:
                SmallTimerView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.eggshell, Color.eggshellDeep],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Pieces

/// Today's digits: ticking while running, static while paused.
private struct WidgetClockDigits: View {
    let snapshot: ClockSnapshot
    var size: CGFloat = 40

    var body: some View {
        if snapshot.isRunning, let startedAt = snapshot.runStartedAt {
            Text(
                timerInterval: liveAnchor(elapsed: snapshot.dailyBase, startedAt: startedAt)...Date.distantFuture,
                countsDown: false,
                showsHours: true
            )
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.toffeeInk)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            TimerDigitsView(elapsed: snapshot.dailyBase, size: size)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// Quiet running indicator: a copper dot, present only while the Clock runs.
private struct RunningDot: View {
    let isRunning: Bool

    var body: some View {
        Circle()
            .fill(Color.rosyCopper)
            .frame(width: 6, height: 6)
            .shadow(color: Color.rosyCopper.opacity(0.5), radius: 3, x: 0, y: 0)
            .opacity(isRunning ? 1 : 0)
            .accessibilityLabel(isRunning ? "Running" : "Paused")
    }
}

private struct StaleHint: View {
    var body: some View {
        Text("Open Russian Tracker to sync")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.bronzeMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// "128h 15m" for the All-Time Total.
private func fmtHours(_ t: TimeInterval) -> String {
    let total = Int(max(0, t))
    let h = total / 3600
    let m = (total % 3600) / 60
    return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
}

// MARK: - Small

private struct SmallTimerView: View {
    let entry: TimerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                AppIconView(size: 22)
                Spacer()
                RunningDot(isRunning: entry.snapshot.isRunning)
            }

            Spacer(minLength: 6)

            Text("Today")
                .eyebrowStyle()
            WidgetClockDigits(snapshot: entry.snapshot, size: 28)
                .padding(.top, 1)
            if entry.showsStaleHint {
                StaleHint()
                    .padding(.top, 2)
            }

            Spacer(minLength: 6)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("All-time")
                        .eyebrowStyle()
                    Text(fmtHours(entry.allTime))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.toffeeBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                WidgetPlayPauseButton(isRunning: entry.snapshot.isRunning, size: 36)
            }
        }
    }
}

// MARK: - Medium

private struct MediumTimerView: View {
    let entry: TimerEntry

    private var progress: Double {
        guard entry.snapshot.dailyGoal > 0 else { return 0 }
        return min(1.0, entry.snapshot.daily(at: entry.date) / entry.snapshot.dailyGoal)
    }

    private var goalHours: Int {
        max(1, Int(entry.snapshot.dailyGoal / 3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ────────────────────────────────────────────────
            HStack(spacing: 10) {
                AppIconView(size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Russian Tracker")
                        .eyebrowStyle()
                    Text("\(fmtHours(entry.allTime)) all-time")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.13)
                        .foregroundStyle(Color.toffeeInk)
                        .lineLimit(1)
                }

                Spacer()

                WidgetStudyTypeDots(selected: entry.snapshot.mode)
                    .padding(.trailing, 6)

                WidgetPlayPauseButton(isRunning: entry.snapshot.isRunning)
            }

            Spacer(minLength: 6)

            // ── Timer row ─────────────────────────────────────────────────
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                WidgetClockDigits(snapshot: entry.snapshot, size: 36)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("OF \(goalHours)H GOAL")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.33)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.bronzeMuted)
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .tracking(0.26)
                        .foregroundStyle(Color.toffeeBrown)
                }
            }

            if entry.showsStaleHint {
                StaleHint()
                    .padding(.top, 2)
            }

            Spacer(minLength: 6)

            // ── Progress bar ──────────────────────────────────────────────
            GoalProgressBar(
                isRunning: entry.snapshot.isRunning,
                dailyElapsed: entry.snapshot.dailyBase,
                dailyGoal: entry.snapshot.dailyGoal,
                timerStartedAt: entry.snapshot.runStartedAt,
                goalHours: goalHours
            )
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    RussianTimerWidget()
} timeline: {
    TimerEntry.placeholder
    TimerEntry.previewRunning
    TimerEntry.previewStale
}

#Preview("Medium", as: .systemMedium) {
    RussianTimerWidget()
} timeline: {
    TimerEntry.placeholder
    TimerEntry.previewRunning
    TimerEntry.previewStale
}
