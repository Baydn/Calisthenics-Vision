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

    // Thresholds from SPEC.md §2.
    var lockoutAngle: Double = 160
    var bottomAngle: Double = 90
    var maxHipDeviation: Double = 15

    /// Landmarks below this confidence are ignored — an occluded arm reports
    /// a position, just not a trustworthy one.
    var minConfidence: Float = 0.5

    private(set) var progress = MovementProgress()

    private enum Phase { case top, descending, bottom }
    private var phase: Phase = .top
    /// Form must be bad for a few consecutive frames before it counts, so one
    /// noisy landmark doesn't fire a false warning.
    private var badFormFrames = 0
    private var framesToFlag = 5

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose, let elbow = elbowAngle(pose) else { return nil }

        progress.repProgress = normalizedDepth(elbow)

        if let event = checkForm(pose) { return event }
        return advance(elbow: elbow)
    }

    mutating func reset() {
        progress = MovementProgress()
        phase = .top
        badFormFrames = 0
    }

    // MARK: - Rep phases

    private mutating func advance(elbow: Double) -> MovementEvent? {
        switch phase {
        case .top:
            // Require a clear departure from lockout before we believe a rep
            // has started; jitter right at the threshold shouldn't advance us.
            if elbow < lockoutAngle - 10 { phase = .descending }

        case .descending:
            if elbow <= bottomAngle {
                phase = .bottom
            } else if elbow >= lockoutAngle {
                // Went back up without reaching depth — not a rep.
                phase = .top
            }

        case .bottom:
            if elbow >= lockoutAngle {
                phase = .top
                progress.reps += 1
                return .repCompleted(total: progress.reps)
            }
        }
        return nil
    }

    /// 0 at lockout, 1 at full depth.
    private func normalizedDepth(_ elbow: Double) -> Double {
        let span = lockoutAngle - bottomAngle
        guard span > 0 else { return 0 }
        return min(1, max(0, (lockoutAngle - elbow) / span))
    }

    // MARK: - Form

    private mutating func checkForm(_ pose: Pose) -> MovementEvent? {
        guard let hip = hipAlignment(pose) else { return nil }

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
