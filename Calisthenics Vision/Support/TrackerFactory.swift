//
//  TrackerFactory.swift
//  Calisthenics Vision
//
//  Builds a movement's tracker with the user's preferences applied.
//
//  This lives outside `Movements/` deliberately. That directory compiles into
//  the standalone test harness (POSE.md §12), and dragging UserDefaults into
//  it would break the one way this app's measurement is actually verified.
//  `Movement.makeTracker()` therefore stays pure, and every preference is
//  applied here — one place, so a new tracker can't quietly ignore a setting.
//

import Foundation

enum TrackerFactory {

    @MainActor
    static func make(for movement: Movement) -> (any MovementTracker)? {
        let settings = AppSettings.shared

        switch movement {
        case .pushUps:
            var tracker = PushUpTracker()
            // Depth is the one gate someone might reasonably want tighter
            // than the default. The default stays lenient, because an
            // uncounted rep reads as a broken app (POSE.md Law 4).
            tracker.bottomGateFraction = settings.repDepth.bottomGateFraction
            return tracker

        default:
            return movement.makeTracker()
        }
    }
}
