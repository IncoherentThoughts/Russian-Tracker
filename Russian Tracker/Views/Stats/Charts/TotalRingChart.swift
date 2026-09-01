import SwiftUI

struct TotalRingChart: View {
    let totalSeconds: TimeInterval

    private var totalHours: Double { totalSeconds / 3600 }

    private struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let hours: Double
        let color: Color
    }

    private var allBuckets: [Bucket] {
        [
            Bucket(label: "0–50h",    hours: min(totalHours, 50),                  color: .lightBronze),
            Bucket(label: "50–100h",  hours: max(0, min(totalHours - 50,  50)),    color: .rosyCopper),
            Bucket(label: "100–200h", hours: max(0, min(totalHours - 100, 100)),   color: .skyReflection),
            Bucket(label: "200h+",    hours: max(0, totalHours - 200),             color: .toffeeBrown),
        ]
    }

    private var totalForRing: Double {
        max(allBuckets.reduce(0) { $0 + $1.hours }, 0.0001)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            // Donut ring
            ZStack {
                // Track
                Circle()
                    .stroke(Color.toffeeBrown.opacity(0.08), lineWidth: 14)
                    .frame(width: 96, height: 96)

                // Stacked arcs (only for buckets > 0)
                ForEach(arcSegments(), id: \.id) { seg in
                    Circle()
                        .trim(from: seg.start, to: seg.end)
                        .stroke(seg.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(-90))
                }

                VStack(spacing: 2) {
                    Text(String(format: "%.0f", totalHours))
                        .font(.system(size: 32, weight: .light))
                        .monospacedDigit()
                        .tracking(-0.96)
                        .foregroundColor(.toffeeInk)
                    Text("Hours").eyebrowStyle()
                }
            }
            .frame(width: 120, height: 120)

            // Legend
            VStack(alignment: .leading, spacing: 8) {
                ForEach(allBuckets) { bucket in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bucket.color)
                            .frame(width: 8, height: 8)
                        Text(bucket.label)
                            .font(.system(size: 12))
                            .foregroundColor(.toffeeInk)
                        Spacer()
                        Text(String(format: "%.0fh", bucket.hours))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.bronzeMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private struct ArcSegment: Identifiable {
        let id = UUID()
        let start: Double
        let end: Double
        let color: Color
    }

    private func arcSegments() -> [ArcSegment] {
        var segments: [ArcSegment] = []
        var cursor: Double = 0
        for bucket in allBuckets where bucket.hours > 0 {
            let frac = bucket.hours / totalForRing
            segments.append(ArcSegment(start: cursor, end: cursor + frac, color: bucket.color))
            cursor += frac
        }
        return segments
    }
}

#Preview {
    TotalRingChart(totalSeconds: 173 * 3600)
        .padding()
        .background(Color.eggshellDeep)
}
