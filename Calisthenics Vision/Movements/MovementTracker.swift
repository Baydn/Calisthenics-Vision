//
//  MovementTracker.swift
//  Calisthenics Vision
//
//  Per-movement state machines consume smoothed poses and emit events
//  (SPEC.md §2).
//

import Foundation

/// Something worth reacting to — a counted rep, a completed hold, or a form
/// problem. The HUD turns these into haptics, sound, and animation (SPEC.md §5).
enum MovementEvent: Equatable {
    case repCompleted(total: Int)
    case formBreak(FormIssue)
    case formRecovered
}

enum FormIssue: String, Equatable {
    case hipSag = "Keep your hips in line"
    case shallowRep = "Go lower"
    case lostAlignment = "Straighten up"
}

/// Running totals a tracker exposes for the HUD.
struct MovementProgress: Equatable {
    var reps = 0
    /// Seconds accumulated in a valid hold, for timed movements.
    var holdDuration: TimeInterval = 0
    var formBreaks = 0
    var isFormValid = true
    /// 0…1 through the current rep, for progress visuals.
    var repProgress: Double = 0
}

protocol MovementTracker {
    var progress: MovementProgress { get }

    /// Feed one smoothed pose. Returns any event that just occurred.
    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent?
    mutating func reset()
}
