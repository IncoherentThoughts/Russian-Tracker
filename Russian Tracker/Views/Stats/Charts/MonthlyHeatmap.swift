import SwiftUI

struct MonthlyHeatmap: View {
    let data: [(date: Date, duration: TimeInterval, dominantType: StudyType?)]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    private var leadingOffset: Int {
        guard let first = data.first?.date else { return 0 }
        return Calendar.current.component(.weekday, from: first) - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Weekday headers
            HStack(spacing: 6) {
                ForEach(dayLabels.indices, id: \.self) { i in
                    Text(dayLabels[i])
                        .font(.system(size: 10, weight: .regular))
                        .tracking(1.0)
                        .foregroundColor(.bronzeMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<leadingOffset, id: \.self) { _ in
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
                ForEach(data, id: \.date) { entry in
                    HeatmapCell(
                        date: entry.date,
                        duration: entry.duration,
                        dominantType: entry.dominantType
                    )
                }
            }

            // Legend — intensity only. Which color means which study type is
            // explained once, on the all-time ring below; repeating it here
            // would put two legends in competition on one screen.
            HStack(spacing: 6) {
                Spacer()
                Text("Less").eyebrowStyle()
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(HeatmapCell.color(for: i))
                        .frame(width: 10, height: 10)
                }
                Text("More").eyebrowStyle()
            }
            .padding(.top, 6)
        }
    }
}

struct HeatmapCell: View {
    let date: Date
    let duration: TimeInterval
    /// The study type this day was mostly spent on. Nil for an untyped day —
    /// one created purely by a manual edit — which falls back to the neutral
    /// copper ramp rather than claiming a type it doesn't have.
    var dominantType: StudyType?

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var intensityLevel: Int {
        // 0: none, 1: <1h, 2: 1-2h, 3: 2h+
        let hours = duration / 3600
        if hours <= 0 { return 0 }
        if hours < 1 { return 1 }
        if hours < 2 { return 2 }
        return 3
    }

    /// Hue answers "what kind of study", opacity answers "how much" — the two
    /// dimensions stay independent so a light immersion day and a heavy one
    /// read as the same color at different strengths.
    private var tint: Color { dominantType?.color ?? .rosyCopper }

    private var fill: Color {
        Self.color(for: intensityLevel, tint: tint)
    }

    static func color(for level: Int, tint: Color = .rosyCopper) -> Color {
        switch level {
        case 0: return Color.toffeeBrown.opacity(0.06)
        case 1: return tint.opacity(0.18)
        case 2: return tint.opacity(0.40)
        default: return tint.opacity(0.75)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isToday ? tint : .clear, lineWidth: 1.5)
                )

            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 10, weight: isToday ? .semibold : .regular, design: .monospaced))
                .foregroundColor(intensityLevel >= 2 ? Color(hex: "#FDF6E3") : .bronzeMuted)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let monthInterval = calendar.dateInterval(of: .month, for: today)!
    let days = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 28
    let types: [StudyType?] = [.grammar, .immersion, .output, nil]
    let data = (0..<days).map { offset -> (date: Date, duration: TimeInterval, dominantType: StudyType?) in
        let date = calendar.date(byAdding: .day, value: offset, to: monthInterval.start)!
        return (date, TimeInterval.random(in: 0...10000), types[offset % types.count])
    }
    return MonthlyHeatmap(data: data)
        .padding()
        .background(Color.eggshellDeep)
}
