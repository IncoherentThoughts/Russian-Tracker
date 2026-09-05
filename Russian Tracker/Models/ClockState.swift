import Foundation
import SwiftData

/// The synced copy of the Clock State: one record per user, carried between
/// devices by CloudKit. The app mirrors `ClockSnapshot` into it after every
/// Clock Action and adopts it when a remote change arrives.
///
/// Every property has a default and nothing is unique, as CloudKit requires.
/// Two records can briefly exist after a first sync between devices that both
/// created one; `StudyStore.clockRecord()` keeps the winner and deletes the rest.
@Model
final class ClockState {
    var isRunning: Bool = false
    var runStartedAt: Date? = nil
    var modeRaw: String = "grammar"
    var studyDay: Date = Date.distantPast
    var dailyBase: Double = 0
    var dailyGrammar: Double = 0
    var dailyImmersion: Double = 0
    var dailyOutput: Double = 0
    var dailyGoal: Double = 14400
    var lastActionAt: Date = Date.distantPast
    var lastActionDevice: String = ""

    init() {}

    var snapshot: ClockSnapshot {
        var s = ClockSnapshot()
        s.isRunning = isRunning
        s.runStartedAt = runStartedAt
        s.mode = StudyType(rawValue: modeRaw) ?? .grammar
        s.studyDay = studyDay
        s.dailyBase = dailyBase
        s.dailyByType = [.grammar: dailyGrammar, .immersion: dailyImmersion, .output: dailyOutput]
            .filter { $0.value > 0 }
        s.dailyGoal = dailyGoal > 0 ? dailyGoal : defaultDailyGoal
        s.lastActionAt = lastActionAt
        s.lastActionDevice = lastActionDevice
        return s
    }

    func apply(_ s: ClockSnapshot) {
        isRunning = s.isRunning
        runStartedAt = s.runStartedAt
        modeRaw = s.mode.rawValue
        studyDay = s.studyDay
        dailyBase = s.dailyBase
        dailyGrammar = s.dailyByType[.grammar] ?? 0
        dailyImmersion = s.dailyByType[.immersion] ?? 0
        dailyOutput = s.dailyByType[.output] ?? 0
        dailyGoal = s.dailyGoal
        lastActionAt = s.lastActionAt
        lastActionDevice = s.lastActionDevice
    }
}
