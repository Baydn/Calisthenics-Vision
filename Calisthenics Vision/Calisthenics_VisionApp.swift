//
//  Calisthenics_VisionApp.swift
//  Calisthenics Vision
//
//  Created by Baydon Galloway on 8/31/26.
//

import SwiftData
import SwiftUI

@main
struct Calisthenics_VisionApp: App {
    @State private var entitlements = Entitlements()

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: WorkoutSession.self)
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(entitlements)
                .task {
                    #if DEBUG
                    SampleSessions.seedIfEmpty(container.mainContext)
                    #endif
                    // Free tier keeps a rolling 7-day window (SPEC.md §4).
                    SessionStore.pruneExpired(
                        windowDays: entitlements.historyWindowDays,
                        context: container.mainContext
                    )
                }
        }
        .modelContainer(container)
    }
}
