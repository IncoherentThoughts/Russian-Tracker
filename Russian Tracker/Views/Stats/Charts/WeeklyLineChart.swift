import SwiftUI
import Charts

struct WeeklyLineChart: View {
    let data: [(weekStart: Date, duration: TimeInterval)]

    private var maxValue: Double {
        let m = data.map { $0.duration / 3600 }.max() ?? 0
        return max(5.0, ceil(m / 5) * 5)
    }

    var body: some View {
        Chart {
            ForEach(data, id: \.weekStart) { entry in
                AreaMark(
                    x: .value("Week", entry.weekStart, unit: .weekOfYear),
                    y: .value("Hours", entry.duration / 3600)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.rosyCopper.opacity(0.18), Color.rosyCopper.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Week", entry.weekStart, unit: .weekOfYear),
                    y: .value("Hours", entry.duration / 3600)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color.rosyCopper)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .symbol {
                    Circle()
                        .fill(Color.eggshellDeep)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Color.rosyCopper, lineWidth: 1.5))
                }
            }
        }
        .chartYScale(domain: 0...maxValue)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.bronzeMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.hairline)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(Int(hours))h")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.bronzeMuted)
                    }
                }
            }
        }
        .frame(height: 160)
    }
}

#Preview {
    let calendar = Calendar.current
    let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
    let data = (0..<8).reversed().map { offset -> (weekStart: Date, duration: TimeInterval) in
        let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek)!
        return (week, TimeInterval.random(in: 0...50000))
    }
    return WeeklyLineChart(data: data)
        .padding()
        .background(Color.eggshellDeep)
}
