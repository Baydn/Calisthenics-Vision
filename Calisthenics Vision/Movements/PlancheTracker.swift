//
//  PlancheTracker.swift
//  Calisthenics Vision
//
//  Planche hold timing. Measurement rules: POSE.md.
//
//  Same shape as the handstand: a set of holds, not one hold. Coming down
//  ends the attempt and mounting again starts a new one, each timed and
//  scored on its own. Line quality (shoulder and hip alignment against a
//  straight body) is scored continuously and never gates the clock — a tucked
//  or bent planche is still a planche (POSE.md Law 4).
//
//  The orientation gate is the interesting part. A push-up's lockout and a
//  planche look identical at the shoulder — arms straight, torso horizontal —
//  so that alone can't tell them apart. What's different is which point in
//  the chain is riding at ground level. A push-up's wrist, hip and ankle all
//  sit near the floor together and the shoulder is the outlier, held up above
//  them by the arm. A planche inverts that: the whole body floats at shoulder
//  height and the wrist is the one still down at the ground. That's a real,
//  physically distinct arrangement of the same four points, not a fixed
//  camera-angle assumption — see `isSupported` (POSE.md Law 1).
//

import Foundation
import simd

struct PlancheTracker: MovementTracker {

    /// Perfect alignment. Deviation from this is what gets scored.
    var idealAlignment: Double = 180
    /// Deviation beyond which the line is called out — a warning, never a gate.
    var warnDeviation: Double = 45
    /// Landmarks below this are ignored — an unreliable point shouldn't end a
    /// hold that's actually fine.
    var minConfidence: Float = 0.5
    /// ~0.7s at 30 FPS. A wobble has to persist before it's mentioned.
    var framesToFlag = 20
    /// Gap beyond which we assume tracking was lost rather than time passing.
    var maxFrameGapMs = 500

    /// How long you can be out of position before the hold is treated as
    /// over. Without this a single dropped frame would chop one clean hold
    /// into fragments.
    var holdGapToleranceMs = 400
    /// Shortest attempt worth recording. Below this it's a press you came
    /// straight back down from, not a hold.
    var minimumHoldSeconds: TimeInterval = 1.0

    private(set) var progress = MovementProgress()

    private(set) var isSupported = false
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
        d.isReady = isSupported
        d.readyLabel = isSupported ? "in planche" : "not in position"
        d.primaryAngleLabel = "shoulder"
        d.primaryAngle = shoulderAngle
        d.secondaryAngleLabel = "hip"
        d.secondaryAngle = hipAngle
        if isSupported {
            d.note = String(
                format: "hold %d/%d · line %.0f%%",
                progress.holds.count + 1, progress.kickUpAttempts,
                (progress.formQuality ?? 0) * 100
            )
        } else {
            d.note = progress.holds.isEmpty
                ? "waiting for support"
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
            isSupported = false
            shoulderAngle = nil
            hipAngle = nil
            return closeHoldIfLapsed(at: timestampMs)
        }

        shoulderAngle = alignment(pose, at: .leftShoulder, from: .leftWrist, to: .leftHip,
                                  mirror: (.rightShoulder, .rightWrist, .rightHip))
        hipAngle = alignment(pose, at: .leftHip, from: .leftShoulder, to: .leftAnkle,
                             mirror: (.rightHip, .rightShoulder, .rightAnkle))

        let wasSupported = isSupported
        isSupported = Self.isSupported(pose)

        guard isSupported else {
            lastTimestampMs = nil
            badFormFrames = 0
            if wasSupported && !progress.isFormValid {
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

        // The hold is running purely because you're supported.
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
        isSupported = false
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
    /// hold isn't lost just because the recording stopped while supported.
    mutating func finish() {
        _ = closeHold()
    }

    // MARK: - Hold segmentation

    private mutating func beginHold(at timestampMs: Int) {
        // Mounting is an attempt whether or not it turns into a real hold.
        // Counting it here, rather than only when a hold is recorded, is what
        // makes a landing rate meaningful.
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
    /// Full marks at dead straight, tapering to zero at 90° off. Worst joint,
    /// not the average (POSE.md Law 7) — a straight shoulder shouldn't mask a
    /// piked hip.
    var currentQuality: Double? {
        let angles = [shoulderAngle, hipAngle].compactMap { $0 }
        guard !angles.isEmpty else { return nil }

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

    // MARK: - Orientation

    /// Body raised parallel to the ground, supported only on straight arms.
    ///
    /// See the file header for the physical reasoning: a push-up's wrist,
    /// hip and ankle sit near the floor together with the shoulder held up
    /// above them, while a planche's whole body floats at shoulder height
    /// with the wrist the one still down at the ground. Comparing how close
    /// the hip sits to each is what tells them apart, and it holds at any
    /// camera angle because it's computed from world landmarks (POSE.md Law 1).
    ///
    /// Known limit: an elbow lever makes the same shape on bent arms, which
    /// is why straight elbows are required here — not worth guessing at
    /// beyond that, the same call as the pull-up/overhead-press ambiguity.
    static func isSupported(_ pose: Pose) -> Bool {
        guard let shoulder = midpoint(pose, .leftShoulder, .rightShoulder),
              let hip = midpoint(pose, .leftHip, .rightHip),
              let wrist = midpoint(pose, .leftWrist, .rightWrist)
        else { return false }

        let body = hip - shoulder
        let length = simd_length(body)
        guard length > 0.15 else { return false }

        // The torso has to actually be lying flat — rules out a dip or a
        // handstand, and the depth-collapsed reading you'd get filmed end-on.
        guard abs(body.y) / length < 0.5 else { return false }

        let elbow = pose.angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)
            ?? pose.angle(at: .rightElbow, from: .rightShoulder, to: .rightWrist)
        guard let elbow, elbow > 140 else { return false }

        // The hip has to be riding with the shoulder, not with the wrist. A
        // real gap has to exist somewhere first, or someone lying flat on the
        // ground — wrist, hip and shoulder all near the same height — would
        // pass on noise alone.
        let hipToShoulder = abs(hip.y - shoulder.y)
        let hipToWrist = abs(hip.y - wrist.y)
        guard hipToWrist > 0.2 * length else { return false }
        return hipToShoulder < hipToWrist
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
