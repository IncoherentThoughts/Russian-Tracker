import Foundation
import SwiftData

@Model
final class StudySession {
    var date: Date            // normalized to midnight (start of day)
    var duration: TimeInterval // total seconds studied that day
    var isManualEdit: Bool    // true if user manually edited this entry

    init(date: Date, duration: TimeInterval, isManualEdit: Bool = false) {
        self.date = Calendar.current.startOfDay(for: date)
        self.duration = duration
        self.isManualEdit = isManualEdit
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
}
