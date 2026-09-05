import Foundation

/// Decides what a full pull does with Sessions, given what is local and what
/// the server holds. Pure so the rules can be tested without a network.
///
/// Rules (ADR 0003):
/// - A Session on both sides: the later `updatedAt` wins. Ties change nothing
///   unless the local copy still needs uploading.
/// - A Session only on the server: adopt it.
/// - A Session only local: upload it if it is waiting to upload (or this is
///   the device's initial upload for the Account); otherwise it was deleted
///   elsewhere, so delete it here.
nonisolated struct SessionSyncPlan: Equatable {
    struct Local: Equatable {
        let date: Date
        let updatedAt: Date
        let needsUpload: Bool
    }
    struct Remote: Equatable {
        let date: Date
        let updatedAt: Date
    }

    var adoptRemote: [Date] = []
    var deleteLocal: [Date] = []
    var upload: [Date] = []

    static func make(local: [Local], remote: [Remote], initialUpload: Bool) -> SessionSyncPlan {
        var plan = SessionSyncPlan()
        let localByDate = Dictionary(local.map { ($0.date, $0) }, uniquingKeysWith: { a, b in
            a.updatedAt >= b.updatedAt ? a : b
        })
        let remoteByDate = Dictionary(remote.map { ($0.date, $0) }, uniquingKeysWith: { a, b in
            a.updatedAt >= b.updatedAt ? a : b
        })

        for (date, r) in remoteByDate.sorted(by: { $0.key < $1.key }) {
            guard let l = localByDate[date] else {
                plan.adoptRemote.append(date)
                continue
            }
            if r.updatedAt > l.updatedAt {
                plan.adoptRemote.append(date)
            } else if l.updatedAt > r.updatedAt || l.needsUpload || initialUpload {
                plan.upload.append(date)
            }
        }
        for (date, l) in localByDate.sorted(by: { $0.key < $1.key }) where remoteByDate[date] == nil {
            if l.needsUpload || initialUpload {
                plan.upload.append(date)
            } else {
                plan.deleteLocal.append(date)
            }
        }
        plan.upload.sort()
        return plan
    }
}

// MARK: - Wire format helpers

/// Dates cross the wire as strings so the app does not depend on the SDK's
/// date strategy: instants as ISO 8601 (UTC), Study Days as `yyyy-MM-dd` in
/// the device calendar.
nonisolated enum SyncDate {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ date: Date) -> String {
        iso.string(from: date)
    }

    /// Tolerates what Postgres and Realtime emit: a space instead of `T`, a
    /// two-digit zone offset, and any number of fractional digits.
    static func date(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        if let r = s.range(of: #"[+-]\d{2}$"#, options: .regularExpression) {
            s += ":00"; _ = r
        }
        if s.hasSuffix("Z") == false, s.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) == nil {
            s += "Z"
        }
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = String(s[r].dropFirst())
            let three = String((digits + "000").prefix(3))
            s.replaceSubrange(r, with: "." + three)
            return iso.date(from: s)
        }
        return isoPlain.date(from: s)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String {
        day.string(from: date)
    }

    static func day(_ raw: String) -> Date? {
        day.date(from: raw).map { Calendar.current.startOfDay(for: $0) }
    }
}
