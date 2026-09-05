#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Menu Bar Item label

/// The status-bar label: the app glyph, plus today's ticking elapsed time
/// only while the Clock is running. Driven by `TimerManager.tick` through
/// `computedDaily`, so it advances once a second without any timer of its own.
struct MenuBarLabel: View {
    @Environment(TimerManager.self) private var timer

    var body: some View {
        if timer.isRunning {
            Label {
                Text(timer.computedDaily.menuBarFormatted)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "book.fill")
            }
            .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "book.fill")
        }
    }
}

// MARK: - Menu Bar Popover

/// The panel behind the Menu Bar Item: today's time, all-time total,
/// Start/Pause, the Study Type switcher, the Daily Goal bar, and the two
/// links out — open the full window, or quit.
struct MenuBarPopoverView: View {
    @Environment(TimerManager.self) private var timer
    @Environment(\.openWindow) private var openWindow

    static let width: CGFloat = 280

    private var goalHours: Int { Int(timer.dailyGoal / 3600) }

    private var todayDateText: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Today · \(f.string(from: Date()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)

            PopoverDigits(elapsed: timer.computedDaily)
                .padding(.top, 10)

            allTimeRow
                .padding(.top, 6)

            goalBar
                .padding(.horizontal, 20)
                .padding(.top, 18)

            StartPauseButton(isRunning: timer.isRunning) {
                withAnimation(.easeInOut(duration: 0.2)) { timer.toggle() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            StudyTypeDots(selected: timer.mode) { timer.setMode($0) }
                .padding(.top, 14)

            footer
                .padding(.top, 16)
        }
        .frame(width: Self.width)
        .background(Color.eggshell)
        .preferredColorScheme(.light)
        .onAppear { timer.onForeground() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text(todayDateText).eyebrowStyle()
            Spacer()
            Text("Goal \(goalHours)h").eyebrowStyle(color: .toffeeBrown)
        }
    }

    private var allTimeRow: some View {
        HStack(spacing: 8) {
            Text("All-time").eyebrowStyle()
            Rectangle()
                .fill(Color.hairline)
                .frame(width: 12, height: 1)
            Text(timer.computedTotal.timerFormatted)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .tracking(1.2)
                .foregroundColor(.toffeeInk)
        }
    }

    /// The Live Activity's goal bar. While running it is anchored on the
    /// banked base and the run's start, so the system advances it.
    private var goalBar: some View {
        GoalProgressBar(
            isRunning: timer.isRunning,
            dailyElapsed: timer.snapshot.dailyBase,
            dailyGoal: timer.dailyGoal,
            timerStartedAt: timer.snapshot.runStartedAt,
            goalHours: goalHours
        )
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
            HStack {
                FooterButton(title: "Open Russian Tracker", systemImage: "macwindow") {
                    openMainWindow()
                }
                Spacer()
                FooterButton(title: "Quit", systemImage: nil) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func openMainWindow() {
        openWindow(id: AppDelegate.mainWindowID)
        // The window's `onAppear` does the same, but that only fires the
        // first time; if the window is already open this brings it forward.
        (NSApp.delegate as? AppDelegate)?.mainWindowDidOpen()
    }
}

// MARK: - Digits

/// Today's elapsed time at popover scale: the Timer screen's digits with
/// bronze separators, shrunk to fit 280pt.
private struct PopoverDigits: View {
    let elapsed: TimeInterval

    private var components: (h: String, m: String, s: String) {
        let total = Int(max(0, elapsed))
        return (
            String(format: "%02d", total / 3600),
            String(format: "%02d", (total % 3600) / 60),
            String(format: "%02d", total % 60)
        )
    }

    var body: some View {
        let c = components
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            digit(c.h)
            separator
            digit(c.m)
            separator
            digit(c.s)
        }
        .contentTransition(.numericText())
    }

    private func digit(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 44, weight: .bold))
            .monospacedDigit()
            .tracking(-1.6)
            .foregroundColor(.toffeeInk)
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 44, weight: .regular))
            .foregroundColor(.lightBronze)
            .baselineOffset(4)
            .padding(.horizontal, 2)
    }
}

// MARK: - Start / Pause

/// A full-width capsule: copper "Start" when paused, parchment "Pause" when
/// running — the same two states as the Timer screen's round button.
private struct StartPauseButton: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(isRunning ? "Pause" : "Start")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.2)
            }
            .foregroundColor(isRunning ? .toffeeInk : Color(hex: "#FDF6E3"))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                ZStack {
                    Capsule().fill(Color.rosyCopper).opacity(isRunning ? 0 : 1)
                    Capsule().fill(Color.eggshellDeep).opacity(isRunning ? 1 : 0)
                }
            )
            .overlay(
                Capsule()
                    .stroke(Color.hairlineStrong, lineWidth: 1)
                    .opacity(isRunning ? 1 : 0)
            )
            .shadow(
                color: isRunning ? Color.toffeeBrown.opacity(0.12) : Color.rosyCopper.opacity(0.35),
                radius: isRunning ? 4 : 12,
                x: 0,
                y: isRunning ? 1 : 6
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .animation(.easeInOut(duration: 0.2), value: isRunning)
    }
}

// MARK: - Footer buttons

private struct FooterButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(hovering ? .toffeeInk : .toffeeBrown)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.toffeeBrown.opacity(hovering ? 0.10 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

#Preview {
    MenuBarPopoverView()
        .environment(TimerManager())
}
#endif
