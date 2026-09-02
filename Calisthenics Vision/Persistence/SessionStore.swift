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
}

enum SessionStore {

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
