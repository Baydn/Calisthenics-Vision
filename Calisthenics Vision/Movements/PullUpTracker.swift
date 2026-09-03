//
//  PullUpTracker.swift
//  Calisthenics Vision
//
//  Pull-up rep counting. Measurement rules: POSE.md.
//
//  Mirror image of the push-up, and the mirroring matters. A push-up's
//  finished position is the *extended* one, so it counts at lockout. A
//  pull-up's finished position is the *flexed* one, so it counts at the top —
//  which is also when a person expects to hear the number.
//
//  State machine: HANG (extended) -> ASCENDING -> TOP counts one rep, and the
//  arms must return towards extension before another can count. Dropping from
//  the top without having hung first never scores.
//
//  Gates are fractions into the person's own observed elbow range, never
//  fixed angles (POSE.md Law 3), and they are deliberately loose: a beginner
//  pulling two thirds of the way up is doing pull-ups, and refusing to count
//  them reads as a broken app (Law 4). Chin-over-bar is measured and scored
//  instead.
//

import CoreGraphics
import Foundation
import simd

struct PullUpTracker: MovementTracker {

    /// Nominal gates, used only until the person's own range is known.
    var hangAngle: Double = 165
    var topAngle: Double = 70

    /// Total elbow travel before the motion is treated as a rep at all, so
    /// shifting grip on the bar can't calibrate its way into counting.
    var minimumRange: Double = 40
    /// How far into your own range you must pull for the rep to count.
    /// Loose on purpose — depth coaching belongs in form feedback, not in
    /// withholding the count.
    var topGateFraction: Double = 0.42
    /// How close to a dead hang re-arms the counter. Tighter, because this is
    /// what separates consecutive reps.
    var hangGateFraction: Double = 0.25

    var minConfidence: Float = 0.5
    /// Form judgements need firmer evidence than counting does.
    var formConfidence: Float = 0.8
    /// Deviation from a straight body before the legs are called out. Generous:
    /// a little swing is normal and only a real kip is worth mentioning.
    var maxHipDeviation: Double = 35
    /// ~0.4s at 30 FPS.
    var framesToFlag = 12
    /// Above this share of the body line running along the camera axis,
    /// posture isn't measurable well enough to comment on (POSE.md Law 5).
    var maxBodyLineDepth: Double = 0.6

    private(set) var progress = MovementProgress()

    private enum Phase {
        /// Just arrived — wait for a hang before counting anything, so
        /// jumping up to the bar isn't a free rep.
        case awaitingHang
        case hanging, ascending, top
    }
    private var phase: Phase = .awaitingHang
    private var badFormFrames = 0

    private(set) var isOnBar = false
    private(set) var isFormMeasurable = false
    private(set) var lastElbowAngle: Double?
    private(set) var lastHipAngle: Double?

    private(set) var observedMin: Double?
    private(set) var observedMax: Double?

    var observedRange: Double? {
        guard let observedMin, let observedMax else { return nil }
        return observedMax - observedMin
    }

    var isCalibrated: Bool { (observedRange ?? 0) >= minimumRange }

    /// At or above this the arms count as hung.
    var hangThreshold: Double {
        guard isCalibrated, let observedMax, let range = observedRange else {
            return hangAngle
        }
        return observedMax - range * hangGateFraction
    }

    /// At or below this the pull counts as high enough.
    var topThreshold: Double {
        guard isCalibrated, let observedMin, let range = observedRange else {
            return topAngle
        }
        return observedMin + range * topGateFraction
    }

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isOnBar
        d.readyLabel = isOnBar ? "hanging" : "not on the bar"
        d.primaryAngleLabel = "elbow"
        d.primaryAngle = lastElbowAngle
        d.secondaryAngleLabel = "hip"
        d.secondaryAngle = lastHipAngle
        if !isCalibrated {
            d.note = "calibrating…"
            d.noteIsWarning = true
        } else {
            d.note = String(
                format: "gates %.0f°/%.0f° · form %@",
                topThreshold, hangThreshold, isFormMeasurable ? "on" : "off"
            )
        }
        return d
    }

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose else {
            isOnBar = false
            lastElbowAngle = nil
            lastHipAngle = nil
            return nil
        }

        lastElbowAngle = elbowAngle(pose)
        lastHipAngle = hipAlignment(pose)

        let onBar = Self.isHanging(pose)
        if onBar != isOnBar {
            isOnBar = onBar
            // Leaving the bar abandons a half-finished rep rather than
            // letting it complete next time you jump up.
            phase = .awaitingHang
            if !onBar {
                badFormFrames = 0
                if !progress.isFormValid {
                    progress.isFormValid = true
                    return .formRecovered
                }
            }
        }
        guard onBar, let elbow = lastElbowAngle else { return nil }

        observeRange(elbow)
        progress.repProgress = normalizedHeight(elbow)

        if let event = checkForm(pose) { return event }
        return advance(elbow: elbow)
    }

    mutating func reset() {
        progress = MovementProgress()
        phase = .awaitingHang
        badFormFrames = 0
        observedMin = nil
        observedMax = nil
    }

    // MARK: - Calibration

    private mutating func observeRange(_ elbow: Double) {
        let decay = 0.05                       // ≈1.5°/s at 30 FPS
        observedMax = max(elbow, (observedMax ?? elbow) - decay)
        observedMin = min(elbow, (observedMin ?? elbow) + decay)
    }

    // MARK: - Rep phases

    private mutating func advance(elbow: Double) -> MovementEvent? {
        let hang = hangThreshold
        let top = topThreshold

        switch phase {
        case .awaitingHang:
            if isCalibrated, elbow >= hang { phase = .hanging }

        case .hanging:
            // Require a clear departure, so jitter sitting on the gate can't
            // start a rep.
            if elbow < hang - dwellMargin { phase = .ascending }

        case .ascending:
            if elbow <= top {
                // Counted here rather than on the way down: the top is the
                // finished position of a pull-up, and it's when you expect
                // to hear the number.
                phase = .top
                progress.reps += 1
                return .repCompleted(total: progress.reps)
            } else if elbow >= hang {
                // Sank back without pulling high enough — not a rep.
                phase = .hanging
            }

        case .top:
            // Must come back down before another can count, so bobbing at
            // the top doesn't rack up reps.
            if elbow >= hang { phase = .hanging }
        }
        return nil
    }

    private var dwellMargin: Double {
        guard let range = observedRange, isCalibrated else { return 10 }
        return max(5, range * 0.1)
    }

    /// 0 at a dead hang, 1 at the top of your range.
    private func normalizedHeight(_ elbow: Double) -> Double {
        let high = observedMax ?? hangAngle
        let low = observedMin ?? topAngle
        let span = high - low
        guard span > 0 else { return 0 }
        return min(1, max(0, (high - elbow) / span))
    }

    // MARK: - Form

    private mutating func checkForm(_ pose: Pose) -> MovementEvent? {
        // Knees are frequently out of frame on a bar, and MediaPipe will
        // happily extrapolate one. Judging a kip off a guessed knee produces
        // exactly the confident-but-wrong warning that makes the feature
        // untrustworthy.
        let kneeConfidence = max(
            confidence(pose, .leftKnee),
            confidence(pose, .rightKnee)
        )
        let depthDominant = (pose.bodyLineDepthFraction ?? 0) > maxBodyLineDepth

        guard !depthDominant,
              kneeConfidence >= formConfidence,
              let hip = lastHipAngle
        else {
            badFormFrames = 0
            isFormMeasurable = false
            // An unmeasurable pose isn't a failing one.
            if !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
            return nil
        }
        isFormMeasurable = true

        // A hanging body reads ~180° at the hip; folding means the knees are
        // coming up, which is the classic kip.
        let kipping = abs(180 - hip) > maxHipDeviation

        if kipping {
            badFormFrames += 1
            if badFormFrames == framesToFlag {
                progress.isFormValid = false
                progress.formBreaks += 1
                return .formBreak(.kipping)
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

    // MARK: - Orientation

    /// Hanging when the body is upright and both wrists are above the
    /// shoulders.
    ///
    /// World y runs downward, so "above" is a smaller y. This is measured
    /// from world landmarks, so it holds at any camera angle (POSE.md Law 1).
    ///
    /// Known limit: an overhead press has the same geometry. Distinguishing
    /// them isn't possible from joint positions alone, and it isn't worth
    /// guessing at — someone pressing overhead with the movement set to
    /// Pull-Ups is not a case worth breaking real pull-ups to catch.
    static func isHanging(_ pose: Pose) -> Bool {
        guard let shoulder = midpoint(pose, .leftShoulder, .rightShoulder),
              let wrist = midpoint(pose, .leftWrist, .rightWrist),
              let hip = midpoint(pose, .leftHip, .rightHip)
        else { return false }

        // Upright: the torso must run along the vertical rather than across
        // it, which rules out counting push-ups as pull-ups.
        let torso = hip - shoulder
        let length = simd_length(torso)
        guard length > 0.01, abs(torso.y) / length > 0.7 else { return false }

        // Hands overhead, by a real margin so noise can't trip it.
        return shoulder.y - wrist.y > 0.15
    }

    private static func midpoint(_ pose: Pose, _ a: PoseJoint, _ b: PoseJoint) -> SIMD3<Double>? {
        guard let pa = pose.worldPoint(a), let pb = pose.worldPoint(b) else { return nil }
        return (pa + pb) / 2
    }

    // MARK: - Measurements

    /// Elbow angle from whichever arm is more visible.
    private func elbowAngle(_ pose: Pose) -> Double? {
        let left = confidence(pose, .leftShoulder, .leftElbow, .leftWrist)
        let right = confidence(pose, .rightShoulder, .rightElbow, .rightWrist)
        guard max(left, right) >= minConfidence else { return nil }

        return left >= right
            ? pose.angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)
            : pose.angle(at: .rightElbow, from: .rightShoulder, to: .rightWrist)
    }

    /// Shoulder-hip-knee angle — straight while hanging, folded while kipping.
    private func hipAlignment(_ pose: Pose) -> Double? {
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
