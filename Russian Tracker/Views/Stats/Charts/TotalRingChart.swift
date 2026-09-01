import SwiftUI

/// All-time hours, split by study type.
///
/// The center figure is the true all-time total. When manual edits exist it can
/// exceed the sum of the slices, because an edit adds hours to a day without
/// attributing them to any type — that gap is a real property of the data, not
/// a rounding artifact, so the ring shows what it can account for rather than
/// inflating a slice to close it.
struct TotalRingChart: View {
    let totalSeconds: TimeInterval
    let byType: [(type: StudyType, seconds: TimeInterval)]

    private var totalHours: Double { totalSeconds / 3600 }

    private struct Bucket: Identifiable {
        var id: StudyType { type }
        let type: StudyType
        let seconds: TimeInterval
        var hours: Double { seconds / 3600 }
    }

    private var allBuckets: [Bucket] {
        byType.map { Bucket(type: $0.type, seconds: $0.seconds) }
    }

    /// Slices are proportioned against the typed sum, not the all-time total,
    /// so the ring always closes.
    private var typedHours: Double {
        allBuckets.reduce(0) { $0 + $1.hours }
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
                ForEach(arcSegments()) { seg in
                    Circle()
                        .trim(from: seg.start, to: seg.end)
                        .stroke(seg.type.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
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

            // Legend — the one place in the app where the dots are named.
            // Circles, not rounded rects, so they read as the same dots that
            // appear on the Timer screen and the Live Activity.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(allBuckets) { bucket in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(bucket.type.color)
                            .frame(width: 8, height: 8)
                        Text(bucket.type.displayName)
                            .font(.system(size: 12))
                            .foregroundColor(.toffeeInk)
                        Spacer()
                        Text(amountLabel(bucket.seconds))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.bronzeMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Formatted at the resolution the number deserves. A flat "%.0fh" reads
    /// "0h" for anything under half an hour, so an early session — or a type
    /// you have only dabbled in — would look unrecorded when it isn't.
    private func amountLabel(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        if hours >= 10 { return String(format: "%.0fh", hours) }
        if hours >= 1  { return String(format: "%.1fh", hours) }
        return "\(Int((seconds / 60).rounded()))m"
    }

    private struct ArcSegment: Identifiable {
        var id: StudyType { type }
        let type: StudyType
        let start: Double
        let end: Double
    }

    private func arcSegments() -> [ArcSegment] {
        guard typedHours > 0 else { return [] }
        var segments: [ArcSegment] = []
        var cursor: Double = 0
        for bucket in allBuckets where bucket.hours > 0 {
            let frac = bucket.hours / typedHours
            segments.append(ArcSegment(type: bucket.type, start: cursor, end: cursor + frac))
            cursor += frac
        }
        return segments
    }
}

#Preview {
    TotalRingChart(
        totalSeconds: 173 * 3600,
        byType: [
            (.grammar, 62 * 3600),
            (.immersion, 87 * 3600),
            (.output, 24 * 3600),
        ]
    )
    .padding()
    .background(Color.eggshellDeep)
}
