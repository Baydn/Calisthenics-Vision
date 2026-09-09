//
//  PlancheGeometry.swift
//  Calisthenics Vision
//
//  The geometry a planche and a planche push-up share. Measurement rules:
//  POSE.md.
//
//  Written once, because both movements ask the same question — is the body
//  floating level on the hands with the shoulders out past them? — and
//  because that question is the subtlest one in this codebase. It shipped
//  wrong the first time, and the way it was wrong is worth keeping:
//
//  The first version compared how close the hip sat to shoulder height
//  against how close it sat to wrist height, on the theory that a push-up's
//  hip rides down at hand level. It doesn't. At a push-up lockout the
//  shoulders are up at arm's length and only the toes are on the floor, so
//  the body is a *diagonal* and the hip sits midway — about 0.2 m below the
//  shoulder against a 0.5 m torso, which passed that test comfortably. The
//  harness fixture had the same wrong shape, so 38 checks agreed with the
//  bug (POSE.md §12: a fixture that shares a bug with the code proves
//  nothing).
//
//  What actually separates them:
//
//  1. **The lean.** If the shoulders stay over the wrists it isn't a planche:
//     they have to travel out past the hands so the centre of mass lands over
//     them, because the legs hang off the back as a counterweight. A push-up
//     has no lean at all — the arm is vertical. This is what catches a
//     *decline* push-up, whose feet are up on a box and which is level, legs
//     up, and passes every height test a planche does.
//  2. **The feet, measured against the hands.** The lean alone isn't enough,
//     because a *pseudo planche push-up* — hands down by the hips — has the
//     full lean by design and is the drill people do on the way to a planche.
//     What it doesn't have is air under its feet. There's no ground reference
//     in a pose, but the hands are on the ground by definition here, so the
//     feet can be measured against them: a planche floats its ankles about
//     0.9 torso lengths above its hands, anything with toes down keeps them
//     level with the hands or below. Vertical axis only, so it survives any
//     camera angle.
//
//     Measuring the feet against the *shoulders* instead — the obvious
//     version — doesn't work: a deep lean drops the shoulders toward hand
//     height, which hides the difference.
//
//  Neither is a camera-angle assumption: both are read off metric world
//  landmarks (POSE.md Law 1), so they hold filmed from any side.
//
//  The one freedom this movement can't have is camera *roll*. Every other
//  tracker is built from joint angles, which don't care how the phone is
//  turned. A planche can't be: "level with the ground" and "out past the
//  hands" are defined by gravity, and there is no gravity in a pose — only
//  the image's own vertical, which is the same thing the plumb-line overlay
//  relies on. Capture rotates with the interface, so a propped phone is
//  upright to within its own tilt, and a phone wedged at a diagonal stops
//  reading the position rather than reading it wrong.
//

import Foundation
import simd

enum PlancheGeometry {

    /// Elbow angle at or above which the arms count as locked. A planche is a
    /// straight-arm skill; bend them and it's an elbow lever.
    static let lockedElbowAngle: Double = 140
    /// Knee angle above which the legs count as extended. Below it the body
    /// is tucked, and the straightness of a tuck is not a fault to report —
    /// a tuck planche is *meant* to be folded.
    static let extendedKneeAngle: Double = 150
    /// Deviation from level at which line quality has bottomed out. Matches
    /// the gymnastics standard, which treats a planche as failed once the
    /// hips are 45° off horizontal.
    static let levelTaperDegrees: Double = 45

    /// One frame's worth of planche geometry, all of it normalized by torso
    /// length so it means the same thing whatever size the person is and
    /// however far away the camera stands.
    struct Reading {
        /// Metres the shoulders sit ahead of the hands along the body's own
        /// forward direction. Positive is a lean; a push-up reads ~0.
        var lean: Double
        /// The same as a fraction of torso length.
        var leanFraction: Double
        /// Degrees the torso runs off horizontal. 0 is parallel to the ground.
        var levelDeviation: Double
        /// Shoulder–hip–ankle angle, but only where the legs are extended
        /// enough for it to mean anything. Nil in a tuck.
        var straightness: Double?
        /// How far the ankles float above the *hands*, in torso lengths — the
        /// closest thing to "feet off the ground" that a pose can offer, the
        /// hands being the part known to be on it. A planche reads ~0.9;
        /// anything with toes down reads ~0.2 or less. Nil without ankles.
        var feetAboveHands: Double?
        /// How far the wrists sit below the shoulders, in torso lengths.
        var handDrop: Double
        /// How far the hips sit from shoulder height, in torso lengths.
        /// Signed: positive means the hips have dropped below the shoulders.
        var hipOffset: Double
        var elbowAngle: Double?
        /// Whether the body line runs across the frame rather than into it.
        /// A planche's line is horizontal, so filming from the front or back
        /// runs it straight down the depth axis — the one a monocular
        /// estimate can't measure (POSE.md Law 5). The clock doesn't care;
        /// the score does.
        var isMeasurable: Bool
    }

    /// Reads the geometry, or nil when the landmarks needed aren't there.
    static func read(_ pose: Pose) -> Reading? {
        guard let shoulder = midpoint(pose, .leftShoulder, .rightShoulder),
              let hip = midpoint(pose, .leftHip, .rightHip),
              let wrist = midpoint(pose, .leftWrist, .rightWrist)
        else { return nil }

        let torso = hip - shoulder
        let torsoLength = simd_length(torso)
        guard torsoLength > 0.15 else { return nil }

        // Which way the body points, in the horizontal plane: hips toward
        // shoulders with the vertical taken out. World y is the image's own
        // up/down axis, which is gravity for a phone stood up or laid on its
        // side — the same assumption the plumb-line overlay already makes.
        //
        // A body standing straight up has no forward direction at all, which
        // is why this returns nil there rather than a number made of noise.
        let along = SIMD3(shoulder.x - hip.x, 0, shoulder.z - hip.z)
        let alongLength = simd_length(along)
        guard alongLength > 0.05 else { return nil }
        let forward = along / alongLength

        let lean = simd_dot(shoulder - wrist, forward)
        let levelDeviation = asin(min(1, abs(torso.y) / torsoLength)) * 180 / .pi

        let ankle = midpoint(pose, .leftAnkle, .rightAnkle)
        let knee = angle(pose, at: .leftKnee, from: .leftHip, to: .leftAnkle)
        let hipAngle = angle(pose, at: .leftHip, from: .leftShoulder, to: .leftAnkle)

        return Reading(
            lean: lean,
            leanFraction: lean / torsoLength,
            levelDeviation: levelDeviation,
            straightness: (knee ?? 0) >= extendedKneeAngle ? hipAngle : nil,
            // World y runs downward, so floating above the hands is a
            // *smaller* y than theirs.
            feetAboveHands: ankle.map { (wrist.y - $0.y) / torsoLength },
            handDrop: (wrist.y - shoulder.y) / torsoLength,
            hipOffset: (hip.y - shoulder.y) / torsoLength,
            elbowAngle: angle(pose, at: .leftElbow, from: .leftShoulder, to: .leftWrist),
            isMeasurable: (pose.bodyLineDepthFraction ?? 0) <= 0.6
        )
    }

    /// Whether the body is in a planche right now.
    ///
    /// `lockedArms` is the one thing that differs between the two movements
    /// that use this. The static hold demands straight arms and the full
    /// hand-below-shoulder drop. The push-up can't: it bends the elbow and
    /// lowers the shoulders to hand height on every rep, and a gate that let
    /// go at the bottom would drop out exactly where the rep is decided —
    /// the mistake `DipTracker.isSupported` carries a comment about.
    static func isPlanchePosition(_ pose: Pose, lockedArms: Bool) -> Bool {
        guard let r = read(pose) else { return false }

        if lockedArms {
            guard let elbow = r.elbowAngle, elbow >= lockedElbowAngle else { return false }
        }

        // Hands underneath you, holding you up. Loose for the push-up, whose
        // shoulders descend to hand height and past it at the bottom.
        guard r.handDrop > (lockedArms ? 0.4 : -0.3) else { return false }

        // Roughly level. This is a wide bound, not a judgement — a planche
        // held badly is still a planche and gets timed and then scored
        // (Law 4). What it does reject is a body stacked upright over the
        // hands, which is a crow stand.
        guard r.levelDeviation < (lockedArms ? 45 : 55) else { return false }

        // The lean: shoulders out past the hands. This is the measurement the
        // movement is defined by — stay stacked over your wrists and it isn't
        // a planche — and it's what rejects a push-up (~0) and a decline
        // push-up (also ~0, despite being perfectly level with its feet up).
        guard r.leanFraction > 0.2 else { return false }

        // Feet in the air, measured against the hands — the pseudo planche
        // push-up rejection. A planche reads ~0.9 here and a pseudo planche
        // push-up ~0.16.
        //
        // Known limit, and an honest one: a floor planche sagging much past
        // 15° reads under this bar and stops being timed. At that point the
        // feet are about 10 cm off the floor and the shape genuinely is a
        // pseudo planche push-up — there is no measurement separating them,
        // because they have nearly stopped being different things.
        if let feetAboveHands = r.feetAboveHands {
            guard feetAboveHands > 0.4 else { return false }
        }
        return true
    }

    // MARK: - Primitives

    static func midpoint(_ pose: Pose, _ a: PoseJoint, _ b: PoseJoint) -> SIMD3<Double>? {
        guard let pa = pose.worldPoint(a), let pb = pose.worldPoint(b) else { return nil }
        return (pa + pb) / 2
    }

    /// Angle on whichever side is more visible — filmed side-on, one arm and
    /// one leg are occluded by the body essentially always.
    static func angle(
        _ pose: Pose, at vertex: PoseJoint, from first: PoseJoint, to second: PoseJoint
    ) -> Double? {
        let left = confidence(pose, vertex, first, second)
        let right = confidence(pose, vertex.mirrored, first.mirrored, second.mirrored)

        return left >= right
            ? pose.angle(at: vertex, from: first, to: second)
                ?? pose.angle(at: vertex.mirrored, from: first.mirrored, to: second.mirrored)
            : pose.angle(at: vertex.mirrored, from: first.mirrored, to: second.mirrored)
                ?? pose.angle(at: vertex, from: first, to: second)
    }

    static func confidence(_ pose: Pose, _ joints: PoseJoint...) -> Float {
        joints.reduce(Float(1)) { lowest, joint in
            let index = joint.rawValue
            guard index < pose.confidence.count else { return 0 }
            return min(lowest, pose.confidence[index])
        }
    }
}
