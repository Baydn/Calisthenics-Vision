//
//  DipTracker.swift
//  Calisthenics Vision
//
//  Dip rep counting. Measurement rules: POSE.md.
//
//  Elbow-driven like the push-up, and counted the same way: the finished
//  position is the locked-out one, so a rep scores on the way back up. What
//  differs is the orientation gate — a dip is upright with the hands *beside*
//  the hips, which is exactly what separates it from a pull-up (hands
//  overhead) and a push-up (torso horizontal).
//
//  The form signal is shoulder depth: at the bottom of a real dip the
//  shoulder drops to or below the elbow. It's scored and called out, never
//  gated — a partial dip is still a dip, and refusing to count it reads as a
//  broken app (POSE.md Law 4).
//

import CoreGraphics
import Foundation
import simd

struct DipTracker: MovementTracker {

    /// Seeds, used only until the person's own range is known.
    var lockoutAngle: Double = 168
    var bottomAngle: Double = 95

    var minimumRange: Double = 40
    /// Loose on purpose: depth coaching is feedback, not a gate.
    var bottomGateFraction: Double = 0.42
    var topGateFraction: Double = 0.25

    /// How close to the depth you actually showed us a rep has to get, in
    /// degrees — the gate the meter draws its line at. Anchored to your own
    /// measured bottom rather than to a fraction of the range, whose top end
    /// is the fragile one. See `PushUpTracker.depthTolerance`.
    var depthTolerance: Double = 15

    var minConfidence: Float = 0.5
    var formConfidence: Float = 0.8
    /// ~0.5s at 30 FPS. Longer than the push-up's, because the bottom of a
    /// dip is brief and a shallow rep shouldn't be called out instantly.
    var framesToFlag = 15

    private(set) var progress = MovementProgress()

    private enum Phase {
        /// Wait for a lockout, so dropping onto the bars already bent and
        /// pressing up isn't a free rep.
        case awaitingLockout
        case top, descending, bottom
    }
    private var phase: Phase = .awaitingLockout
    private var badFormFrames = 0
    /// Whether this rep has reached shoulder-below-elbow depth yet.
    private var reachedDepth = false

    private(set) var isOnBars = false
    private(set) var lastElbowAngle: Double?
    private(set) var lastShoulderDrop: Double?

    private(set) var observedMin: Double?
    private(set) var observedMax: Double?
    /// Last angle fed to `observeRange`, to tell moving from holding still.
    private var lastRangeAngle: Double?

    /// Extremes of the rep currently under way, and the range a *completed*
    /// rep showed us — which is what the gates use once there is one.
    ///
    /// Learning it from every frame in position let the setup set the range:
    /// see `PushUpTracker` for the bug and why a finished rep is the honest
    /// sample. The first one sets the range and it then holds for the set.
    private var repMin: Double?
    private var repMax: Double?
    private var settledMin: Double?
    private var settledMax: Double?

    var settledRange: Double? {
        guard let settledMin, let settledMax else { return nil }
        return settledMax - settledMin
    }

    /// True once a completed rep has defined the range.
    var isSettled: Bool { settledRange != nil }

    /// The range the gates are computed from.
    var workingRange: Double? { settledRange ?? (isCalibrated ? observedRange : nil) }

    var observedRange: Double? {
        guard let observedMin, let observedMax else { return nil }
        return observedMax - observedMin
    }

    var isCalibrated: Bool { (observedRange ?? 0) >= minimumRange }

    var topThreshold: Double {
        if let settledMax, let range = settledRange {
            return settledMax - range * topGateFraction
        }
        guard isCalibrated, let observedMax, let range = observedRange else { return lockoutAngle }
        return observedMax - range * topGateFraction
    }

    var bottomThreshold: Double {
        if let settledMin { return settledMin + depthTolerance }
        guard isCalibrated, let observedMin, let range = observedRange else { return bottomAngle }
        return observedMin + range * bottomGateFraction
    }

    /// Ends of the meter's scale: locked out at the top, shoulders below the
    /// elbows at the bottom — a full rep, not an unreachable one. Drawing bounds, not gates (see `DepthGauge`).
    var extendedAngle: Double = 180
    var floorAngle: Double = 90

    var depthGauge: DepthGauge? {
        guard isOnBars, let elbow = lastElbowAngle else { return nil }
        return DepthGauge(
            depth: onScale(elbow),
            countsAt: isSettled ? onScale(bottomThreshold) : nil
        )
    }

    private func onScale(_ angle: Double) -> Double {
        let span = extendedAngle - floorAngle
        guard span > 0 else { return 0 }
        return min(1, max(0, (extendedAngle - angle) / span))
    }

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isOnBars
        d.readyLabel = isOnBars ? "on the bars" : "not on the bars"
        d.primaryAngleLabel = "elbow"
        d.primaryAngle = lastElbowAngle
        d.secondaryAngleLabel = "shoulder drop"
        d.secondaryAngle = lastShoulderDrop.map { $0 * 100 }
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
            isOnBars = false
            lastElbowAngle = nil
            lastShoulderDrop = nil
            return nil
        }

        lastElbowAngle = elbowAngle(pose)
        lastShoulderDrop = shoulderDrop(pose)

        let supported = Self.isSupported(pose)
        if supported != isOnBars {
            isOnBars = supported
            phase = .awaitingLockout
            reachedDepth = false
            if !supported {
                badFormFrames = 0
                if !progress.isFormValid {
                    progress.isFormValid = true
                    return .formRecovered
                }
            }
        }
        guard supported, let elbow = lastElbowAngle else { return nil }

        observeRange(elbow)
        repMin = min(elbow, repMin ?? elbow)
        repMax = max(elbow, repMax ?? elbow)
        settleDepth(reaching: elbow)
        progress.repProgress = normalizedDepth(elbow)

        // Depth is watched throughout the rep and judged when it finishes.
        if let drop = lastShoulderDrop, drop >= 0 { reachedDepth = true }

        return advance(elbow: elbow)
    }

    mutating func reset() {
        progress = MovementProgress()
        phase = .awaitingLockout
        badFormFrames = 0
        reachedDepth = false
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
    /// holding still on the bars is not evidence about your range, and letting
    /// it collapse un-learns the person mid-set. See
    /// `PushUpTracker.observeRange` for the bug this fixes.
    private mutating func observeRange(_ elbow: Double) {
        let moved = abs(elbow - (lastRangeAngle ?? elbow)) > 0.5
        lastRangeAngle = elbow

        let slack = (observedRange ?? 0) - minimumRange
        let decay = moved && slack > 0 ? min(0.05, slack / 2) : 0
        observedMax = max(elbow, (observedMax ?? elbow) - decay)
        observedMin = min(elbow, (observedMin ?? elbow) + decay)
    }

    // MARK: - Rep phases

    private mutating func advance(elbow: Double) -> MovementEvent? {
        let top = topThreshold
        let bottom = bottomThreshold

        switch phase {
        case .awaitingLockout:
            // Arming can't wait for calibration: the observed range only
            // grows once you move, so it would arm halfway down your first
            // rep and eat it. See `PushUpTracker.advance`.
            if elbow >= lockoutAngle || (isCalibrated && elbow >= top) {
                enterTop(at: elbow)
            }

        case .top:
            if elbow < top - dwellMargin {
                phase = .descending
                reachedDepth = false
            }

        case .descending:
            if elbow <= bottom {
                phase = .bottom
            } else if elbow >= top {
                enterTop(at: elbow)
            }

        case .bottom:
            if elbow >= top {
                progress.reps += 1
                settleTop(elbow)
                enterTop(at: elbow)

                // Counted first, judged second — the rep is banked either way.
                if isFormMeasurable && !reachedDepth {
                    progress.formBreaks += 1
                    progress.isFormValid = false
                    return .formBreak(.shallowDip)
                }
                progress.isFormValid = true
                return .repCompleted(total: progress.reps)
            }
        }
        return nil
    }


    /// Sets the depth target at the bottom of the first descent, the moment
    /// the angle turns around. Waiting for the rep to finish meant the line
    /// didn't appear until the second one. See `PushUpTracker.settleDepth`.
    private mutating func settleDepth(reaching angle: Double) {
        guard settledMin == nil,
              let low = repMin, let high = repMax,
              high - low >= minimumRange,
              angle > low + 2
        else { return }

        settledMin = low
        settledMax = high
    }

    /// The top the last rep actually finished at. Keeps adapting, unlike the
    /// depth target, because the first rep starts from a setup nothing
    /// afterwards revisits — and nothing draws this, so it can move unseen.
    private mutating func settleTop(_ angle: Double) {
        let high = max(repMax ?? angle, angle)
        guard let low = settledMin, high - low >= minimumRange else { return }
        settledMax = high
    }

    /// Arriving at the top opens the window the next rep's range is measured
    /// over — it can't start at the descent, which is only recognised after
    /// the dwell margin has already been travelled.
    private mutating func enterTop(at elbow: Double) {
        phase = .top
        repMin = elbow
        repMax = elbow
    }

    private var dwellMargin: Double {
        guard let range = workingRange else { return 10 }
        return max(5, range * 0.1)
    }

    private func normalizedDepth(_ elbow: Double) -> Double {
        let high = observedMax ?? lockoutAngle
        let low = observedMin ?? bottomAngle
        let span = high - low
        guard span > 0 else { return 0 }
        return min(1, max(0, (high - elbow) / span))
    }

    // MARK: - Form

    /// How far the shoulder sits below the elbow, in metres. Positive means
    /// the shoulder has dropped past it, which is the standard for a full dip.
    ///
    /// World y runs downward, so "below" is a larger y.
    func shoulderDrop(_ pose: Pose) -> Double? {
        let confidence = min(
            self.confidence(pose, .leftShoulder, .rightShoulder),
            self.confidence(pose, .leftElbow, .rightElbow)
        )
        guard confidence >= formConfidence,
              let shoulder = Self.midpoint(pose, .leftShoulder, .rightShoulder),
              let elbow = Self.midpoint(pose, .leftElbow, .rightElbow)
        else { return nil }

        return shoulder.y - elbow.y
    }

    private var isFormMeasurable: Bool { lastShoulderDrop != nil }

    // MARK: - Orientation

    /// Upright, with the hands beside the hips rather than overhead.
    ///
    /// The hand position is what separates this from a pull-up; the upright
    /// torso is what separates it from a push-up.
    ///
    /// Known limit: standing and bending your elbows has the same geometry.
    /// Distinguishing them needs a ground reference we don't have, and it
    /// isn't worth breaking real dips to catch — the same call as the
    /// pull-up's overhead-press case.
    static func isSupported(_ pose: Pose) -> Bool {
        guard let shoulder = midpoint(pose, .leftShoulder, .rightShoulder),
              let hip = midpoint(pose, .leftHip, .rightHip),
              let wrist = midpoint(pose, .leftWrist, .rightWrist)
        else { return false }

        let torso = hip - shoulder
        let length = simd_length(torso)
        guard length > 0.01, abs(torso.y) / length > 0.7 else { return false }

        // The hands must not be *overhead*, which is what rules out a hang.
        //
        // Not "below the shoulders": at the bottom of a deep dip the shoulder
        // descends to hand height or past it, so requiring the wrist to stay
        // below would drop out of position at the bottom of every good rep —
        // exactly where the rep is decided. The complement of the pull-up's
        // gate, which wants the wrist 15cm *above* the shoulder.
        return shoulder.y - wrist.y < 0.15 && wrist.y > hip.y - length * 1.2
    }

    static func midpoint(_ pose: Pose, _ a: PoseJoint, _ b: PoseJoint) -> SIMD3<Double>? {
        guard let pa = pose.worldPoint(a), let pb = pose.worldPoint(b) else { return nil }
        return (pa + pb) / 2
    }

    // MARK: - Measurements

    private func elbowAngle(_ pose: Pose) -> Double? {
        let left = confidence(pose, .leftShoulder, .leftElbow, .leftWrist)
        let right = confidence(pose, .rightShoulder, .rightElbow, .rightWrist)
        guard max(left, right) >= minConfidence else { return nil }

        return left >= right
            ? pose.angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)
            : pose.angle(at: .rightElbow, from: .rightShoulder, to: .rightWrist)
    }

    private func confidence(_ pose: Pose, _ joints: PoseJoint...) -> Float {
        joints.reduce(Float(1)) { lowest, joint in
            let index = joint.rawValue
            guard index < pose.confidence.count else { return 0 }
            return min(lowest, pose.confidence[index])
        }
    }
}
