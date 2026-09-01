import Foundation
import SwiftData

@Model
final class StudySession {
    var date: Date            // normalized to midnight (start of day)
    var duration: TimeInterval // total seconds studied that day
    var isManualEdit: Bool    // true if user manually edited this entry

    // Per-type breakdown of `duration`.
    //
    // `duration` stays the authoritative daily total: every existing stat
    // (streak, average, best day, the bar and line charts) reads it and is
    // unaffected by types. These three are an additional dimension underneath.
    //
    // Invariant: grammar + immersion + output <= duration. The two are equal
    // for a day recorded entirely by the timer; a manual edit raises `duration`
    // without attributing the difference to any type, which is why the ring can
    // legitimately show fewer hours than the all-time total.
    var grammarDuration: TimeInterval = 0
    var immersionDuration: TimeInterval = 0
    var outputDuration: TimeInterval = 0

    init(
        date: Date,
        duration: TimeInterval,
        isManualEdit: Bool = false,
        grammarDuration: TimeInterval = 0,
        immersionDuration: TimeInterval = 0,
        outputDuration: TimeInterval = 0
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.duration = duration
        self.isManualEdit = isManualEdit
        self.grammarDuration = grammarDuration
        self.immersionDuration = immersionDuration
        self.outputDuration = outputDuration
    }
}

extension StudySession {
    /// Formats duration as "Xh Ym" for display
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    func duration(for type: StudyType) -> TimeInterval {
        switch type {
        case .grammar:   return grammarDuration
        case .immersion: return immersionDuration
        case .output:    return outputDuration
        }
    }

    func setDuration(_ value: TimeInterval, for type: StudyType) {
        switch type {
        case .grammar:   grammarDuration = value
        case .immersion: immersionDuration = value
        case .output:    outputDuration = value
        }
    }

    var breakdown: [StudyType: TimeInterval] {
        Dictionary(uniqueKeysWithValues: StudyType.allCases.map { ($0, duration(for: $0)) })
    }

    /// The type this day was mostly spent on, or nil when no time was
    /// attributed to any type — a day created purely by a manual edit. The
    /// heatmap falls back to its neutral tint in that case rather than picking
    /// an arbitrary winner among three zeroes.
    var dominantType: StudyType? {
        let ranked = StudyType.allCases
            .map { ($0, duration(for: $0)) }
            .max { $0.1 < $1.1 }
        guard let ranked, ranked.1 > 0 else { return nil }
        return ranked.0
    }
}
