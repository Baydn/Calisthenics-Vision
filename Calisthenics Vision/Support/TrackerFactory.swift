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

        // Depth is the one gate someone might reasonably want tighter than
        // the default, and it means the same thing in each of these: how far
        // into your own observed range a rep has to travel. The default stays
        // lenient, because an uncounted rep reads as a broken app (Law 4).
        let depth = settings.repDepth.bottomGateFraction

        switch movement {
        case .pushUps:
            var tracker = PushUpTracker()
            tracker.bottomGateFraction = depth
            return tracker

        case .squat:
            var tracker = SquatTracker()
            tracker.bottomGateFraction = depth
            return tracker

        case .dip:
            var tracker = DipTracker()
            tracker.bottomGateFraction = depth
            return tracker

        case .pullUps:
            var tracker = PullUpTracker()
            // Named for the top on a pull-up, but the same idea: how far into
            // your range the rep has to travel to count.
            tracker.topGateFraction = depth
            return tracker

        default:
            return movement.makeTracker()
        }
    }
}
