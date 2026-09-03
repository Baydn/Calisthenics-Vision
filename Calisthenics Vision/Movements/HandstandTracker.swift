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
//  A session is a *set of holds*, not one hold. Coming down ends the attempt
//  and going back up starts a new one, each timed and scored on its own —
//  which is how holds are actually trained. Time only accrues frame to frame,
//  so losing the pose mid-hold pauses the clock rather than silently
//  crediting the gap.
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

    /// How long you can be out of position before the hold is treated as
    /// over. Without this, one dropped frame or a momentary landmark glitch
    /// would chop a single clean hold into a dozen fragments.
    var holdGapToleranceMs = 400
    /// Shortest attempt worth recording. Below this it's a wobble on the way
    /// up, not a hold, and listing it would bury the real attempts.
    var minimumHoldSeconds: TimeInterval = 1.0

    private(set) var progress = MovementProgress()

    private(set) var isInverted = false
    private(set) var shoulderAngle: Double?
    private(set) var hipAngle: Double?

    private var lastTimestampMs: Int?
    private var badFormFrames = 0
    private var lastWholeSecond = 0

    /// When the current attempt began, and when we last saw it interrupted.
    /// A non-nil `outOfPositionSinceMs` means an attempt is open but paused.
    private var holdStartMs: Int?
    private var outOfPositionSinceMs: Int?

    /// Running mean of line quality, weighted by time rather than frame count
    /// so a dropped frame doesn't skew the score. Tracked for the attempt
    /// under way and for the set as a whole.
    private var holdQualitySum: Double = 0
    private var holdQualityWeight: Double = 0
    private var setQualitySum: Double = 0
    private var setQualityWeight: Double = 0

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isInverted
        d.readyLabel = isInverted ? "inverted" : "not inverted"
        d.primaryAngleLabel = "shoulder"
        d.primaryAngle = shoulderAngle
        d.secondaryAngleLabel = "hip"
        d.secondaryAngle = hipAngle
        if isInverted {
            d.note = String(
                format: "hold %d/%d · line %.0f%%",
                progress.holds.count + 1, progress.kickUpAttempts,
                (progress.formQuality ?? 0) * 100
            )
        } else {
            d.note = progress.holds.isEmpty
                ? "waiting for inversion"
                : "\(progress.holds.count) held · go again"
            d.noteIsWarning = progress.holds.isEmpty
        }
        return d
    }

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose else {
            // Losing the pose pauses the clock: resuming shouldn't credit the
            // time spent out of frame. The attempt itself stays open until the
            // grace period runs out, so a brief dropout doesn't split a hold.
            lastTimestampMs = nil
            isInverted = false
            shoulderAngle = nil
            hipAngle = nil
            return closeHoldIfLapsed(at: timestampMs)
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
                // The attempt stays open through the grace window; the next
                // frame closes it if you're still down.
                return .formRecovered
            }
            return closeHoldIfLapsed(at: timestampMs)
        }

        // Back in position within the grace window — the attempt continues.
        outOfPositionSinceMs = nil
        if holdStartMs == nil { beginHold(at: timestampMs) }

        defer { lastTimestampMs = timestampMs }

        // The hold is running purely because you're upside down.
        guard let previous = lastTimestampMs else { return nil }
        let delta = timestampMs - previous
        guard delta > 0, delta <= maxFrameGapMs else { return nil }

        let seconds = Double(delta) / 1000
        progress.currentHold += seconds
        recordQuality(over: seconds)

        if let event = updateFormState() { return event }

        let whole = Int(progress.currentHold)
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
        holdStartMs = nil
        outOfPositionSinceMs = nil
        holdQualitySum = 0
        holdQualityWeight = 0
        setQualitySum = 0
        setQualityWeight = 0
    }

    /// Ends any attempt still open — call when the set finishes, so the last
    /// hold isn't lost just because the recording stopped while inverted.
    mutating func finish() {
        _ = closeHold()
    }

    // MARK: - Hold segmentation

    private mutating func beginHold(at timestampMs: Int) {
        // Going up is a kick-up attempt whether or not it turns into a hold.
        // Counting it here, rather than only when a hold is recorded, is what
        // makes a success rate meaningful — the failures are the attempts
        // that never make it past `minimumHoldSeconds`.
        progress.kickUpAttempts += 1
        holdStartMs = timestampMs
        progress.currentHold = 0
        lastWholeSecond = 0
        holdQualitySum = 0
        holdQualityWeight = 0
    }

    /// Closes the open attempt once you've been out of position longer than
    /// the grace window.
    private mutating func closeHoldIfLapsed(at timestampMs: Int) -> MovementEvent? {
        guard holdStartMs != nil else { return nil }

        guard let since = outOfPositionSinceMs else {
            outOfPositionSinceMs = timestampMs
            return nil
        }
        guard timestampMs - since >= holdGapToleranceMs else { return nil }
        return closeHold()
    }

    /// Files the attempt under way, if it lasted long enough to mean anything.
    private mutating func closeHold() -> MovementEvent? {
        guard let start = holdStartMs else { return nil }
        let duration = progress.currentHold

        holdStartMs = nil
        outOfPositionSinceMs = nil
        progress.currentHold = 0
        lastWholeSecond = 0

        guard duration >= minimumHoldSeconds else {
            // Too short to be an attempt. Its time never counted toward the
            // set, since `holdDuration` sums the recorded holds.
            holdQualitySum = 0
            holdQualityWeight = 0
            return nil
        }

        let quality = holdQualityWeight > 0 ? holdQualitySum / holdQualityWeight : nil
        holdQualitySum = 0
        holdQualityWeight = 0

        progress.holds.append(
            HoldSegment(duration: duration, startTimestampMs: start, quality: quality)
        )
        return .holdCompleted(index: progress.holds.count, duration: duration)
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
        holdQualitySum += quality * seconds
        holdQualityWeight += seconds
        setQualitySum += quality * seconds
        setQualityWeight += seconds
        progress.formQuality = setQualityWeight > 0 ? setQualitySum / setQualityWeight : nil
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
    /// point of working in 3D (POSE.md Law 1).
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
