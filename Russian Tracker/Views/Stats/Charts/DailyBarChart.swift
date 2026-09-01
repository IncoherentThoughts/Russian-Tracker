import SwiftUI
import Charts

struct DailyBarChart: View {
    let data: [(date: Date, duration: TimeInterval)]

    private let today = Calendar.current.startOfDay(for: Date())

    private var maxValue: Double {
        let m = data.map { $0.duration / 3600 }.max() ?? 0
        return max(2.0, ceil(m * 2) / 2)
    }

    var body: some View {
        Chart {
            ForEach(data, id: \.date) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Hours", entry.duration / 3600),
                    width: .fixed(14)
                )
                .foregroundStyle(
                    Calendar.current.startOfDay(for: entry.date) == today
                        ? Color.rosyCopper
                        : Color.lightBronze
                )
                .cornerRadius(4)
            }
        }
        .chartYScale(domain: 0...maxValue)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        let isToday = Calendar.current.startOfDay(for: date) == today
                        Text(date, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 10, weight: isToday ? .medium : .regular))
                            .foregroundColor(isToday ? .toffeeInk : .bronzeMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.hairline)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(formatTick(hours))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.bronzeMuted)
                    }
                }
            }
        }
        .frame(height: 160)
    }

    private func formatTick(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))h"
        }
        return String(format: "%.1fh", value)
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let data = (0..<7).reversed().map { offset -> (date: Date, duration: TimeInterval) in
        let date = calendar.date(byAdding: .day, value: -offset, to: today)!
        return (date, TimeInterval.random(in: 0...7200))
    }
    return DailyBarChart(data: data)
        .padding()
        .background(Color.eggshellDeep)
}
