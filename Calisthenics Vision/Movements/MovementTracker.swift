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
    /// Emitted each time a hold crosses another whole second.
    case holdTick(seconds: Int)
    case formBreak(FormIssue)
    case formRecovered
}

enum FormIssue: String, Equatable {
    case hipSag = "Keep your hips in line"
    case shallowRep = "Go lower"
    case lostAlignment = "Straighten your line"
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

/// What the debug readout shows. Generalized across movements so the HUD
/// doesn't need to know which tracker is running.
struct TrackerDiagnostics {
    /// Whether the body is in a position this movement can be judged from.
    var isReady = false
    /// Short description of that state, e.g. "in position" / "inverted".
    var readyLabel = "not in position"
    var primaryAngleLabel = "angle"
    var primaryAngle: Double?
    var secondaryAngleLabel = "angle"
    var secondaryAngle: Double?
    /// Free-text note about calibration or measurability.
    var note: String?
    var noteIsWarning = false
}

protocol MovementTracker {
    var progress: MovementProgress { get }
    var diagnostics: TrackerDiagnostics { get }

    /// Feed one smoothed pose. Returns any event that just occurred.
    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent?
    mutating func reset()
}

extension Movement {
    /// The tracker that scores this movement, or nil where none exists yet.
    ///
    /// Returning nil rather than silently substituting a push-up counter means
    /// the UI can say "not supported yet" instead of appearing to work while
    /// counting nothing.
    func makeTracker() -> (any MovementTracker)? {
        switch self {
        case .pushUps:   PushUpTracker()
        case .handstand: HandstandTracker()
        default:         nil
        }
    }

    var isTrackingSupported: Bool { makeTracker() != nil }
}
