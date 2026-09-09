//
//  PushUpTracker.swift
//  Calisthenics Vision
//
//  Push-up rep counting. Measurement rules: POSE.md.
//
//  **A push-up is your chest going down, not your elbow bending.** This ran
//  off the elbow angle for a long time, and it was exploitable in about the
//  most embarrassing way available: lift one hand off the floor and put it
//  back, and the elbow sweeps its whole range with your body completely
//  still. Every rep of that counted. You could lie in a plank and rack up a
//  hundred by waving.
//
//  The elbow was only ever a proxy for the thing that matters, and the thing
//  that matters is measurable directly: how far the shoulders ride above the
//  hands. The hands are on the floor in a push-up, so they *are* the ground
//  reference -- and it is specifically the **lower** of the two wrists, the
//  one still bearing weight. Take their midpoint and lifting a hand drags the
//  reference up with it, which is the same exploit wearing a hat.
//
//  Reported as a fraction of the person's own arm length, which is the
//  normaliser that actually cancels: the numerator and the denominator are
//  the same limbs, so body size divides straight out and only forearm-to-
//  upper-arm proportion is left, which barely varies between people.
//
//  **Your shoulders never get near the floor, even with your chest flat on
//  it.** The forearm stays vertical through a push-up, so the elbow sits a
//  forearm's length up and the shoulder sits at about elbow height. Chest on
//  the floor reads ~0.39 of an arm length, not ~0. Scaling the meter as if it
//  reached zero put a full-depth rep at about half the bar, and put the
//  counting standard somewhere nobody could reach -- which then fired the
//  can't-reach-the-standard rescue on every set and made the line wander.
//  The measured numbers are ~0.93 at the top and ~0.39 chest-to-floor.
//
//  The elbow is still measured, but only to be shown -- nothing counts on it.
//
//  State machine: TOP -> BOTTOM -> TOP counts one rep. A rep only counts on
//  the way back up through lockout, so descending halfway and giving up never
//  scores. Gates are calibrated to the person (POSE.md Law 3).
//
//  Hip sag is flagged when shoulder-hip-ankle bends more than 15 degrees off
//  straight -- but only while posture is actually measurable (POSE.md Law 5),
//  and never by withholding the rep count (Law 4).
//

import CoreGraphics
import Foundation
import simd

struct PushUpTracker: MovementTracker {

    // Everything below is in **arm lengths of chest height above the planted
    // hand** — see `chestHeight`. Roughly 0.93 at the top of a push-up and
    // 0.39 with the chest on the floor, on any size of body.
    //
    // The seed only arms the state machine; every gate that decides anything
    // is measured off the person (POSE.md Law 3).
    var lockoutHeight: Double = 0.80
    var maxHipDeviation: Double = 15

    /// Total travel required before the motion is treated as a rep at all,
    /// so fidgeting in position can't calibrate its way into counting.
    /// A full push-up covers about 0.54, so this is over half of one.
    var minimumRange: Double = 0.28
    /// How close to full extension counts as locked out, as a fraction of
    /// your own range. This is what separates consecutive reps.
    var topGateFraction: Double = 0.25

    /// Where the counting line sits, as a fraction of the meter's bar. This
    /// is a *standard*: it's known before you've moved, so the line is on
    /// screen from the first frame of the recording and doesn't have to be
    /// discovered.
    var standardDepthFraction: Double = 0.80

    /// How close to your own measured bottom counts, in arm lengths.
    ///
    /// Applies **only** where a rep has shown the standard is out of reach —
    /// see `bottomThreshold`. That condition is the whole point: it's what
    /// stops someone who can't get their chest near the floor from counting
    /// zero reps forever (POSE.md Law 3), without loosening the gate under
    /// everyone who was already clearing it.
    var depthTolerance: Double = 0.08

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

    var diagnostics: TrackerDiagnostics {
        var d = TrackerDiagnostics()
        d.isReady = isInPosition
        d.readyLabel = isInPosition ? "in position" : "not in position"
        d.primaryAngleLabel = "chest"
        d.primaryAngle = lastChestHeight.map { $0 * 100 }
        d.secondaryAngleLabel = "hip"
        d.secondaryAngle = lastHipAngle
        if !isCalibrated {
            d.note = "calibrating…"
            d.noteIsWarning = true
        } else {
            d.note = String(
                format: "gates %.2f/%.2f · form %@",
                bottomThreshold, topThreshold,
                isFormMeasurable ? "on" : "off"
            )
        }
        return d
    }

    /// Whether the body is oriented like a push-up right now, exposed so the
    /// HUD can explain why nothing is being counted.
    private(set) var isInPosition = false

    /// Whether posture can currently be judged at all. False when the camera
    /// is end-on to the body or the legs aren't visible — reps still count.
    private(set) var isFormMeasurable = false

    /// Latest measurements. `lastChestHeight` is the one that counts; the
    /// elbow is shown but decides nothing.
    private(set) var lastElbowAngle: Double?
    private(set) var lastChestHeight: Double?
    private(set) var lastHipAngle: Double?

    /// Elbow extremes seen so far, and the resulting gates. Surfaced so the
    /// HUD can show why something is or isn't counting.
    private(set) var observedMin: Double?
    private(set) var observedMax: Double?
    /// Last angle fed to `observeRange`, to tell moving from holding still.
    private var lastRangeAngle: Double?

    /// Extremes of the rep currently under way.
    private var repMin: Double?
    private var repMax: Double?

    /// The range a *completed rep* showed us, which is what the gates use
    /// once there is one.
    ///
    /// Learning the range from every frame the body is horizontal was the
    /// mistake, and it produced three complaints at once. Setting up in a
    /// plank holds the elbows locked, which reads ~178°, while the top people
    /// actually return to between reps is nearer 160° — so the observed
    /// maximum came from the setup rather than from any rep. Every gate is a
    /// *fraction of the range*, so one inflated end pushed the bottom gate up
    /// (barely have to go down for it to count) and the lockout gate up with
    /// it (have to go all the way back up before it will). And because the
    /// extremes kept moving as the set went on, the gates — and the meter's
    /// line drawn at them — changed after every rep.
    ///
    /// A finished rep is the honest sample: it contains exactly one top and
    /// one bottom, both of them yours, neither of them your setup. The first
    /// one sets the range and it then holds for the set, so the line lands
    /// once and stays put.
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

    /// True once a completed rep has defined the range. Until then the gates
    /// run on the rougher running observation, which is what lets the *first*
    /// rep be detected at all.
    var isSettled: Bool { settledRange != nil }

    /// True once enough travel has been seen to try counting.
    var isCalibrated: Bool { (observedRange ?? 0) >= minimumRange }

    /// The range the gates are computed from.
    var workingRange: Double? { settledRange ?? (isCalibrated ? observedRange : nil) }

    /// Angle at or above which the arm counts as extended.
    var topThreshold: Double {
        if let settledMax, let range = settledRange {
            return settledMax - range * topGateFraction
        }
        guard isCalibrated, let observedMax, let range = observedRange else {
            return lockoutHeight
        }
        return observedMax - range * topGateFraction
    }

    /// The angle the standard sits at, from the fraction of the bar it's
    /// drawn at.
    var standardDepthHeight: Double {
        extendedHeight - standardDepthFraction * (extendedHeight - floorHeight)
    }

    /// Angle at or below which the rep counts as deep enough. **This is what
    /// the meter draws**, so it is the truth about where the line is.
    ///
    /// The standard, unless a rep has shown that the standard is out of
    /// reach. Taking `max(standard, bottom + tolerance)` unconditionally —
    /// the previous attempt — loosened the gate for people who never needed
    /// it: reach 95° against a 108° standard and you're past the line, but
    /// the max still moved the gate to 110°, so reps counted a visible
    /// distance short of the line you were being shown. A line that isn't
    /// the gate is worse than no line.
    ///
    /// The loosening survives for the case it exists for — someone whose
    /// deepest rep reads *shallower* than the standard would otherwise count
    /// zero forever (POSE.md Law 3) — and there it moves the drawn line too,
    /// so the two never disagree.
    var bottomThreshold: Double {
        guard let settledMin, settledMin > standardDepthHeight else {
            return standardDepthHeight
        }
        return settledMin + depthTolerance
    }

    /// Ends of the scale the depth meter is drawn on, in arm lengths above
    /// the planted hand: arms straight at the top, chest on the floor at the
    /// bottom.
    ///
    /// **The deep end is where a real chest-to-floor rep actually lands
    /// (~0.39), not zero.** The shoulder can't reach the floor — the forearm
    /// stays vertical and holds it a forearm's length up — so scaling as if
    /// it could put a full-depth rep at barely half the bar, and put the
    /// counting standard somewhere nobody reaches. That then fired the
    /// can't-reach-the-standard rescue on every set, which is what kept the
    /// line moving. Drawing bounds, not gates — see `DepthGauge` for why
    /// those are different things.
    var extendedHeight: Double = 1.0
    var floorHeight: Double = 0.35

    /// Always present. Only the fill depends on being able to see you; the
    /// bar and its line are there from the first frame of the recording, and
    /// stay put while you walk in and out of shot.
    ///
    /// The line is drawn at `bottomThreshold` — the gate itself, never a
    /// stand-in for it. Anything else and "reach the line" stops meaning
    /// "the rep counts", which is the only job the line has.
    var depthGauge: DepthGauge? {
        DepthGauge(
            depth: (isInPosition ? lastChestHeight : nil).map(onScale),
            countsAt: onScale(bottomThreshold)
        )
    }

    /// See `MovementTracker.depthGauge(for:)` — the replay's meter.
    func depthGauge(for pose: Pose) -> DepthGauge? {
        guard pose.isTorsoHorizontal ?? false, let height = chestHeight(pose) else { return nil }
        return DepthGauge(depth: onScale(height), countsAt: onScale(standardDepthHeight))
    }

    private func onScale(_ height: Double) -> Double {
        let span = extendedHeight - floorHeight
        guard span > 0 else { return 0 }
        return min(1, max(0, (extendedHeight - height) / span))
    }

    mutating func update(pose: Pose?, timestampMs: Int) -> MovementEvent? {
        guard let pose else {
            isInPosition = false
            lastElbowAngle = nil
            lastChestHeight = nil
            lastHipAngle = nil
            return nil
        }

        lastElbowAngle = elbowAngle(pose)
        lastChestHeight = chestHeight(pose)
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
        guard horizontal, let height = lastChestHeight else { return nil }

        observeRange(height)
        repMin = min(height, repMin ?? height)
        repMax = max(height, repMax ?? height)
        settleDepth(reaching: height)
        progress.repProgress = normalizedDepth(height)

        if let event = checkForm(pose) { return event }
        return advance(height: height)
    }

    mutating func reset() {
        progress = MovementProgress()
        phase = .awaitingLockout
        badFormFrames = 0
        observedMin = nil
        observedMax = nil
        lastRangeAngle = nil
        lastChestHeight = nil
        repMin = nil
        repMax = nil
        settledMin = nil
        settledMax = nil
    }

    // MARK: - Calibration

    /// Widens the observed range, letting stale extremes decay slowly so one
    /// unusually deep rep — or a bad frame — doesn't set the gates forever.
    ///
    /// Two things bound the decay, and both were bugs.
    ///
    /// **It only runs while you're moving.** An extreme goes stale because
    /// you've since done reps that didn't reach it — not because time passed.
    /// Decaying every frame regardless ate the range at 1.5°/s while you
    /// simply held the top of a plank, so half a minute of rest un-learned
    /// the person mid-set: gates collapsed to a few degrees apart, narrow
    /// enough for a small bob to score a rep, and the depth meter's line
    /// wandered up the bar and then snapped to the pre-calibration seed.
    ///
    /// **And it floors at `minimumRange`.** Below that the range is too
    /// narrow to have been trustworthy in the first place, so there's nothing
    /// left worth forgetting.
    private mutating func observeRange(_ height: Double) {
        // 0.005 arm lengths per frame ≈ a fifth of a range per second. A real
        // rep sweeps its range in about a second, well above this; a smoothed,
        // stationary landmark sits well under it.
        let moved = abs(height - (lastRangeAngle ?? height)) > 0.005
        lastRangeAngle = height

        // Both ends move each frame, so half the slack is the most either can
        // take without carrying the range below the floor.
        let slack = (observedRange ?? 0) - minimumRange
        let decay = moved && slack > 0 ? min(0.0005, slack / 2) : 0
        observedMax = max(height, (observedMax ?? height) - decay)
        observedMin = min(height, (observedMin ?? height) + decay)
    }

    // MARK: - Rep phases

    private mutating func advance(height: Double) -> MovementEvent? {
        let top = topThreshold
        let bottom = bottomThreshold

        switch phase {
        case .awaitingLockout:
            // Arming needs a top to leave from, and waiting for calibration
            // meant it could never happen while you were *still* — the
            // observed range only grows once you move, so the counter armed
            // halfway down your first descent and ate that rep, which is why
            // the line waited for the second one. The seeded lockout is safe
            // here precisely because it only *starts* the state machine:
            // every gate that decides anything is still measured off you.
            if height >= lockoutHeight || (isCalibrated && height >= top) {
                enterTop(at: height)
            }

        case .top:
            // Require a clear departure before believing a rep has started;
            // jitter sitting on the gate shouldn't advance us.
            if height < top - dwellMargin { phase = .descending }

        case .descending:
            if height <= bottom {
                phase = .bottom
            } else if height >= top {
                // Went back up without reaching depth — not a rep.
                enterTop(at: height)
            }

        case .bottom:
            if height >= top {
                progress.reps += 1
                settleTop(height)
                enterTop(at: height)
                return .repCompleted(total: progress.reps)
            }
        }
        return nil
    }

    /// Arriving at the top opens the window the next rep's range is measured
    /// over. It has to start here rather than when the descent is detected:
    /// a descent is only recognised once you've already dropped past the
    /// dwell margin, so measuring from there would shave that much off the
    /// top of every rep and quietly under-report your range.
    private mutating func enterTop(at height: Double) {
        phase = .top
        repMin = height
        repMax = height
    }

    /// Sets the depth target at the bottom of the first descent — the moment
    /// the elbow turns around and starts back up.
    ///
    /// Waiting for the rep to *finish* meant the line didn't appear until the
    /// second one, because the first rep is the one that teaches us the
    /// range. The bottom is the earliest instant the number is actually
    /// known: by then you've been to the deepest point of the rep, and
    /// nothing about coming back up adds to it.
    ///
    /// It then holds for the set. Your first honest rep is the target, and a
    /// target that moves is not one.
    private mutating func settleDepth(reaching height: Double) {
        guard let low = repMin, let high = repMax,
              high - low >= minimumRange,
              low < (settledMin ?? .infinity),
              // Turned around: on the way back up from the bottom, rather
              // than still descending.
              height > low + 0.02
        else { return }

        settledMin = low
        settledMax = high
    }

    /// The top the last rep actually finished at.
    ///
    /// Kept adapting every rep, unlike the depth target, because the first
    /// rep starts from a setup lockout that nothing afterwards revisits —
    /// and because nothing draws this, so it can move without anyone seeing
    /// it. Left fixed, it demanded you push back up to your setup on every
    /// rep before one would close.
    private mutating func settleTop(_ height: Double) {
        let high = max(repMax ?? height, height)
        guard let low = settledMin, high - low >= minimumRange else { return }
        settledMax = high
    }

    /// Dead band around a gate, scaled to the person's range so it means the
    /// same thing whether they travel 50° or 100°.
    private var dwellMargin: Double {
        guard let range = workingRange else { return 0.08 }
        return max(0.04, range * 0.1)
    }

    /// 0 at the top of the range, 1 at full depth.
    private func normalizedDepth(_ height: Double) -> Double {
        let high = observedMax ?? extendedHeight
        let low = observedMin ?? floorHeight
        let span = high - low
        guard span > 0 else { return 0 }
        return min(1, max(0, (high - height) / span))
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

    /// How far the chest rides above the hands, as a fraction of arm length.
    ///
    /// This is the measurement a push-up actually is, and the reason the
    /// tracker no longer counts anything off the elbow — see the file header.
    ///
    /// The ground reference is the **lower** of the two wrists: the hand
    /// still bearing weight. Using their midpoint let one lifted hand pull
    /// the reference up and fake a whole rep.
    ///
    /// Normalised by the person's own arm — shoulder to elbow to wrist, which
    /// is a constant whatever the elbow is doing — so body size cancels
    /// exactly rather than approximately. Torso length was the first choice
    /// and it's a worse one: it leaves the arm-to-torso ratio in the answer,
    /// and that varies enough between people to move the counting standard.
    /// Measured from world landmarks, so it holds at any camera angle
    /// (POSE.md Law 1).
    func chestHeight(_ pose: Pose) -> Double? {
        let confidence = min(
            self.confidence(pose, .leftShoulder, .rightShoulder),
            max(self.confidence(pose, .leftWrist), self.confidence(pose, .rightWrist))
        )
        guard confidence >= minConfidence,
              let shoulder = Self.midpoint(pose, .leftShoulder, .rightShoulder),
              let leftWrist = pose.worldPoint(.leftWrist),
              let rightWrist = pose.worldPoint(.rightWrist)
        else { return nil }

        // World y runs downward, so the planted hand is the *larger* y. The
        // whole arm is taken from that side — reference and normaliser both.
        // Averaging the two arms instead leaves the lifted one in the
        // denominator, and the exploit walks straight back in through it.
        let plantedIsLeft = leftWrist.y > rightWrist.y
        let ground = plantedIsLeft ? leftWrist.y : rightWrist.y
        guard let plantedShoulder = pose.worldPoint(plantedIsLeft ? .leftShoulder : .rightShoulder),
              let plantedElbow = pose.worldPoint(plantedIsLeft ? .leftElbow : .rightElbow)
        else { return nil }

        let plantedWrist = plantedIsLeft ? leftWrist : rightWrist
        let armLength = simd_length(plantedElbow - plantedShoulder)
            + simd_length(plantedWrist - plantedElbow)
        guard armLength > 0.15 else { return nil }

        return (ground - shoulder.y) / armLength
    }

    static func midpoint(_ pose: Pose, _ a: PoseJoint, _ b: PoseJoint) -> SIMD3<Double>? {
        guard let pa = pose.worldPoint(a), let pb = pose.worldPoint(b) else { return nil }
        return (pa + pb) / 2
    }

    /// Elbow angle from whichever arm is more visible — filming side-on means
    /// one arm is usually occluded by the body. Shown, never counted on.
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
