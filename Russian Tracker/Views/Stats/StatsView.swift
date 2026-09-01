import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(StudyStore.self) private var store
    @Environment(TimerManager.self) private var timer
    @Query(sort: \StudySession.date) private var allSessions: [StudySession]

    private var monthEyebrow: String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: Date())
    }

    private var monthShort: String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Page header
                HStack(alignment: .firstTextBaseline) {
                    Text("Statistics").pageTitleStyle()
                    Spacer()
                    Text(monthEyebrow).eyebrowStyle()
                }
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .padding(.bottom, 24)

                // Top stat cards grid
                HStack(spacing: 10) {
                    StreakCard(streak: store.streak(from: allSessions))
                    DailyAvgCard(seconds: store.dailyAverage(from: allSessions))
                }
                .padding(.bottom, 10)

                // Best Day card
                BestDayCard(session: store.bestDay(from: allSessions))
                    .padding(.bottom, 22)

                // Last 7 days bar chart
                StatCardContainer(title: "Last 7 days", trailing: "Hours") {
                    DailyBarChart(data: todayOverridden(store.lastNDays(7, from: allSessions)))
                }
                .padding(.bottom, 14)

                // Last 8 weeks line chart
                StatCardContainer(title: "Last 8 weeks", trailing: "Trend") {
                    WeeklyLineChart(data: store.lastNWeeks(8, from: allSessions))
                }
                .padding(.bottom, 14)

                // This month heatmap
                StatCardContainer(title: "This month", trailing: monthShort) {
                    MonthlyHeatmap(data: todayOverridden(store.currentMonthDays(from: allSessions)))
                }
                .padding(.bottom, 14)

                // All-time ring, split by study type
                StatCardContainer(title: "All-time", trailing: "Hours") {
                    TotalRingChart(
                        totalSeconds: timer.computedTotal,
                        byType: StudyType.allCases.map { ($0, timer.computedTotal(for: $0)) }
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 62)
            .padding(.bottom, 120)
        }
        .background(Color.eggshell.ignoresSafeArea())
        .onAppear {
            store.upsertSession(
                date: Date(),
                duration: timer.computedDaily,
                breakdown: timer.currentDayBreakdown()
            )
        }
    }

    /// Today's row is patched from the live timer, because time accrued since
    /// the last persist hasn't reached SwiftData yet and the charts would
    /// otherwise lag the running clock.
    private func todayOverridden(
        _ days: [(date: Date, duration: TimeInterval)]
    ) -> [(date: Date, duration: TimeInterval)] {
        let today = Calendar.current.startOfDay(for: Date())
        return days.map { entry in
            entry.date == today ? (entry.date, max(entry.duration, timer.computedDaily)) : entry
        }
    }

    /// Same patch for the heatmap, which also needs today's dominant type kept
    /// current — a session that just switched to immersion should retint today
    /// without waiting for the next persist.
    private func todayOverridden(
        _ days: [(date: Date, duration: TimeInterval, dominantType: StudyType?)]
    ) -> [(date: Date, duration: TimeInterval, dominantType: StudyType?)] {
        let today = Calendar.current.startOfDay(for: Date())
        let liveDominant = timer.currentDayBreakdown()
            .filter { $0.value > 0 }
            .max { $0.value < $1.value }?
            .key
        return days.map { entry in
            guard entry.date == today else { return entry }
            return (
                entry.date,
                max(entry.duration, timer.computedDaily),
                liveDominant ?? entry.dominantType
            )
        }
    }
}

// MARK: - Card primitives

struct PolishCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.eggshellDeep)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.toffeeBrown.opacity(0.06), lineWidth: 1)
            )
    }
}

struct StatCardContainer<Content: View>: View {
    let title: String
    let trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        PolishCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).sectionHeaderStyle()
                    Spacer()
                    if let trailing {
                        Text(trailing).eyebrowStyle()
                    }
                }
                content()
            }
        }
    }
}

// MARK: - Streak / Daily Avg / Best Day

private struct StreakCard: View {
    let streak: Int

    var body: some View {
        PolishCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.rosyCopper)
                    Text("Streak").eyebrowStyle(color: .rosyCopper)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streak)").bigStatStyle()
                    Text("days").statUnitStyle()
                }
                Text(streak == 0 ? "Start one today" : "Keep it going")
                    .font(.system(size: 11))
                    .foregroundColor(.bronzeMuted)
            }
        }
    }
}

private struct DailyAvgCard: View {
    let seconds: TimeInterval

    private var minutesValue: Int {
        Int((seconds / 60).rounded())
    }

    private var displayValue: (number: String, unit: String) {
        if minutesValue >= 60 {
            let hrs = Double(minutesValue) / 60.0
            return (String(format: "%.1f", hrs), "hr")
        }
        return ("\(minutesValue)", "min")
    }

    var body: some View {
        PolishCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.toffeeBrown)
                    Text("Daily avg").eyebrowStyle(color: .toffeeBrown)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayValue.number).bigStatStyle()
                    Text(displayValue.unit).statUnitStyle()
                }
                Text("Last 30 days")
                    .font(.system(size: 11))
                    .foregroundColor(.bronzeMuted)
            }
        }
    }
}

private struct BestDayCard: View {
    let session: StudySession?

    private var dateString: String {
        guard let session, session.duration > 0 else { return "—" }
        return session.date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var durationString: String {
        guard let session, session.duration > 0 else { return "0m" }
        return session.duration.compactFormatted
    }

    var body: some View {
        PolishCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.skyReflection)
                    Text("Best day").eyebrowStyle(color: .skyReflection)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(durationString).bigStatStyle()
                    Spacer()
                    Text(dateString)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.bronzeMuted)
                }
            }
        }
    }
}

// MARK: - Style helpers

private extension Text {
    func bigStatStyle() -> some View {
        self
            .font(.system(size: 42, weight: .light))
            .monospacedDigit()
            .tracking(-1.47)
            .foregroundColor(.toffeeInk)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    func statUnitStyle() -> some View {
        self
            .font(.system(size: 12, weight: .regular))
            .tracking(0.96)
            .textCase(.uppercase)
            .foregroundColor(.bronzeMuted)
    }
}

#Preview {
    StatsView()
        .environment(StudyStore())
        .environment(TimerManager())
}
