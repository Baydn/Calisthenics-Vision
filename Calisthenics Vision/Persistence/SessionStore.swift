//
//  SessionStore.swift
//  Calisthenics Vision
//
//  Operations over stored sessions: derived stats, retention, deletion.
//

import Foundation
import SwiftData

/// Numbers behind the three cards at the top of History.
struct SessionStats {
    var dayStreak = 0
    var repsThisWeek = 0
    var totalSessions = 0

    var bestPushUpSet = 0
    var longestHold: TimeInterval = 0
    /// Every rep ever counted, for lifetime achievements.
    var totalReps = 0

    /// Hold time logged in the last 7 days. A handstand-only week used to
    /// read as a week of zeroes, because every headline number counted reps.
    var holdTimeThisWeek: TimeInterval = 0
    /// Line score of the best-scoring single hold, 0…1. Nil when nothing has
    /// been scored — sessions from before line scoring, or holds too
    /// unreliable to measure.
    var bestLine: Double?
    /// How many individual holds have been logged, across every set.
    var totalHolds = 0
}

/// Where a set sits among everything you've done for that movement.
///
/// Strava's habit loop isn't the leaderboard — it's that *every* effort gets
/// contextualised, so nothing goes unremarked. All of this is computable from
/// sessions already on the phone; none of it needs an account.
struct PerformanceContext {
    /// 1 = best ever for this movement.
    var rank: Int = 1
    /// How many sessions of this movement exist, including this one.
    var total: Int = 1
    /// Days since the last time you matched or beat this, when it isn't an
    /// all-time best. Nil when nothing before it comes close.
    var daysSinceBetter: Int?

    var isPersonalBest: Bool { rank == 1 && total > 1 }
    /// A first-ever set has no context, and saying "1st best" would be
    /// nonsense — the record-to-beat display follows the same rule.
    var hasContext: Bool { total > 1 }

    var rankLabel: String? {
        guard hasContext else { return nil }
        if isPersonalBest { return "Personal best" }
        switch rank {
        case 2:  return "2nd best ever"
        case 3:  return "3rd best ever"
        default: return "\(rank)th best ever"
        }
    }

    /// "Best in 6 weeks" — the phrasing people actually find motivating,
    /// because it beats a number they remember rather than an all-time high
    /// they may never touch.
    var recencyLabel: String? {
        guard hasContext, !isPersonalBest, let days = daysSinceBetter, days >= 7 else { return nil }
        if days >= 365 { return "Best in over a year" }
        if days >= 60  { return "Best in \(days / 30) months" }
        if days >= 14  { return "Best in \(days / 7) weeks" }
        return "Best this week"
    }
}

enum SessionStore {

    // MARK: - Context

    /// Ranks one session against the others for the same movement.
    ///
    /// Holds are ranked on the best single attempt, never the set total —
    /// six five-second handstands are not a thirty-second handstand.
    static func context(
        for session: WorkoutSession,
        among sessions: [WorkoutSession]
    ) -> PerformanceContext {
        func metric(_ s: WorkoutSession) -> Double {
            s.movement.isTimedHold ? s.bestHold : Double(s.repCount)
        }

        let peers = sessions.filter { $0.movement == session.movement && $0.id != session.id }
        var context = PerformanceContext()
        context.total = peers.count + 1
        guard !peers.isEmpty else { return context }

        let mine = metric(session)
        context.rank = 1 + peers.filter { metric($0) > mine }.count

        // Walk backwards to the most recent session that matched or beat this
        // one; the gap to it is what "best in N weeks" means.
        if let previousBetter = peers
            .filter({ $0.startedAt < session.startedAt && metric($0) >= mine })
            .max(by: { $0.startedAt < $1.startedAt }) {
            context.daysSinceBetter = Calendar.current.dateComponents(
                [.day], from: previousBetter.startedAt, to: session.startedAt
            ).day
        }
        return context
    }

    // MARK: - Stats

    static func stats(for sessions: [WorkoutSession]) -> SessionStats {
        var stats = SessionStats()
        stats.totalSessions = sessions.count
        guard !sessions.isEmpty else { return stats }

        let calendar = Calendar.current

        // Reps in the last 7 days.
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) {
            stats.repsThisWeek = sessions
                .filter { $0.startedAt >= weekAgo }
                .reduce(0) { $0 + $1.repCount }
        }

        stats.totalReps = sessions.reduce(0) { $0 + $1.repCount }

        stats.bestPushUpSet = sessions
            .filter { $0.movement == .pushUps }
            .map(\.repCount)
            .max() ?? 0

        // A session's `duration` is the *total* held across the set, so the
        // personal record has to come from the best single attempt — six
        // five-second handstands are not a thirty-second handstand.
        stats.longestHold = sessions
            .filter { $0.movement.isTimedHold }
            .map(\.bestHold)
            .max() ?? 0

        let holdSessions = sessions.filter { $0.movement.isTimedHold }

        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) {
            stats.holdTimeThisWeek = holdSessions
                .filter { $0.startedAt >= weekAgo }
                .reduce(0) { $0 + $1.duration }
        }

        // Scored per hold, not per session: one clean attempt in an otherwise
        // scrappy set is still your best line, and averaging would hide it.
        let holds = holdSessions.flatMap(\.holdSegments)
        stats.totalHolds = holds.count
        stats.bestLine = holds.compactMap(\.quality).max()
            // Sessions recorded before holds were segmented only carry a
            // whole-session score.
            ?? holdSessions.compactMap(\.formQuality).max()

        stats.dayStreak = dayStreak(for: sessions, calendar: calendar)
        return stats
    }

    /// Consecutive days ending today (or yesterday, so a streak isn't shown
    /// as broken before the user has trained today).
    private static func dayStreak(for sessions: [WorkoutSession], calendar: Calendar) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: .now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday)
            else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    // MARK: - Retention

    /// Drops sessions older than the tier's history window, media included.
    /// Free tier keeps 7 days (SPEC.md §4); Pro passes `nil` to keep everything.
    @discardableResult
    static func pruneExpired(
        windowDays: Int?,
        context: ModelContext
    ) -> Int {
        guard let windowDays,
              let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: .now)
        else { return 0 }

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt < cutoff }
        )
        guard let expired = try? context.fetch(descriptor), !expired.isEmpty else { return 0 }

        for session in expired {
            MediaLibrary.deleteMedia(for: session)
            context.delete(session)
        }
        try? context.save()
        return expired.count
    }

    #if DEBUG
    /// Wipes every session and its media — used by the developer panel to
    /// simulate a fresh install without deleting and reinstalling the app.
    @discardableResult
    static func deleteAll(context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<WorkoutSession>()) else { return 0 }
        for session in all {
            MediaLibrary.deleteMedia(for: session)
            context.delete(session)
        }
        try? context.save()
        // Sweep anything left behind by a crash mid-recording.
        MediaLibrary.removeOrphans(keeping: [])
        return all.count
    }
    #endif

    static func delete(_ session: WorkoutSession, context: ModelContext) {
        MediaLibrary.deleteMedia(for: session)
        context.delete(session)
        try? context.save()
    }
}
