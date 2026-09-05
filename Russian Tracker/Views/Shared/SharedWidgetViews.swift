import SwiftUI
import AppIntents

// Views shared by the Live Activity, the Mac menu bar popover and the
// timeline widget. Lives in the app target and the widget extension via
// the project's membershipExceptions.

// MARK: - Helpers

/// Returns a reference date anchored so that `Text(timerInterval:)` /
/// `Text(_:style: .timer)` auto-counts up to the current daily total:
/// `now - referenceDate == dailyElapsed + (now - startedAt)`.
nonisolated func liveAnchor(elapsed: TimeInterval, startedAt: Date) -> Date {
    startedAt.addingTimeInterval(-elapsed)
}

/// Formats elapsed seconds as MM:SS (under 1 h) or H:MM:SS (1 h+).
/// No leading zero on hours; always two digits for minutes and seconds.
nonisolated func fmtElapsed(_ t: TimeInterval) -> String {
    let s = Int(max(0, t))
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, sec)
        : String(format: "%02d:%02d", m, sec)
}

// MARK: - AppIconView

/// App icon view.
/// Fallback: toffeeBrown rounded rect + book glyph.
/// Real icon: an Image Set named "RussianAppIcon" in the widget extension's
/// Assets.xcassets covers the fallback automatically.
struct AppIconView: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.toffeeBrown)
            Image(systemName: "book.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(Color.eggshell)
            Image("RussianAppIcon")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Widget Play/Pause Button

/// The Start/Pause control used by the Live Activity and the widget. Fires
/// `ToggleTimerIntent`, which performs the Clock Action in the suite.
struct WidgetPlayPauseButton: View {
    let isRunning: Bool
    var size: CGFloat = 44

    var body: some View {
        Button(intent: ToggleTimerIntent()) {
            ZStack {
                Circle()
                    .fill(isRunning ? Color.eggshell.opacity(0.9) : Color.rosyCopper)
                    .shadow(
                        color: isRunning
                            ? Color.toffeeBrown.opacity(0.18)
                            : Color.rosyCopper.opacity(0.55),
                        radius: isRunning ? 3 : 7,
                        x: 0,
                        y: isRunning ? 2 : 6
                    )
                if isRunning {
                    Circle()
                        .strokeBorder(Color.toffeeBrown.opacity(0.25), lineWidth: 1)
                }
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.32, weight: .medium))
                    .foregroundStyle(isRunning ? Color.toffeeInk : Color(hex: "#FDF6E3"))
                    .offset(x: isRunning ? 0 : size * 0.034)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Widget Study Type Dots

/// The three study types as tappable dots.
///
/// Live Activities only accept `Button(intent:)` and `Toggle(intent:)` — no
/// `Menu`, no `Picker` — so this is three buttons rather than a picker control.
/// Unlabeled, matching the app's Timer screen; the names live on the Stats screen.
struct WidgetStudyTypeDots: View {
    let selected: StudyType

    var body: some View {
        HStack(spacing: 10) {
            ForEach(StudyType.allCases) { type in
                Button(intent: SetStudyModeIntent(mode: type)) {
                    ZStack {
                        // Laid out whether or not it's shown, so the row
                        // doesn't shift as the selection moves.
                        Circle()
                            .strokeBorder(type.color, lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                            .opacity(selected == type ? 1 : 0)
                        Circle()
                            .fill(type.color)
                            .frame(width: 9, height: 9)
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(type.displayName)
            }
        }
    }
}

// MARK: - Timer Digits

/// H:MM:SS with colons rendered in lightBronze at regular weight. Static —
/// used when the Clock is paused. A running Clock uses `Text(timerInterval:)`.
struct TimerDigitsView: View {
    let elapsed: TimeInterval
    var size: CGFloat = 40

    private var h: Int { Int(max(0, elapsed)) / 3600 }
    private var m: Int { (Int(max(0, elapsed)) % 3600) / 60 }
    private var s: Int { Int(max(0, elapsed)) % 60 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            digit(String(h))
            colon
            digit(String(format: "%02d", m))
            colon
            digit(String(format: "%02d", s))
        }
    }

    private func digit(_ text: String) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.toffeeInk)
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(Color.lightBronze)
            .baselineOffset(size * 0.1)
            .padding(.horizontal, 2)
    }
}

// MARK: - Goal Progress Bar

/// Custom ProgressViewStyle so we keep the bar's look while delegating value
/// updates to the system. When the bar is driven by `ProgressView(timerInterval:)`,
/// `configuration.fractionCompleted` ticks natively on the Lock Screen — no
/// activity.update() needed.
struct RussianProgressBarStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let progress = min(1.0, max(0.0, configuration.fractionCompleted ?? 0))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.toffeeBrown.opacity(0.18))
                    .frame(height: 4)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color.rosyCopper, Color.copperSoft],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, geo.size.width * progress), height: 4)
                    .shadow(color: Color.rosyCopper.opacity(0.4), radius: 4, x: 0, y: 0)
                ForEach([0.25, 0.5, 0.75] as [Double], id: \.self) { frac in
                    Rectangle()
                        .fill(Color.toffeeBrown.opacity(0.35))
                        .frame(width: 1, height: 8)
                        .offset(x: geo.size.width * frac - 0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 8)
    }
}

struct GoalProgressBar: View {
    let isRunning: Bool
    let dailyElapsed: TimeInterval
    let dailyGoal: TimeInterval
    let timerStartedAt: Date?
    let goalHours: Int

    private var axisLabels: [String] {
        (0...4).map { i in
            let num = goalHours * i
            if num % 4 == 0 {
                return "\(num / 4)h"
            }
            return String(format: "%.1fh", Double(num) / 4.0)
        }
    }

    private var staticProgress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(1.0, dailyElapsed / dailyGoal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if isRunning, let startedAt = timerStartedAt, dailyGoal > 0 {
                    // Anchor chosen so that at `now` the fraction equals
                    // dailyElapsed/dailyGoal, then it ticks forward to 100%
                    // at anchor + dailyGoal — the system updates the
                    // fraction on the Lock Screen with no app wakeups.
                    let anchor = startedAt.addingTimeInterval(-dailyElapsed)
                    let endDate = anchor.addingTimeInterval(dailyGoal)
                    ProgressView(
                        timerInterval: anchor...endDate,
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                } else {
                    ProgressView(value: staticProgress)
                }
            }
            .progressViewStyle(RussianProgressBarStyle())

            HStack {
                ForEach(Array(axisLabels.enumerated()), id: \.offset) { i, label in
                    if i > 0 { Spacer() }
                    Text(label)
                }
            }
            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
            .tracking(0.76)
            .foregroundStyle(Color.bronzeMuted)
        }
    }
}
