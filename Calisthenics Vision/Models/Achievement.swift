//
//  Achievement.swift
//  Calisthenics Vision
//
//  Achievements the camera actually watched you earn.
//
//  Every rival's badges are self-reported — you tick a box saying you held a
//  handstand. Ours are witnessed: the count came from the same measurement
//  pipeline that draws the skeleton. That's the whole point of them, so
//  nothing here may be awarded from anything but recorded sessions.
//
//  Derived rather than stored. Recomputing from sessions means an achievement
//  can never drift out of sync with the history that justifies it, and
//  deleting a session correctly takes its achievements with it.
//

import Foundation

struct Achievement: Identifiable, Hashable {
    let id: String
    let title: String
    /// What you did to earn it, in the past tense.
    let detail: String
    let symbol: String
}

/// Everything the definitions below are allowed to look at.
struct AchievementContext {
    var sessionCount = 0
    var totalReps = 0
    var bestSet = 0
    var bestHold: TimeInterval = 0
    var totalHolds = 0
    var dayStreak = 0

    init(sessions: [WorkoutSession], stats: SessionStats) {
        sessionCount = sessions.count
        totalReps = stats.totalReps
        bestSet = stats.bestPushUpSet
        bestHold = stats.longestHold
        totalHolds = stats.totalHolds
        dayStreak = stats.dayStreak
    }
}

enum Achievements {

    private struct Definition {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let isEarned: (AchievementContext) -> Bool

        /// Trailing-closure form, so a one-line predicate reads as one.
        init(
            id: String, title: String, detail: String, symbol: String,
            _ isEarned: @escaping (AchievementContext) -> Bool
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.symbol = symbol
            self.isEarned = isEarned
        }
    }

    // Ordered easiest first, so the list reads as a path rather than a wall.
    private static let definitions: [Definition] = [
        Definition(
            id: "first-session", title: "First Rep Counted",
            detail: "Recorded your first session", symbol: "checkmark.seal.fill"
        ) { $0.sessionCount >= 1 },
        Definition(
            id: "set-10", title: "Ten in a Set",
            detail: "10 push-ups in one set", symbol: "10.circle.fill"
        ) { $0.bestSet >= 10 },
        Definition(
            id: "first-hold", title: "Upside Down",
            detail: "Held your first handstand", symbol: "figure.gymnastics"
        ) { $0.bestHold > 0 },
        Definition(
            id: "hold-10", title: "Ten Seconds",
            detail: "Held a handstand for 10 seconds", symbol: "timer"
        ) { $0.bestHold >= 10 },
        Definition(
            id: "streak-3", title: "Three Days",
            detail: "Trained three days running", symbol: "flame.fill"
        ) { $0.dayStreak >= 3 },
        Definition(
            id: "set-25", title: "Twenty-Five",
            detail: "25 push-ups in one set", symbol: "bolt.fill"
        ) { $0.bestSet >= 25 },
        Definition(
            id: "reps-100", title: "Century",
            detail: "100 push-ups counted, all time", symbol: "chart.line.uptrend.xyaxis"
        ) { $0.totalReps >= 100 },
        Definition(
            id: "hold-30", title: "Half a Minute",
            detail: "Held a handstand for 30 seconds", symbol: "hourglass"
        ) { $0.bestHold >= 30 },
        Definition(
            id: "streak-7", title: "A Full Week",
            detail: "Trained seven days running", symbol: "calendar"
        ) { $0.dayStreak >= 7 },
        Definition(
            id: "holds-50", title: "Fifty Attempts",
            detail: "50 handstands logged", symbol: "arrow.triangle.2.circlepath"
        ) { $0.totalHolds >= 50 },
        Definition(
            id: "reps-500", title: "Five Hundred",
            detail: "500 push-ups counted, all time", symbol: "crown.fill"
        ) { $0.totalReps >= 500 },
    ]

    private static func achievement(_ d: Definition) -> Achievement {
        Achievement(id: d.id, title: d.title, detail: d.detail, symbol: d.symbol)
    }

    static func earned(in context: AchievementContext) -> [Achievement] {
        definitions.filter { $0.isEarned(context) }.map(achievement)
    }

    static func locked(in context: AchievementContext) -> [Achievement] {
        definitions.filter { !$0.isEarned(context) }.map(achievement)
    }

    /// What became true between two states — for the moment worth celebrating.
    static func newlyEarned(
        from before: AchievementContext,
        to after: AchievementContext
    ) -> [Achievement] {
        let had = Set(earned(in: before).map(\.id))
        return earned(in: after).filter { !had.contains($0.id) }
    }
}
