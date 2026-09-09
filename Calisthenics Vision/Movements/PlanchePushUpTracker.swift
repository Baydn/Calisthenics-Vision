//
//  PlanchePushUpTracker.swift
//  Calisthenics Vision
//
//  Planche push-up rep counting. Measurement rules: POSE.md. The position
//  test lives in PlancheGeometry.
//
//  The rep half is the push-up's, unchanged and for the same reasons: the
//  finished position is the locked-out one, so a rep scores on the way back
//  up, and the gates are fractions into the person's own observed elbow range
//  rather than fixed angles (Law 3). Someone strong enough to do these has a
//  smaller usable range than a floor push-up, not a bigger one — the lean
//  eats travel — which is exactly the case a fixed 90° bottom gate would
//  count zero of.
//
//  The position half is the planche's, with two thresholds relaxed, and the
//  relaxation is the whole design problem. A planche push-up bends the elbow
//  and lowers the shoulders to hand height and past it at the bottom, which
//  is precisely where the rep is decided. A gate that demanded locked arms or
//  a full hand-below-shoulder drop would let go at the bottom of every good
//  rep and count none of them — the failure `DipTracker.isSupported` carries
//  a comment about. So the arm is left out of the gate entirely (it's the
//  thing being counted, not evidence of position) and the hip and hand drops
//  are widened to cover the bottom of the rep.
//
//  What still holds the gate up is the pair of things a push-up can't fake:
//  the legs are up at body height rather than hanging to the floor, and the
//  shoulders sit out past the hands. Both survive the whole rep.
//

import Foundation
import simd

struct PlanchePushUpTracker: MovementTracker {

    /// Seeds, used only until the person's own range is known.
    var lockoutAngle: Double = 165
    var bottomAngle: Double = 100

    /// Elbow travel required before this is treated as reps at all, so
    /// wobbling in a static planche can't calibrate its way into counting.
    var minimumRange: Double = 35
    /// How far into your own range a rep has to travel to count. Loose:
    /// depth coaching belongs in form feedback, not in withholding the count.
    var bottomGateFraction: Double = 0.42
    /// How close to lockout re-arms the counter.
    var topGateFraction: Double = 0.25

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
    /// ~0.5s at 30 FPS.
    var framesToFlag = 15
    /// Deviation beyond which the line is called out, in the same units
    /// `PlancheTracker` scores in.
    var warnDeviation: Double = 45

    private(set) var progress = MovementProgress()

    private enum Phase {
        /// Wait for a lockout, so arriving already bent isn't a free rep.
        case awaitingLockout
        case top, descending, bottom
    }
    private var phase: Phase = .awaitingLockout
    private var badFormFrames = 0

    private(set) var isInPosition = false
    private(set) var reading: PlancheGeometry.Reading?
    private(set) var lastElbowAngle: Double?

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
        guard let settledMin, settledMin > standardDepthAngle else {
            return standardDepthAngle
        }
        return settledMin + depthTolerance
    }

    /// Ends of the meter's scale — the deep end is a full rep, not an
    /// unreachable one. Drawing bounds, not gates (see `DepthGauge`).
    var extendedAngle: Double = 180
    var floorAngle: Double = 90

    var depthGauge: DepthGauge? {
        DepthGauge(
            depth: (isInPosition ? lastElbowAngle : nil).map(onScale),
            countsAt: onScale(bottomThreshold)
        )
    }

    /// The angle the standard sits at, from the fraction of the bar it's
    /// drawn at.
    var standardDepthAngle: Double {
        extendedAngle - standardDepthFraction * (extendedAngle - floorAngle)
    }

    /// See `MovementTracker.depthGauge(for:)` — the replay's meter.
    func depthGauge(for pose: Pose) -> DepthGauge? {
        guard Self.isInPosition(pose), let elbow = elbowAngle(pose) else { return nil }
        return DepthGauge(depth: onScale(elbow), countsAt: onScale(standardDepthAngle))
    }

    private func onScale(_ angle: Double) -> Double {
        let span = extendedAngle - floorAngle
        guard span > 0 else { return 0 }
        return min(1, max(0, (extendedAngle - angle) / span))
    }

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isInPosition
        d.readyLabel = isInPosition ? "in planche" : "not in position"
        d.primaryAngleLabel = "elbow"
        d.primaryAngle = lastElbowAngle
        d.secondaryAngleLabel = "lean"
        d.secondaryAngle = reading.map { $0.leanFraction * 100 }
        if !isInPosition {
            d.note = "waiting for the lean"
            d.noteIsWarning = true
        } else if !isCalibrated {
            d.note = "calibrating…"
            d.noteIsWarning = true
        } else {
            d.note = String(format: "gates %.0f°/%.0f°", bottomThreshold, topThreshold)
        }
        return d
    }

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose else {
            isInPosition = false
            reading = nil
            lastElbowAngle = nil
            return nil
        }

        reading = PlancheGeometry.read(pose)
        lastElbowAngle = elbowAngle(pose)

        let supported = PlancheGeometry.isPlanchePosition(pose, lockedArms: false)
        if supported != isInPosition {
            isInPosition = supported
            // Leaving the position abandons a half-finished rep rather than
            // letting it complete the next time you get back on the bars.
            phase = .awaitingLockout
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

        if let event = checkForm() { return event }
        return advance(elbow: elbow)
    }

    mutating func reset() {
        progress = MovementProgress()
        phase = .awaitingLockout
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
    /// holding the planche still is not evidence about your range, and letting
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
            if elbow < top - dwellMargin { phase = .descending }

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
                return .repCompleted(total: progress.reps)
            }
        }
        return nil
    }


    /// Sets the depth target at the bottom of the first descent, the moment
    /// the angle turns around. Waiting for the rep to finish meant the line
    /// didn't appear until the second one. See `PushUpTracker.settleDepth`.
    private mutating func settleDepth(reaching angle: Double) {
        guard let low = repMin, let high = repMax,
              high - low >= minimumRange,
              low < (settledMin ?? .infinity),
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

    /// 0 at lockout, 1 at the bottom of your range.
    private func normalizedDepth(_ elbow: Double) -> Double {
        let high = observedMax ?? lockoutAngle
        let low = observedMin ?? bottomAngle
        let span = high - low
        guard span > 0 else { return 0 }
        return min(1, max(0, (high - elbow) / span))
    }

    // MARK: - Form

    /// Same judgement the static planche makes — level first, straight second
    /// — and, as there, it never withholds a rep.
    private mutating func checkForm() -> MovementEvent? {
        guard let reading, reading.isMeasurable else {
            badFormFrames = 0
            if !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
            return nil
        }

        var worst = reading.levelDeviation * 90 / PlancheGeometry.levelTaperDegrees
        var issue = FormIssue.hipsNotLevel
        if let straightness = reading.straightness, abs(180 - straightness) > worst {
            worst = abs(180 - straightness)
            issue = .lostAlignment
        }
        progress.formQuality = max(0, 1 - worst / 90)

        if worst > warnDeviation {
            badFormFrames += 1
            if badFormFrames == framesToFlag {
                progress.isFormValid = false
                progress.formBreaks += 1
                return .formBreak(issue)
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

    private func elbowAngle(_ pose: Pose) -> Double? {
        let left = PlancheGeometry.confidence(pose, .leftShoulder, .leftElbow, .leftWrist)
        let right = PlancheGeometry.confidence(pose, .rightShoulder, .rightElbow, .rightWrist)
        guard max(left, right) >= minConfidence else { return nil }

        return left >= right
            ? pose.angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)
            : pose.angle(at: .rightElbow, from: .rightShoulder, to: .rightWrist)
    }

    // MARK: - Orientation

    static func isInPosition(_ pose: Pose) -> Bool {
        PlancheGeometry.isPlanchePosition(pose, lockedArms: false)
    }
}
