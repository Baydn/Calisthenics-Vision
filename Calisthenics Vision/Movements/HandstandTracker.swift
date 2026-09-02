//
//  HandstandTracker.swift
//  Calisthenics Vision
//
//  Handstand hold timing (SPEC.md §2).
//
//  Unlike a push-up this counts nothing — it accumulates time, and only while
//  the hold is genuinely valid. Two conditions must both hold: the body is
//  inverted, and the wrist-shoulder-hip-ankle line is straight enough.
//
//  Time only accrues frame to frame, so losing the pose mid-hold pauses the
//  clock rather than silently crediting the gap.
//

import Foundation
import simd

struct HandstandTracker: MovementTracker {

    /// Minimum angle at the shoulder and hip for the line to count as straight.
    var minAlignment: Double = 165
    /// Landmarks below this are ignored — an unreliable point shouldn't end
    /// a hold that is actually fine.
    var minConfidence: Float = 0.5
    /// Alignment must fail for this long before it's called a break, so a
    /// wobble doesn't end an otherwise good hold. ~0.4s at 30 FPS.
    var framesToFlag = 12
    /// Gap beyond which we assume tracking was lost rather than time passing.
    var maxFrameGapMs = 500

    private(set) var progress = MovementProgress()

    private(set) var isInverted = false
    private(set) var shoulderAngle: Double?
    private(set) var hipAngle: Double?

    private var lastTimestampMs: Int?
    private var badFormFrames = 0
    private var lastWholeSecond = 0

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isInverted
        d.readyLabel = isInverted ? "inverted" : "not inverted"
        d.primaryAngleLabel = "shoulder"
        d.primaryAngle = shoulderAngle
        d.secondaryAngleLabel = "hip"
        d.secondaryAngle = hipAngle
        if !isInverted {
            d.note = "waiting for inversion"
            d.noteIsWarning = true
        } else {
            d.note = progress.isFormValid ? "holding" : "line lost"
            d.noteIsWarning = !progress.isFormValid
        }
        return d
    }

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose else {
            // Losing the pose pauses the clock: resuming shouldn't credit the
            // time spent out of frame.
            lastTimestampMs = nil
            isInverted = false
            shoulderAngle = nil
            hipAngle = nil
            return nil
        }

        shoulderAngle = alignment(pose, at: .leftShoulder, from: .leftWrist, to: .leftHip,
                                  mirror: (.rightShoulder, .rightWrist, .rightHip))
        hipAngle = alignment(pose, at: .leftHip, from: .leftShoulder, to: .leftAnkle,
                             mirror: (.rightHip, .rightShoulder, .rightAnkle))

        let inverted = Self.isInverted(pose)
        let wasInverted = isInverted
        isInverted = inverted

        guard inverted else {
            lastTimestampMs = nil
            badFormFrames = 0
            if wasInverted && !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
            return nil
        }

        let aligned = isAligned
        let event = updateFormState(aligned: aligned)

        // Accrue time only across a plausible frame gap while the hold is good.
        defer { lastTimestampMs = timestampMs }
        guard aligned, let previous = lastTimestampMs else { return event }

        let delta = timestampMs - previous
        guard delta > 0, delta <= maxFrameGapMs else { return event }

        progress.holdDuration += Double(delta) / 1000

        if let event { return event }

        let whole = Int(progress.holdDuration)
        if whole > lastWholeSecond {
            lastWholeSecond = whole
            return .holdTick(seconds: whole)
        }
        return nil
    }

    mutating func reset() {
        progress = MovementProgress()
        isInverted = false
        shoulderAngle = nil
        hipAngle = nil
        lastTimestampMs = nil
        badFormFrames = 0
        lastWholeSecond = 0
    }

    // MARK: - Conditions

    private var isAligned: Bool {
        guard let shoulderAngle, let hipAngle else { return false }
        return shoulderAngle >= minAlignment && hipAngle >= minAlignment
    }

    private mutating func updateFormState(aligned: Bool) -> MovementEvent? {
        if aligned {
            badFormFrames = 0
            if !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
        } else {
            badFormFrames += 1
            if badFormFrames == framesToFlag {
                progress.isFormValid = false
                progress.formBreaks += 1
                return .formBreak(.lostAlignment)
            }
        }
        return nil
    }

    /// Inverted when the ankles sit above the shoulders.
    ///
    /// World-space y runs downward, matching the image, so "above" means a
    /// smaller y. Comparing ankles to shoulders rather than checking wrist
    /// height keeps this true whatever angle the camera is at — the whole
    /// point of working in 3D (SPEC.md §1).
    static func isInverted(_ pose: Pose) -> Bool {
        guard let shoulder = midpoint(pose, .leftShoulder, .rightShoulder),
              let ankle = midpoint(pose, .leftAnkle, .rightAnkle),
              let hip = midpoint(pose, .leftHip, .rightHip)
        else { return false }

        // Require a real vertical separation so someone lying flat, where the
        // ordering is near-arbitrary, doesn't read as a handstand.
        let span = abs(shoulder.y - ankle.y)
        guard span > 0.3 else { return false }

        return ankle.y < hip.y && hip.y < shoulder.y
    }

    private static func midpoint(_ pose: Pose, _ a: PoseJoint, _ b: PoseJoint) -> SIMD3<Double>? {
        guard let pa = pose.worldPoint(a), let pb = pose.worldPoint(b) else { return nil }
        return (pa + pb) / 2
    }

    // MARK: - Measurement

    /// Angle on whichever side is more visible.
    private func alignment(
        _ pose: Pose,
        at vertex: PoseJoint, from first: PoseJoint, to second: PoseJoint,
        mirror: (PoseJoint, PoseJoint, PoseJoint)
    ) -> Double? {
        let left = confidence(pose, vertex, first, second)
        let right = confidence(pose, mirror.0, mirror.1, mirror.2)
        guard max(left, right) >= minConfidence else { return nil }

        return left >= right
            ? pose.angle(at: vertex, from: first, to: second)
            : pose.angle(at: mirror.0, from: mirror.1, to: mirror.2)
    }

    private func confidence(_ pose: Pose, _ joints: PoseJoint...) -> Float {
        joints.reduce(Float(1)) { lowest, joint in
            let index = joint.rawValue
            guard index < pose.confidence.count else { return 0 }
            return min(lowest, pose.confidence[index])
        }
    }
}
