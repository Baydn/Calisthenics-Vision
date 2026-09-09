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
        // the default, and it means the same thing in each of these: how
        // where the counting line sits on the depth meter. It is the line
        // the person can see, so the setting moves a thing they can point at.
        let depth = settings.repDepth.depthFraction

        switch movement {
        case .pushUps:
            var tracker = PushUpTracker()
            tracker.standardDepthFraction = depth
            return tracker

        case .squat:
            var tracker = SquatTracker()
            tracker.standardDepthFraction = depth
            return tracker

        case .dip:
            var tracker = DipTracker()
            tracker.standardDepthFraction = depth
            return tracker

        case .planchePushUp:
            var tracker = PlanchePushUpTracker()
            tracker.standardDepthFraction = depth
            return tracker

        case .pullUps:
            var tracker = PullUpTracker()
            // Measured from the top of the pull on a pull-up, but the same
            // idea: where the line sits on the bar.
            tracker.standardDepthFraction = depth
            return tracker

        default:
            return movement.makeTracker()
        }
    }
}
