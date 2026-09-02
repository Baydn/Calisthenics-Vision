//
//  HandstandTracker.swift
//  Calisthenics Vision
//
//  Handstand hold timing. Measurement rules: POSE.md.
//
//  The clock runs whenever you're inverted. Straightness is *measured*, not
//  required: an early handstand is banana-shaped, and refusing to time it
//  reads as the app being broken rather than as coaching. Line quality is
//  scored continuously instead and reported afterwards, so you can see what to
//  work on without being denied credit for the hold.
//
//  Time only accrues frame to frame, so losing the pose mid-hold pauses the
//  clock rather than silently crediting the gap.
//

import Foundation
import simd

struct HandstandTracker: MovementTracker {

    /// Perfect alignment. Deviation from this is what gets scored.
    var idealAlignment: Double = 180
    /// Deviation beyond which the line is called out — deliberately generous,
    /// since this is a warning and not a gate.
    var warnDeviation: Double = 45
    /// Landmarks below this are ignored — an unreliable point shouldn't end
    /// a hold that is actually fine.
    var minConfidence: Float = 0.5
    /// A wobble has to persist before it's mentioned. ~0.7s at 30 FPS.
    var framesToFlag = 20
    /// Gap beyond which we assume tracking was lost rather than time passing.
    var maxFrameGapMs = 500

    private(set) var progress = MovementProgress()

    private(set) var isInverted = false
    private(set) var shoulderAngle: Double?
    private(set) var hipAngle: Double?

    private var lastTimestampMs: Int?
    private var badFormFrames = 0
    private var lastWholeSecond = 0

    /// Running mean of line quality, weighted by time rather than frame count
    /// so a dropped frame doesn't skew the score.
    private var qualitySum: Double = 0
    private var qualityWeight: Double = 0

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isInverted
        d.readyLabel = isInverted ? "inverted" : "not inverted"
        d.primaryAngleLabel = "shoulder"
        d.primaryAngle = shoulderAngle
        d.secondaryAngleLabel = "hip"
        d.secondaryAngle = hipAngle
        if isInverted {
            d.note = String(format: "holding · line %.0f%%", (progress.formQuality ?? 0) * 100)
        } else {
            d.note = "waiting for inversion"
            d.noteIsWarning = true
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

        let wasInverted = isInverted
        isInverted = Self.isInverted(pose)

        guard isInverted else {
            lastTimestampMs = nil
            badFormFrames = 0
            if wasInverted && !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
            return nil
        }

        defer { lastTimestampMs = timestampMs }

        // The hold is running purely because you're upside down.
        guard let previous = lastTimestampMs else { return nil }
        let delta = timestampMs - previous
        guard delta > 0, delta <= maxFrameGapMs else { return nil }

        let seconds = Double(delta) / 1000
        progress.holdDuration += seconds
        recordQuality(over: seconds)

        if let event = updateFormState() { return event }

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
        qualitySum = 0
        qualityWeight = 0
    }

    // MARK: - Line quality

    /// How straight the line is right now, 0…1.
    ///
    /// Full marks at dead straight, tapering to zero at 90° off — a scale
    /// that keeps ordinary imperfection in the useful middle of the range
    /// rather than bottoming out the moment you bend.
    var currentQuality: Double? {
        let angles = [shoulderAngle, hipAngle].compactMap { $0 }
        guard !angles.isEmpty else { return nil }

        // Worst joint, not the average: a straight shoulder shouldn't mask a
        // piked hip. A line is only as good as its biggest bend, which is also
        // how a coach would read it.
        let worstDeviation = angles.map { abs(idealAlignment - $0) }.max() ?? 0
        return max(0, 1 - worstDeviation / 90)
    }

    private mutating func recordQuality(over seconds: Double) {
        guard let quality = currentQuality else { return }
        qualitySum += quality * seconds
        qualityWeight += seconds
        progress.formQuality = qualityWeight > 0 ? qualitySum / qualityWeight : nil
    }

    /// Flags only a sustained, large deviation — and never stops the clock.
    private mutating func updateFormState() -> MovementEvent? {
        let deviations = [shoulderAngle, hipAngle]
            .compactMap { $0 }
            .map { abs(idealAlignment - $0) }
        guard let worst = deviations.max() else { return nil }

        if worst > warnDeviation {
            badFormFrames += 1
            if badFormFrames == framesToFlag {
                progress.isFormValid = false
                progress.formBreaks += 1
                return .formBreak(.lostAlignment)
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

    // MARK: - Inversion

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
        guard abs(shoulder.y - ankle.y) > 0.3 else { return false }

        // Hips need only be above the shoulders — a tucked or piked handstand
        // still counts, and the legs may be nowhere near overhead.
        return hip.y < shoulder.y && ankle.y < shoulder.y
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
