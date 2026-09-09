//
//  PlancheTracker.swift
//  Calisthenics Vision
//
//  Planche hold timing. Measurement rules: POSE.md. The position test and the
//  reasoning behind it live in PlancheGeometry.
//
//  Hold segmentation is the handstand's: a set of attempts, not one hold,
//  each timed and scored on its own, the clock pausing rather than crediting
//  time you weren't there for.
//
//  **What gets scored is not the handstand's.** That was the second bug in
//  this file. A handstand is judged against a straight line through
//  everything — wrist, shoulder, hip, ankle all at 180° — so scoring it means
//  measuring every joint against straight. A planche is not that shape. The
//  arm is *meant* to sit at roughly 60° to the torso; that angle is the lean
//  that holds the whole thing up. Scoring it against 180° gave a textbook
//  planche a line score of zero.
//
//  The two things a planche is actually judged on:
//
//  - **Level.** The body is held parallel to the ground. Hips riding high is
//    the universal cheat, and the gymnastics standard treats 45° off level as
//    the point where it stops counting as a planche at all.
//  - **Straight.** Shoulder through hip to ankle in one line, no sag, no pike
//    — but only where the legs are extended enough for that to mean anything.
//    A tuck planche is folded on purpose and scoring it against a straight
//    body would report a correct tuck as a failure.
//
//  Worst of the two, never the average (POSE.md Law 7), and neither ever
//  gates the clock (Law 4).
//
//  Scapular protraction is the third thing a coach would judge and it is
//  deliberately absent: MediaPipe gives one coarse point per shoulder, and
//  protraction is a couple of centimetres of scapular travel that lands on
//  the depth axis when filmed side-on. There is no honest way to report it,
//  so it isn't reported (Law 5).
//

import Foundation
import simd

struct PlancheTracker: MovementTracker {

    /// Deviation beyond which the line is called out — a warning, never a gate.
    var warnDeviation: Double = 35
    /// Landmarks below this are ignored.
    var minConfidence: Float = 0.5
    /// ~0.7s at 30 FPS. A wobble has to persist before it's mentioned.
    var framesToFlag = 20
    /// Gap beyond which we assume tracking was lost rather than time passing.
    var maxFrameGapMs = 500

    /// How long you can be out of position before the hold is treated as
    /// over. Without this a single dropped frame would chop one clean hold
    /// into fragments.
    var holdGapToleranceMs = 400
    /// Shortest attempt worth recording. Two seconds is the gymnastics
    /// standard for a planche to count at all, but that's a judging rule, not
    /// a measurement one — a one-second planche happened and belongs in the
    /// set, the same way a one-second handstand does.
    var minimumHoldSeconds: TimeInterval = 1.0

    private(set) var progress = MovementProgress()

    private(set) var isSupported = false
    private(set) var reading: PlancheGeometry.Reading?

    private var lastTimestampMs: Int?
    private var badFormFrames = 0
    private var lastWholeSecond = 0

    private var holdStartMs: Int?
    private var outOfPositionSinceMs: Int?

    private var holdQualitySum: Double = 0
    private var holdQualityWeight: Double = 0
    private var setQualitySum: Double = 0
    private var setQualityWeight: Double = 0

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isSupported
        d.readyLabel = isSupported ? "in planche" : "not in position"
        // The lean is the measurement that defines this movement, so it's the
        // one on the readout — as degrees off level rather than as an angle,
        // because "how far past your hands" is what you're trying to change.
        d.primaryAngleLabel = "lean"
        d.primaryAngle = reading.map { $0.leanFraction * 100 }
        d.secondaryAngleLabel = "off level"
        d.secondaryAngle = reading?.levelDeviation
        if isSupported {
            d.note = String(
                format: "hold %d/%d · line %@",
                progress.holds.count + 1, progress.kickUpAttempts,
                currentQuality.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
            )
        } else {
            d.note = progress.holds.isEmpty
                ? "waiting for the lean"
                : "\(progress.holds.count) held · go again"
            d.noteIsWarning = progress.holds.isEmpty
        }
        return d
    }

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose else {
            lastTimestampMs = nil
            isSupported = false
            reading = nil
            return closeHoldIfLapsed(at: timestampMs)
        }

        reading = PlancheGeometry.read(pose)

        let wasSupported = isSupported
        isSupported = PlancheGeometry.isPlanchePosition(pose, lockedArms: true)

        guard isSupported else {
            lastTimestampMs = nil
            badFormFrames = 0
            if wasSupported && !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
            return closeHoldIfLapsed(at: timestampMs)
        }

        outOfPositionSinceMs = nil
        if holdStartMs == nil { beginHold(at: timestampMs) }

        defer { lastTimestampMs = timestampMs }

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
        reading = nil
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

    /// Ends any attempt still open, so stopping the recording mid-planche
    /// doesn't throw the hold away.
    mutating func finish() {
        _ = closeHold()
    }

    // MARK: - Hold segmentation

    private mutating func beginHold(at timestampMs: Int) {
        progress.kickUpAttempts += 1
        holdStartMs = timestampMs
        progress.currentHold = 0
        lastWholeSecond = 0
        holdQualitySum = 0
        holdQualityWeight = 0
    }

    private mutating func closeHoldIfLapsed(at timestampMs: Int) -> MovementEvent? {
        guard holdStartMs != nil else { return nil }

        guard let since = outOfPositionSinceMs else {
            outOfPositionSinceMs = timestampMs
            return nil
        }
        guard timestampMs - since >= holdGapToleranceMs else { return nil }
        return closeHold()
    }

    private mutating func closeHold() -> MovementEvent? {
        guard let start = holdStartMs else { return nil }
        let duration = progress.currentHold

        holdStartMs = nil
        outOfPositionSinceMs = nil
        progress.currentHold = 0
        lastWholeSecond = 0

        guard duration >= minimumHoldSeconds else {
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

    /// How good the planche is right now, 0…1 — level first, straight second,
    /// worst of the two. Nil when the body line runs into the camera, where
    /// neither can be measured honestly (POSE.md Law 5).
    var currentQuality: Double? {
        guard let worst = worstFault else { return nil }
        return max(0, 1 - worst.deviation / 90)
    }

    /// The fault currently costing the most, with how far off it is in
    /// degrees, so the warning can name the thing that's actually wrong
    /// rather than saying "line" for everything.
    var worstFault: (issue: FormIssue, deviation: Double)? {
        guard let reading, reading.isMeasurable else { return nil }

        // Level is scored on a shorter scale than straightness: 45° off
        // horizontal is a failed planche by the gymnastics standard, where
        // 45° of pike is merely a bad line.
        var faults: [(FormIssue, Double)] = [
            (.hipsNotLevel, reading.levelDeviation * 90 / PlancheGeometry.levelTaperDegrees)
        ]
        if let straightness = reading.straightness {
            faults.append((.lostAlignment, abs(180 - straightness)))
        }

        guard let worst = faults.max(by: { $0.1 < $1.1 }) else { return nil }
        return (worst.0, worst.1)
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
        guard let worst = worstFault else {
            // Unmeasurable is not failing: don't leave the skeleton red
            // because the camera ended up in front of the body.
            badFormFrames = 0
            if !progress.isFormValid {
                progress.isFormValid = true
                return .formRecovered
            }
            return nil
        }

        if worst.deviation > warnDeviation {
            badFormFrames += 1
            if badFormFrames == framesToFlag {
                progress.isFormValid = false
                progress.formBreaks += 1
                return .formBreak(worst.issue)
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

    static func isSupported(_ pose: Pose) -> Bool {
        PlancheGeometry.isPlanchePosition(pose, lockedArms: true)
    }
}
