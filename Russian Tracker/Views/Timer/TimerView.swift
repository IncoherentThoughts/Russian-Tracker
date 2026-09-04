import SwiftUI

struct TimerView: View {
    @Environment(TimerManager.self) private var timer

    @State private var buttonScale: CGFloat = 1.0

    private var dailyGoalSeconds: TimeInterval {
        let g = UserDefaults(suiteName: appGroupSuite)?.double(forKey: "dailyGoal") ?? 0
        return g > 0 ? g : 14400
    }

    private var dailyGoalHours: Int { Int(dailyGoalSeconds / 3600) }

    private var progressFraction: Double {
        guard dailyGoalSeconds > 0 else { return 0 }
        return min(1.0, max(0.0, timer.computedDaily / dailyGoalSeconds))
    }

    private var progressPercentText: String {
        "\(Int((progressFraction * 100).rounded()))%"
    }

    private var todayDateText: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Today · \(f.string(from: Date()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top eyebrow row
            HStack {
                Text(todayDateText).eyebrowStyle()
                Spacer()
                Text("Goal \(dailyGoalHours)h").eyebrowStyle(color: .toffeeBrown)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)

            Spacer()

            // Centered timer stack
            VStack(spacing: 0) {
                    TimerDigits(elapsed: timer.computedDaily)

                    // All-time row
                    HStack(spacing: 10) {
                        Text("All-time").eyebrowStyle()
                        Rectangle()
                            .fill(Color.hairline)
                            .frame(width: 14, height: 1)
                        Text(timer.computedTotal.timerFormatted)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .tracking(1.4)
                            .foregroundColor(.toffeeInk)
                    }
                    .padding(.top, 16)

                    // Progress bar
                    VStack(spacing: 6) {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.hairline)
                                .frame(height: 3)
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color.rosyCopper)
                                    .frame(width: geo.size.width * progressFraction, height: 3)
                                    .animation(.easeInOut(duration: 0.4), value: progressFraction)
                            }
                            .frame(height: 3)
                        }
                        HStack {
                            Text("Progress").eyebrowStyle()
                            Spacer()
                            Text(progressPercentText)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .monospacedDigit()
                                .tracking(0.8)
                                .foregroundColor(.bronzeMuted)
                        }
                    }
                    .frame(width: 200)
                    .padding(.top, 28)
                }

            // Play/Pause button
            PlayPauseButton(isRunning: timer.isRunning, scale: buttonScale) {
                Task {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        buttonScale = 0.96
                    }
                    try? await Task.sleep(for: .seconds(0.12))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        buttonScale = 1.0
                    }
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    timer.toggle()
                }
            }
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: timer.isRunning)
            .padding(.top, 60)

            // Study type switch — dots unlabeled, with a bubble naming the
            // active type; switching mid-session splits the running session
            // rather than interrupting it.
            StudyTypeDots(selected: timer.mode) { timer.setMode($0) }
                .sensoryFeedback(.selection, trigger: timer.mode)
                .padding(.top, 20)

            // State label
            Text(timer.isRunning ? "Studying" : "Tap to begin")
                .eyebrowStyle()
                .padding(.top, 14)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.eggshell)
    }
}

// MARK: - Timer Digits (HH : MM : SS with bronze separators)

private struct TimerDigits: View {
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
            .font(.system(size: 80, weight: .bold))
            .monospacedDigit()
            .tracking(-3.2)
            .foregroundColor(.toffeeInk)
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 80, weight: .regular))
            .foregroundColor(.lightBronze)
            .baselineOffset(8)
            .padding(.horizontal, 4)
    }
}

// MARK: - Play / Pause Button

private struct PlayPauseButton: View {
    let isRunning: Bool
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Warm radial glow — always rendered, opacity-toggled to avoid layout shift
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.rosyCopper.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 94, height: 94)
                    .blur(radius: 4)
                    .opacity(isRunning ? 0 : 1)

                // Background fill — cross-fade both colors so there's no fill snap
                ZStack {
                    Circle().fill(Color.rosyCopper).opacity(isRunning ? 0 : 1)
                    Circle().fill(Color.eggshellDeep).opacity(isRunning ? 1 : 0)
                }
                .frame(width: 74, height: 74)
                .overlay(
                    Circle()
                        .stroke(Color.hairlineStrong, lineWidth: 1)
                        .opacity(isRunning ? 1 : 0)
                )
                .shadow(
                    color: isRunning
                        ? Color.toffeeBrown.opacity(0.15)
                        : Color.rosyCopper.opacity(0.40),
                    radius: isRunning ? 6 : 18,
                    x: 0,
                    y: isRunning ? 2 : 10
                )

                // Both glyphs rendered, cross-faded — keeps each icon's optical
                // offset baked in so neither shifts during the transition.
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Color(hex: "#FDF6E3"))
                    .offset(x: 3)
                    .opacity(isRunning ? 0 : 1)

                Image(systemName: "pause.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.toffeeInk)
                    .opacity(isRunning ? 1 : 0)
            }
            .frame(width: 94, height: 94)
            .scaleEffect(scale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TimerView()
        .environment(TimerManager())
}
