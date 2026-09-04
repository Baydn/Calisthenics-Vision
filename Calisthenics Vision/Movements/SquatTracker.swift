//
//  SquatTracker.swift
//  Calisthenics Vision
//
//  Squat rep counting. Measurement rules: POSE.md.
//
//  Same shape as the push-up: the finished position is the extended one, so a
//  rep counts on the way back up through standing. Dropping into a squat and
//  staying there never scores, and neither does standing up from a squat you
//  arrived in — a lockout has to be seen before the counter arms.
//
//  Gates are fractions into the person's own observed knee range rather than
//  fixed angles (POSE.md Law 3). Depth varies enormously with ankle mobility
//  and limb proportions, and a fixed "below parallel" rule counts nothing for
//  a tall person with stiff ankles who is squatting perfectly well for them.
//
//  Knees caving inward is the form check, because it's the one that matters
//  and the one that's actually visible: it compares knee separation to ankle
//  separation, which is a ratio and so survives any camera distance.
//

import CoreGraphics
import Foundation
import simd

struct SquatTracker: MovementTracker {

    /// Seeds, used only until the person's own range is known.
    var standAngle: Double = 168
    var bottomAngle: Double = 95

    /// Knee travel required before this is treated as squatting at all, so
    /// shifting your weight can't calibrate its way into counting.
    var minimumRange: Double = 40
    /// How far into your own range you must descend for the rep to count.
    /// Deliberately loose — depth coaching belongs in form feedback, not in
    /// withholding the count (POSE.md Law 4).
    var bottomGateFraction: Double = 0.42
    /// How close to standing re-arms the counter. Tighter, since this is what
    /// separates consecutive reps.
    var topGateFraction: Double = 0.25

    var minConfidence: Float = 0.5
    /// Form judgements need firmer evidence than counting does.
    var formConfidence: Float = 0.8
    /// Knees this much narrower than the ankles counts as caving. A little
    /// convergence is normal; this is set for the real fault.
    var valgusRatio: Double = 0.72
    /// ~0.4s at 30 FPS.
    var framesToFlag = 12

    private(set) var progress = MovementProgress()

    private enum Phase {
        /// Wait for a stand before counting, so arriving mid-squat isn't a
        /// free rep.
        case awaitingStand
        case standing, descending, bottom
    }
    private var phase: Phase = .awaitingStand
    private var badFormFrames = 0

    private(set) var isInPosition = false
    private(set) var isFormMeasurable = false
    private(set) var lastKneeAngle: Double?
    private(set) var lastHipAngle: Double?

    private(set) var observedMin: Double?
    private(set) var observedMax: Double?

    var observedRange: Double? {
        guard let observedMin, let observedMax else { return nil }
        return observedMax - observedMin
    }

    var isCalibrated: Bool { (observedRange ?? 0) >= minimumRange }

    var topThreshold: Double {
        guard isCalibrated, let observedMax, let range = observedRange else { return standAngle }
        return observedMax - range * topGateFraction
    }

    var bottomThreshold: Double {
        guard isCalibrated, let observedMin, let range = observedRange else { return bottomAngle }
        return observedMin + range * bottomGateFraction
    }

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isInPosition
        d.readyLabel = isInPosition ? "standing" : "not upright"
        d.primaryAngleLabel = "knee"
        d.primaryAngle = lastKneeAngle
        d.secondaryAngleLabel = "hip"
        d.secondaryAngle = lastHipAngle
        if !isCalibrated {
            d.note = "calibrating…"
            d.noteIsWarning = true
        } else {
            d.note = String(
                format: "gates %.0f°/%.0f° · form %@",
                bottomThreshold, topThreshold, isFormMeasurable ? "on" : "off"
            )
        }
        return d
    }

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose else {
            isInPosition = false
            lastKneeAngle = nil
            lastHipAngle = nil
            return nil
        }

        lastKneeAngle = kneeAngle(pose)
        lastHipAngle = hipAngle(pose)

        let upright = Self.isStandingUpright(pose)
        if upright != isInPosition {
            isInPosition = upright
            // Leaving position abandons a half-finished rep rather than
            // letting it complete when you come back.
            phase = .awaitingStand
            if !upright {
                badFormFrames = 0
                if !progress.isFormValid {
                    progress.isFormValid = true
                    return .formRecovered
                }
            }
        }
        guard upright, let knee = lastKneeAngle else { return nil }

        observeRange(knee)
        progress.repProgress = normalizedDepth(knee)

        if let event = checkForm(pose) { return event }
        return advance(knee: knee)
    }

    mutating func reset() {
        progress = MovementProgress()
        phase = .awaitingStand
        badFormFrames = 0
        observedMin = nil
        observedMax = nil
    }

    // MARK: - Calibration

    private mutating func observeRange(_ knee: Double) {
        let decay = 0.05                       // ≈1.5°/s at 30 FPS
        observedMax = max(knee, (observedMax ?? knee) - decay)
        observedMin = min(knee, (observedMin ?? knee) + decay)
    }

    // MARK: - Rep phases

    private mutating func advance(knee: Double) -> MovementEvent? {
        let top = topThreshold
        let bottom = bottomThreshold

        switch phase {
        case .awaitingStand:
            if isCalibrated, knee >= top { phase = .standing }

        case .standing:
            if knee < top - dwellMargin { phase = .descending }

        case .descending:
            if knee <= bottom {
                phase = .bottom
            } else if knee >= top {
                // Dipped and came back without reaching depth — not a rep.
                phase = .standing
            }

        case .bottom:
            if knee >= top {
                phase = .standing
                progress.reps += 1
                return .repCompleted(total: progress.reps)
            }
        }
        return nil
    }

    private var dwellMargin: Double {
        guard let range = observedRange, isCalibrated else { return 10 }
        return max(5, range * 0.1)
    }

    /// 0 standing, 1 at the bottom of your range.
    private func normalizedDepth(_ knee: Double) -> Double {
        let high = observedMax ?? standAngle
        let low = observedMin ?? bottomAngle
        let span = high - low
        guard span > 0 else { return 0 }
        return min(1, max(0, (high - knee) / span))
    }

    // MARK: - Form

    private mutating func checkForm(_ pose: Pose) -> MovementEvent? {
        let confidence = min(
            self.confidence(pose, .leftKnee, .rightKnee),
            self.confidence(pose, .leftAnkle, .rightAnkle)
        )

        // Filmed straight from the side, knee separation runs along the
        // camera axis and there's nothing trustworthy to measure (Law 5).
        let depthDominant = (pose.stanceDepthFraction ?? 0) > 0.6

        guard !depthDominant,
              confidence >= formConfidence,
              let ratio = valgus(pose)
        else {
            badFormFrames = 0
            isFormMeasurable = false
            if !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
            return nil
        }
        isFormMeasurable = true

        // Only judge it where it happens: knees track outward at the bottom,
        // and near lockout the ratio means nothing.
        let isDeep = progress.repProgress > 0.4
        let caving = isDeep && ratio < valgusRatio

        if caving {
            badFormFrames += 1
            if badFormFrames == framesToFlag {
                progress.isFormValid = false
                progress.formBreaks += 1
                return .formBreak(.kneeCave)
            }
        } else {
            badFormFrames = 0
            if !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
        }
        return nil
    }

    /// Knee separation ÷ ankle separation. A ratio rather than a distance, so
    /// it's the same number whatever size the person is or how far away the
    /// camera stands.
    func valgus(_ pose: Pose) -> Double? {
        guard let leftKnee = pose.worldPoint(.leftKnee),
              let rightKnee = pose.worldPoint(.rightKnee),
              let leftAnkle = pose.worldPoint(.leftAnkle),
              let rightAnkle = pose.worldPoint(.rightAnkle)
        else { return nil }

        let ankleGap = simd_length(leftAnkle - rightAnkle)
        guard ankleGap > 0.05 else { return nil }
        return simd_length(leftKnee - rightKnee) / ankleGap
    }

    // MARK: - Orientation

    /// Upright with the feet under you.
    ///
    /// This is what separates a squat from a push-up (torso horizontal) and
    /// from a hanging movement (feet above the hips). Measured from world
    /// landmarks, so it holds at any camera angle (POSE.md Law 1).
    static func isStandingUpright(_ pose: Pose) -> Bool {
        guard let shoulder = midpoint(pose, .leftShoulder, .rightShoulder),
              let hip = midpoint(pose, .leftHip, .rightHip),
              let ankle = midpoint(pose, .leftAnkle, .rightAnkle)
        else { return false }

        let torso = hip - shoulder
        let length = simd_length(torso)
        guard length > 0.01, abs(torso.y) / length > 0.7 else { return false }

        // World y runs downward, so feet below the hips means a larger y.
        return ankle.y > hip.y + 0.15
    }

    private static func midpoint(_ pose: Pose, _ a: PoseJoint, _ b: PoseJoint) -> SIMD3<Double>? {
        guard let pa = pose.worldPoint(a), let pb = pose.worldPoint(b) else { return nil }
        return (pa + pb) / 2
    }

    // MARK: - Measurements

    /// Knee angle from whichever leg is more visible.
    private func kneeAngle(_ pose: Pose) -> Double? {
        let left = confidence(pose, .leftHip, .leftKnee, .leftAnkle)
        let right = confidence(pose, .rightHip, .rightKnee, .rightAnkle)
        guard max(left, right) >= minConfidence else { return nil }

        return left >= right
            ? pose.angle(at: .leftKnee, from: .leftHip, to: .leftAnkle)
            : pose.angle(at: .rightKnee, from: .rightHip, to: .rightAnkle)
    }

    /// Shoulder-hip-knee — how far the torso folds. Reported for diagnostics
    /// rather than judged: a squat legitimately involves a lot of hinge.
    private func hipAngle(_ pose: Pose) -> Double? {
        let left = confidence(pose, .leftShoulder, .leftHip, .leftKnee)
        let right = confidence(pose, .rightShoulder, .rightHip, .rightKnee)
        guard max(left, right) >= minConfidence else { return nil }

        return left >= right
            ? pose.angle(at: .leftHip, from: .leftShoulder, to: .leftKnee)
            : pose.angle(at: .rightHip, from: .rightShoulder, to: .rightKnee)
    }

    private func confidence(_ pose: Pose, _ joints: PoseJoint...) -> Float {
        joints.reduce(Float(1)) { lowest, joint in
            let index = joint.rawValue
            guard index < pose.confidence.count else { return 0 }
            return min(lowest, pose.confidence[index])
        }
    }
}
