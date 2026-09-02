//
//  PushUpTracker.swift
//  Calisthenics Vision
//
//  Push-up rep counting (SPEC.md §2).
//
//  State machine: TOP (elbow ≥160°) → BOTTOM (≤90°) → TOP counts one rep.
//  A rep only counts on the way back up through lockout, so descending
//  halfway and giving up never scores.
//
//  Hip sag: if the shoulder-hip-ankle line bends more than 15° off straight,
//  form is flagged.
//

import CoreGraphics
import Foundation

struct PushUpTracker: MovementTracker {

    // Nominal thresholds from SPEC.md §2. These are the *starting* values; once
    // enough motion has been seen the tracker calibrates to the person's own
    // range instead (see `topThreshold`/`bottomThreshold`).
    //
    // Fixed angles don't survive contact with real bodies: arm proportions,
    // how far someone locks out, how deep they go, and the residual error in a
    // 3D landmark estimate all shift the numbers. Demanding a literal 160°
    // lockout means a person whose arms read 150° at the top counts zero reps
    // forever, which is precisely the failure this replaces.
    var lockoutAngle: Double = 160
    var bottomAngle: Double = 90
    var maxHipDeviation: Double = 15

    /// Total elbow travel required before the motion is treated as a rep at
    /// all, so fidgeting in position can't calibrate its way into counting.
    var minimumRange: Double = 45
    /// How far down into the range you must travel for the rep to count, as a
    /// fraction of your own range. Deliberately loose: demanding near-maximum
    /// depth every rep means a beginner sees nothing counted at all, and an
    /// uncounted rep reads as "the app is broken" rather than "go deeper".
    /// Depth coaching belongs in form feedback, not in withholding the count.
    var bottomGateFraction: Double = 0.42
    /// How close to full extension counts as locked out. Tighter than the
    /// bottom gate, since the top of a push-up is unambiguous and this is what
    /// separates consecutive reps.
    var topGateFraction: Double = 0.25

    /// Landmarks below this confidence are ignored — an occluded arm reports
    /// a position, just not a trustworthy one.
    var minConfidence: Float = 0.5
    /// Form judgements need firmer evidence than rep counting does.
    var formConfidence: Float = 0.8
    /// Above this share of the body line lying along the camera axis, posture
    /// is not measurable well enough to comment on.
    var maxBodyLineDepth: Double = 0.6

    private(set) var progress = MovementProgress()

    private enum Phase {
        /// Just entered position — wait for a lockout before counting anything,
        /// so dropping in already at the bottom and pressing up isn't a rep.
        case awaitingLockout
        case top, descending, bottom
    }
    private var phase: Phase = .awaitingLockout
    /// Form must be bad for a few consecutive frames before it counts, so one
    /// noisy landmark doesn't fire a false warning.
    private var badFormFrames = 0
    /// ~0.4s at 30 FPS. Long enough that transient landmark noise during the
    /// fast part of a rep doesn't register as sagging.
    private var framesToFlag = 12

    /// Whether the body is oriented like a push-up right now, exposed so the
    /// HUD can explain why nothing is being counted.
    private(set) var isInPosition = false

    /// Whether posture can currently be judged at all. False when the camera
    /// is end-on to the body or the legs aren't visible — reps still count.
    private(set) var isFormMeasurable = false

    /// Latest measurements, for on-device diagnostics.
    private(set) var lastElbowAngle: Double?
    private(set) var lastHipAngle: Double?

    /// Elbow extremes seen so far, and the resulting gates. Surfaced so the
    /// HUD can show why something is or isn't counting.
    private(set) var observedMin: Double?
    private(set) var observedMax: Double?

    var observedRange: Double? {
        guard let observedMin, let observedMax else { return nil }
        return observedMax - observedMin
    }

    /// True once enough travel has been seen to trust the person's own range.
    var isCalibrated: Bool { (observedRange ?? 0) >= minimumRange }

    /// Angle at or above which the arm counts as extended.
    var topThreshold: Double {
        guard isCalibrated, let observedMax, let range = observedRange else {
            return lockoutAngle
        }
        return observedMax - range * topGateFraction
    }

    /// Angle at or below which the rep counts as deep enough.
    var bottomThreshold: Double {
        guard isCalibrated, let observedMin, let range = observedRange else {
            return bottomAngle
        }
        return observedMin + range * bottomGateFraction
    }

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose else {
            isInPosition = false
            lastElbowAngle = nil
            lastHipAngle = nil
            return nil
        }

        lastElbowAngle = elbowAngle(pose)
        lastHipAngle = pose.angle(at: .leftHip, from: .leftShoulder, to: .leftAnkle)
            ?? pose.angle(at: .rightHip, from: .rightShoulder, to: .rightAnkle)

        // Only judge a push-up when the body is actually in one. Standing and
        // bending your arms sweeps the same elbow range as a rep, so without
        // this gate arm-waving counts as push-ups.
        let horizontal = pose.isTorsoHorizontal ?? false
        if horizontal != isInPosition {
            isInPosition = horizontal
            // Leaving position abandons any half-finished rep rather than
            // letting it complete the next time you lie down.
            // Re-entering position must start from a lockout, not mid-rep.
            phase = .awaitingLockout
            if !horizontal {
                badFormFrames = 0
                if !progress.isFormValid {
                    progress.isFormValid = true
                    return .formRecovered
                }
            }
        }
        guard horizontal, let elbow = lastElbowAngle else { return nil }

        observeRange(elbow)
        progress.repProgress = normalizedDepth(elbow)

        if let event = checkForm(pose) { return event }
        return advance(elbow: elbow)
    }

    mutating func reset() {
        progress = MovementProgress()
        phase = .awaitingLockout
        badFormFrames = 0
        observedMin = nil
        observedMax = nil
    }

    // MARK: - Calibration

    /// Widens the observed range, letting stale extremes decay slowly so one
    /// unusually deep rep — or a bad frame — doesn't set the gates forever.
    private mutating func observeRange(_ elbow: Double) {
        let decay = 0.05                       // ≈1.5°/s at 30 FPS
        observedMax = max(elbow, (observedMax ?? elbow) - decay)
        observedMin = min(elbow, (observedMin ?? elbow) + decay)
    }

    // MARK: - Rep phases

    private mutating func advance(elbow: Double) -> MovementEvent? {
        let top = topThreshold
        let bottom = bottomThreshold

        switch phase {
        case .awaitingLockout:
            // Needs calibration first, so the very first motion establishes
            // the range rather than being judged against a guess.
            if isCalibrated, elbow >= top { phase = .top }

        case .top:
            // Require a clear departure before believing a rep has started;
            // jitter sitting on the gate shouldn't advance us.
            if elbow < top - dwellMargin { phase = .descending }

        case .descending:
            if elbow <= bottom {
                phase = .bottom
            } else if elbow >= top {
                // Went back up without reaching depth — not a rep.
                phase = .top
            }

        case .bottom:
            if elbow >= top {
                phase = .top
                progress.reps += 1
                return .repCompleted(total: progress.reps)
            }
        }
        return nil
    }

    /// Dead band around a gate, scaled to the person's range so it means the
    /// same thing whether they travel 50° or 100°.
    private var dwellMargin: Double {
        guard let range = observedRange, isCalibrated else { return 10 }
        return max(5, range * 0.1)
    }

    /// 0 at the top of the range, 1 at full depth.
    private func normalizedDepth(_ elbow: Double) -> Double {
        let high = observedMax ?? lockoutAngle
        let low = observedMin ?? bottomAngle
        let span = high - low
        guard span > 0 else { return 0 }
        return min(1, max(0, (high - elbow) / span))
    }

    // MARK: - Form

    private mutating func checkForm(_ pose: Pose) -> MovementEvent? {
        // Legs are frequently cropped out or occluded when the phone is close,
        // and MediaPipe still emits an extrapolated ankle. Judging form off a
        // guessed landmark produces exactly the false "fix your hips" warning
        // that makes the feature untrustworthy, so demand real confidence here
        // — higher than for counting, since a wrong warning is worse than a
        // missing one.
        let ankleConfidence = max(
            confidence(pose, .leftAnkle),
            confidence(pose, .rightAnkle)
        )

        // Facing the camera, the body line runs into depth — the one axis a
        // monocular estimate can't measure well — so straightness there is
        // guesswork dressed up as a number. Counting reps still works (elbow
        // flexion is measured across the body, not along it); judging posture
        // does not, so say nothing rather than something wrong.
        let depthDominant = (pose.bodyLineDepthFraction ?? 0) > maxBodyLineDepth

        guard !depthDominant,
              ankleConfidence >= formConfidence,
              let hip = hipAlignment(pose)
        else {
            badFormFrames = 0
            isFormMeasurable = false
            // Don't leave the skeleton stuck red once we can no longer tell:
            // an unmeasurable pose is not a failing one.
            if !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
            return nil
        }
        isFormMeasurable = true

        // A straight body reads ~180° at the hip; deviation either way is a sag
        // or a pike.
        let sagging = abs(180 - hip) > maxHipDeviation

        if sagging {
            badFormFrames += 1
            if badFormFrames == framesToFlag {
                progress.isFormValid = false
                progress.formBreaks += 1
                return .formBreak(.hipSag)
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

    // MARK: - Measurements

    /// Elbow angle from whichever arm is more visible — filming side-on means
    /// one arm is usually occluded by the body.
    private func elbowAngle(_ pose: Pose) -> Double? {
        let left = confidence(pose, .leftShoulder, .leftElbow, .leftWrist)
        let right = confidence(pose, .rightShoulder, .rightElbow, .rightWrist)

        let useLeft = left >= right
        let best = max(left, right)
        guard best >= minConfidence else { return nil }

        return useLeft
            ? pose.angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)
            : pose.angle(at: .rightElbow, from: .rightShoulder, to: .rightWrist)
    }

    /// Shoulder-hip-ankle angle on the more visible side.
    private func hipAlignment(_ pose: Pose) -> Double? {
        let left = confidence(pose, .leftShoulder, .leftHip, .leftAnkle)
        let right = confidence(pose, .rightShoulder, .rightHip, .rightAnkle)

        let useLeft = left >= right
        guard max(left, right) >= minConfidence else { return nil }

        return useLeft
            ? pose.angle(at: .leftHip, from: .leftShoulder, to: .leftAnkle)
            : pose.angle(at: .rightHip, from: .rightShoulder, to: .rightAnkle)
    }

    /// Weakest landmark in the chain — a joint triple is only as trustworthy
    /// as its least visible point.
    private func confidence(_ pose: Pose, _ joints: PoseJoint...) -> Float {
        joints.reduce(Float(1)) { lowest, joint in
            let index = joint.rawValue
            guard index < pose.confidence.count else { return 0 }
            return min(lowest, pose.confidence[index])
        }
    }
}
