//
//  SampleSessions.swift
//  Calisthenics Vision
//
//  Sample content for SwiftUI previews and for seeding a debug build.
//
//  This exists because the camera can't run in the Simulator, so without it
//  there's no way to get sessions into the store to look at. It is compiled
//  out of release builds.
//

import Foundation
import SwiftData

enum SampleSessions {

    static func make() -> [WorkoutSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        return [
            WorkoutSession(movement: .pushUps,   startedAt: date(daysAgo: 0, hour: 7, minute: 14), duration: 96,  repCount: 24),
            WorkoutSession(movement: .handstand, startedAt: date(daysAgo: 0, hour: 7, minute: 22), duration: 38,  formBreaks: 1),
            WorkoutSession(movement: .pushUps,   startedAt: date(daysAgo: 1, hour: 6, minute: 50), duration: 74,  repCount: 18),
            WorkoutSession(movement: .handstand, startedAt: date(daysAgo: 2, hour: 7, minute: 10), duration: 62),
            WorkoutSession(movement: .pushUps,   startedAt: date(daysAgo: 3, hour: 8, minute: 3),  duration: 88,  repCount: 21, formBreaks: 2),
            WorkoutSession(movement: .pushUps,   startedAt: date(daysAgo: 5, hour: 7, minute: 30), duration: 82,  repCount: 20),
            WorkoutSession(movement: .handstand, startedAt: date(daysAgo: 6, hour: 7, minute: 45), duration: 51),
            WorkoutSession(movement: .pushUps,   startedAt: date(daysAgo: 8, hour: 7, minute: 12), duration: 79,  repCount: 19),
        ]
    }

    /// In-memory container for `#Preview` blocks.
    @MainActor
    static var previewContainer: ModelContainer {
        let container = try! ModelContainer(
            for: WorkoutSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for session in make() {
            container.mainContext.insert(session)
        }
        return container
    }

    #if DEBUG
    /// Seeds a debug build the first time it runs with an empty store, so the
    /// History screens have something to show in the Simulator.
    @MainActor
    static func seedIfEmpty(_ context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutSession>()
        guard let existing = try? context.fetchCount(descriptor), existing == 0 else { return }

        for session in make() { context.insert(session) }
        try? context.save()
    }
    #endif
}
