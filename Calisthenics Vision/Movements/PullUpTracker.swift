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

    /// Where the counting line sits, as a fraction of the meter's bar — a
    /// *standard*, known before you've moved, so the line is on screen from
    /// the first frame of the recording. See `PushUpTracker`.
    var standardDepthFraction: Double = 0.80

    /// How close to your own measured bottom counts, in degrees. Applies
    /// *only* where a rep has shown the standard is out of reach, which is
    /// what stops a short range counting nothing (Law 3). Everyone else is
    /// judged against the line they can see. See `PushUpTracker`.
    var depthTolerance: Double = 15

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
    /// Last angle fed to `observeRange`, to tell moving from holding still.
    private var lastRangeAngle: Double?

    /// Extremes of the rep currently under way, and the range a *completed*
    /// rep showed us — which is what the gates use once there is one.
    ///
    /// Learning it from every frame on the bar let hanging about set the
    /// range: see `PushUpTracker` for the bug and why a finished rep is the
    /// honest sample. The first one sets the range and it then holds.
    private var repMin: Double?
    private var repMax: Double?
    private var settledMin: Double?
    private var settledMax: Double?

    var observedRange: Double? {
        guard let observedMin, let observedMax else { return nil }
        return observedMax - observedMin
    }

    var settledRange: Double? {
        guard let settledMin, let settledMax else { return nil }
        return settledMax - settledMin
    }

    /// True once a completed rep has defined the range.
    var isSettled: Bool { settledRange != nil }

    var isCalibrated: Bool { (observedRange ?? 0) >= minimumRange }

    /// The range the gates are computed from.
    var workingRange: Double? { settledRange ?? (isCalibrated ? observedRange : nil) }

    /// At or above this the arms count as hung.
    var hangThreshold: Double {
        if let settledMax, let range = settledRange {
            return settledMax - range * hangGateFraction
        }
        guard isCalibrated, let observedMax, let range = observedRange else {
            return hangAngle
        }
        return observedMax - range * hangGateFraction
    }

    /// At or below this the pull counts as high enough.
    var topThreshold: Double {
        guard let settledMin, settledMin > standardDepthAngle else {
            return standardDepthAngle
        }
        return settledMin + depthTolerance
    }

    /// Ends of the meter's scale: a dead hang at one end, chin over the bar
    /// at the other. Drawing bounds, not gates (see `DepthGauge`).
    var extendedAngle: Double = 180
    var pulledAngle: Double = 45

    /// Drawn rising rather than falling: a pull-up's "deep" is its top, and a
    /// bar that filled downward while the body went up would read backwards.
    var depthGauge: DepthGauge? {
        DepthGauge(
            depth: (isOnBar ? lastElbowAngle : nil).map(onScale),
            countsAt: onScale(topThreshold),
            risesOnScreen: true
        )
    }

    /// The angle the standard sits at, from the fraction of the bar it's
    /// drawn at.
    var standardDepthAngle: Double {
        extendedAngle - standardDepthFraction * (extendedAngle - pulledAngle)
    }

    /// See `MovementTracker.depthGauge(for:)` — the replay's meter.
    func depthGauge(for pose: Pose) -> DepthGauge? {
        guard Self.isHanging(pose), let elbow = elbowAngle(pose) else { return nil }
        return DepthGauge(
            depth: onScale(elbow),
            countsAt: onScale(standardDepthAngle),
            risesOnScreen: true
        )
    }

    private func onScale(_ angle: Double) -> Double {
        let span = extendedAngle - pulledAngle
        guard span > 0 else { return 0 }
        return min(1, max(0, (extendedAngle - angle) / span))
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
        repMin = min(elbow, repMin ?? elbow)
        repMax = max(elbow, repMax ?? elbow)
        settleDepth(reaching: elbow)
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
        lastRangeAngle = nil
        repMin = nil
        repMax = nil
        settledMin = nil
        settledMax = nil
    }

    // MARK: - Calibration

    /// Decay runs only while you're moving, and floors at `minimumRange`:
    /// hanging still is not evidence about your range, and letting
    /// it collapse un-learns the person mid-set. See
    /// `PushUpTracker.observeRange` for the bug this fixes.
    private mutating func observeRange(_ elbow: Double) {
        let moved = abs(elbow - (lastRangeAngle ?? elbow)) > 0.5
        lastRangeAngle = elbow

        let slack = (observedRange ?? 0) - minimumRange
        let decay = moved && slack > 0 ? min(0.05, slack / 2) : 0     // ≈1.5°/s at 30 FPS
        observedMax = max(elbow, (observedMax ?? elbow) - decay)
        observedMin = min(elbow, (observedMin ?? elbow) + decay)
    }

    // MARK: - Rep phases

    private mutating func advance(elbow: Double) -> MovementEvent? {
        let hang = hangThreshold
        let top = topThreshold

        switch phase {
        case .awaitingHang:
            // Arming can't wait for calibration: the observed range only
            // grows once you move. See `PushUpTracker.advance`.
            if elbow >= hangAngle || (isCalibrated && elbow >= hang) {
                enterHang(at: elbow)
            }

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
                enterHang(at: elbow)
            }

        case .top:
            // Must come back down before another can count, so bobbing at
            // the top doesn't rack up reps.
            if elbow >= hang {
                settleTop(elbow)
                enterHang(at: elbow)
            }
        }
        return nil
    }

    /// Sets the target at the top of the first pull, the moment the elbow
    /// turns around and starts back down. See `PushUpTracker.settleDepth`.
    private mutating func settleDepth(reaching elbow: Double) {
        guard let low = repMin, let high = repMax,
              high - low >= minimumRange,
              low < (settledMin ?? .infinity),
              elbow > low + 2
        else { return }

        settledMin = low
        settledMax = high
    }

    /// The hang the last rep actually returned to. Keeps adapting, unlike the
    /// target, because nothing draws it. See `PushUpTracker.settleTop`.
    private mutating func settleTop(_ elbow: Double) {
        let high = max(repMax ?? elbow, elbow)
        guard let low = settledMin, high - low >= minimumRange else { return }
        settledMax = high
    }

    /// Returning to the hang opens the window the next rep's range is
    /// measured over. It starts here rather than when the pull is detected,
    /// which only happens once the dwell margin has already been travelled.
    private mutating func enterHang(at elbow: Double) {
        phase = .hanging
        repMin = elbow
        repMax = elbow
    }

    private var dwellMargin: Double {
        guard let range = workingRange else { return 10 }
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
