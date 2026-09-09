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
    /// Emitted each time the hold under way crosses another whole second.
    case holdTick(seconds: Int)
    /// One hold ended and was long enough to keep. `index` is 1-based, so
    /// the HUD can say "hold 3" without arithmetic.
    case holdCompleted(index: Int, duration: TimeInterval)
    case formBreak(FormIssue)
    case formRecovered
}

/// One continuous hold inside a set.
///
/// A handstand session is a set of attempts, not a single unbroken hold —
/// you come down, shake out, and go again. Each attempt is timed and scored
/// separately so the set reads the way it was actually performed.
struct HoldSegment: Equatable {
    var duration: TimeInterval
    /// Capture-clock instant the hold began, so review can jump to it.
    var startTimestampMs: Int
    /// Mean line quality over this hold alone, 0…1, where measurable.
    var quality: Double?

    /// Shortest hold that counts as landing the kick-up.
    ///
    /// A judgement call, deliberately low: getting up and holding two seconds
    /// is a landed kick-up even if it isn't a good handstand yet. Anything
    /// shorter is a kick-up you came straight back down from.
    static let kickUpSuccessSeconds: TimeInterval = 2.0

    var isLandedKickUp: Bool { duration >= Self.kickUpSuccessSeconds }
}

/// What a movement's line is supposed to be measured against.
///
/// `.endToEnd` only shows *bend*: a body that is perfectly straight but held
/// at the wrong angle reads as perfect against it. Where gravity decides
/// what the right angle is, the reference has to come from gravity instead.
enum IdealLine: Equatable {
    /// A plumb line through the base of support — hands, or the bar.
    case vertical
    /// Level with the ground.
    case horizontal
    /// The straight line between the ends of the chain.
    case endToEnd
}

enum FormIssue: String, Equatable {
    case hipSag = "Keep your hips in line"
    case shallowRep = "Go lower"
    case lostAlignment = "Straighten your line"
    case kipping = "Keep your legs still"
    case kneeCave = "Push your knees out"
    case shallowDip = "Go deeper"
    /// A planche's own fault, and the common one: the body is straight but
    /// tilted, hips riding up above shoulder height. "Straighten your line"
    /// would be wrong advice — the line *is* straight.
    case hipsNotLevel = "Level your hips"
}

/// Running totals a tracker exposes for the HUD.
struct MovementProgress: Equatable {
    var reps = 0
    /// Every hold completed so far in this set, oldest first.
    var holds: [HoldSegment] = []
    /// Seconds in the hold currently under way; 0 when not holding.
    var currentHold: TimeInterval = 0
    var formBreaks = 0
    var isFormValid = true
    /// 0…1 through the current rep, for progress visuals.
    var repProgress: Double = 0
    /// Mean line quality across the whole set, 0…1. Nil where the movement
    /// doesn't score form, or where nothing measurable has happened yet.
    var formQuality: Double?
    /// Times you went up in this set, landed or not. Every hold below is one
    /// of these; the rest came straight back down.
    var kickUpAttempts = 0

    /// Total counted hold time across the set, including the one in progress.
    var holdDuration: TimeInterval {
        holds.reduce(0) { $0 + $1.duration } + currentHold
    }

    /// The best single hold, which is what a hold set is judged on — a
    /// two-minute total made of six-second attempts is a different session
    /// from one unbroken two-minute handstand.
    var bestHold: TimeInterval {
        max(holds.map(\.duration).max() ?? 0, currentHold)
    }

    /// Kick-ups that turned into a hold worth the name.
    var landedKickUps: Int { holds.filter(\.isLandedKickUp).count }
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

    /// Where `progress.repProgress` needs to reach for the rep under way to
    /// count, once enough motion has been seen to know it — nil before
    /// calibration, and nil for anything with no depth gate at all (a timed
    /// hold has no "how far down" to show). Surfaced so the HUD's depth meter
    /// can mark the same line the state machine actually counts at, rather
    /// than a second guess at it.
    var depthGateProgress: Double? { get }

    /// Feed one smoothed pose. Returns any event that just occurred.
    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent?
    mutating func reset()

    /// Called when the set ends, to close anything still open — a hold that
    /// was still running when the recording stopped would otherwise be lost.
    mutating func finish()
}

extension MovementTracker {
    /// Most movements have nothing to settle; only segmented holds override.
    mutating func finish() {}
    var depthGateProgress: Double? { nil }
}

extension Movement {
    /// The tracker that scores this movement, or nil where none exists yet.
    ///
    /// Returning nil rather than silently substituting a push-up counter means
    /// the UI can say "not supported yet" instead of appearing to work while
    /// counting nothing.
    /// The tracker with its own defaults, free of any user preference —
    /// `Movements/` stays pure so it compiles into the standalone test
    /// harness (POSE.md §12). Preferences are applied by `TrackerFactory`.
    func makeTracker() -> (any MovementTracker)? {
        switch self {
        case .pushUps:   PushUpTracker()
        case .pullUps:   PullUpTracker()
        case .squat:     SquatTracker()
        case .dip:       DipTracker()
        case .handstand: HandstandTracker()
        case .planche:   PlancheTracker()
        case .planchePushUp: PlanchePushUpTracker()
        default:         nil
        }
    }

    var isTrackingSupported: Bool { makeTracker() != nil }

    /// The joint this movement is judged at, for the angle overlay: the
    /// vertex and the two joints whose lines form it.
    ///
    /// Deliberately the same angle the tracker counts on and the same one the
    /// chart plots — three views of one measurement. Left-side joints; the
    /// overlay mirrors them to whichever side the camera can see.
    var focusAngle: (vertex: PoseJoint, from: PoseJoint, to: PoseJoint, label: String)? {
        switch self {
        // A handstand's shoulder wants to be open at 180°; a planche's wants
        // to be closed at roughly 60°, because that angle *is* the lean out
        // past the hands. Same joint, opposite ideal — which is why the
        // chart bands for the two can't be shared.
        case .handstand, .planche:
            (.leftShoulder, .leftWrist, .leftHip, "Shoulder")
        case .pushUps, .dip, .pullUps, .planchePushUp:
            (.leftElbow, .leftShoulder, .leftWrist, "Elbow")
        case .squat:
            (.leftKnee, .leftHip, .leftAnkle, "Knee")
        default:
            nil
        }
    }

    /// Joints that should form one straight line, in order.
    ///
    /// The alignment overlay draws the straight line between the ends and the
    /// real path through the middle, so the gap between them *is* the fault —
    /// a piked handstand or a sagging push-up shows as the two lines parting.
    var alignmentChain: [PoseJoint]? {
        switch self {
        // Hands are part of the line when you're standing on them.
        case .handstand, .handstandPushUp:
            [.leftWrist, .leftShoulder, .leftHip, .leftAnkle]
        case .pushUps, .plank, .hollowBody, .planche, .planchePushUp,
             .frontLever, .backLever, .elbowLever, .dip, .pullUps, .deadHang,
             .oneArmPullUp, .muscleUps:
            [.leftShoulder, .leftHip, .leftAnkle]
        // An L-sit's legs are meant to be at ninety degrees to the torso, so
        // there is no straight line to hold and nothing honest to draw.
        default:
            nil
        }
    }

    /// What the line this movement holds is meant to be measured against.
    ///
    /// "Vertical" and "level" here mean vertical and level *in the picture*.
    /// Capture rotates with the interface, so that matches gravity for a
    /// phone stood up or laid on its side — which is every way you'd prop one
    /// to film this. A phone tilted back leans the reference with it.
    var idealLine: IdealLine {
        switch self {
        // Judged against gravity: straight but leaning is still a fault, and
        // only a plumb line through the hands or the bar shows it.
        case .handstand, .handstandPushUp, .deadHang, .pullUps, .oneArmPullUp,
             .muscleUps, .dip:
            .vertical
        // Held parallel to the ground, which is the same argument turned on
        // its side: a planche with the hips riding high is straight and still
        // wrong, and only a level reference shows that. The gymnastics
        // standard says the same thing — 45° off level stops being a planche.
        case .planche, .planchePushUp, .frontLever, .backLever, .elbowLever,
             .humanFlag:
            .horizontal
        // A push-up or a plank runs from raised shoulders down to feet on the
        // floor. That line is a diagonal, not a level one, so the only honest
        // reference is the one drawn end to end.
        default:
            .endToEnd
        }
    }

    /// A one-time framing tip (BACKLOG.md F5), never a gate — a movement
    /// whose line runs the length of the body loses more of it to a portrait
    /// frame than one whose line runs top to bottom does, so the same
    /// horizontal/vertical split `idealLine` already draws answers this too.
    /// Nil for anything with no line to fit in frame in the first place.
    var cameraAngleHint: String? {
        guard alignmentChain != nil, idealLine != .vertical else { return nil }
        return "Films better in landscape — your whole line fits in frame"
    }

    /// Whether a pose is in the position this movement is judged from, with
    /// no tracker state involved.
    ///
    /// The live HUD reads this off the running tracker's diagnostics, but
    /// review has no tracker — it replays frames off disk — and the overlay
    /// still needs to fade in and out at the same moments. Each case defers
    /// to the same gate its tracker uses, so the two never disagree.
    /// Nil where the movement has no tracker and so no position to be in.
    func isInPosition(_ pose: Pose) -> Bool? {
        switch self {
        case .pushUps:   pose.isTorsoHorizontal ?? false
        case .pullUps:   PullUpTracker.isHanging(pose)
        case .squat:     SquatTracker.isStandingUpright(pose)
        case .dip:       DipTracker.isSupported(pose)
        case .handstand: HandstandTracker.isInverted(pose)
        case .planche:   PlancheTracker.isSupported(pose)
        case .planchePushUp: PlanchePushUpTracker.isInPosition(pose)
        default:         nil
        }
    }
}
