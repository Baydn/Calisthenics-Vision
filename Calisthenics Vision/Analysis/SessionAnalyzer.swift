//
//  SessionAnalyzer.swift
//  Calisthenics Vision
//
//  Turns a recorded set's telemetry into a few things worth knowing —
//  post-hoc, over data already on disk. Nothing here runs live and nothing
//  here can affect a count or a hold time; it reads what happened after the
//  fact, the same way a coach reviewing the tape would.
//
//  This is the analysis every rival is missing. A form score is a number with
//  no explanation; this can say *which* joint, *when* in the set, and *by how
//  much* — because the telemetry log already has every frame, and nothing
//  else in the category keeps one.
//
//  Two rules from POSE.md apply directly here and nowhere more strictly:
//  Law 5 — say nothing you can't measure. Telemetry carries no confidence
//  (SessionReviewView reconstructs review poses the same way, confidence
//  filled with 1), so degenerate geometry is discarded rather than reported.
//  Law 8 — unmeasurable is absent, never zero. A metric that can't be
//  computed for this set is left out of the list, not shown as "0%".
//

import Foundation
import simd

/// One thing worth telling the user about the set, in the past tense, with
/// the frame that justifies it when there is one. A takeaway that can't point
/// at a moment is still a takeaway — not every finding is about a moment.
struct Takeaway: Identifiable {
    let id = UUID()
    let text: String
    /// Capture-clock instant to jump to in review, if this points at one.
    var timestampMs: Int?
}

struct SessionAnalysis {
    var metrics: [(label: String, value: String)]
    var takeaways: [Takeaway]
}

enum SessionAnalyzer {

    /// nil when there's nothing to say — no telemetry, or too little motion
    /// to draw a conclusion from. A screen with nothing to show should show
    /// nothing, not a manufactured finding.
    static func analyze(_ session: WorkoutSession) -> SessionAnalysis? {
        guard let url = session.telemetryURL, let reader = TelemetryReader(url: url),
              reader.frameCount > 0
        else { return nil }

        return session.movement.isTimedHold
            ? analyzeHold(session, reader)
            : analyzeReps(session, reader)
    }

    // MARK: - Rep movements

    /// The angle this movement is driven by, as a joint triple.
    private static func drivingJoint(for movement: Movement) -> (PoseJoint, PoseJoint, PoseJoint)? {
        switch movement {
        case .pushUps, .pullUps, .dip:
            (.leftElbow, .leftShoulder, .leftWrist)     // mirrored automatically below
        case .squat:
            (.leftKnee, .leftHip, .leftAnkle)
        default:
            nil
        }
    }

    private static func mirrored(_ joint: PoseJoint) -> PoseJoint {
        switch joint {
        case .leftElbow: .rightElbow
        case .leftShoulder: .rightShoulder
        case .leftWrist: .rightWrist
        case .leftKnee: .rightKnee
        case .leftHip: .rightHip
        case .leftAnkle: .rightAnkle
        default: joint
        }
    }

    private static func analyzeReps(_ session: WorkoutSession, _ reader: TelemetryReader) -> SessionAnalysis? {
        guard let (vertex, from, to) = drivingJoint(for: session.movement) else { return nil }
        let marks = session.repTimestampsMs.sorted()
        guard marks.count >= 2 else { return nil }   // one rep has no "across reps" to say anything about

        // Read every frame once, compute both sides, and — since telemetry
        // carries no per-landmark confidence — pick whichever side actually
        // moved. A side that's occluded or an estimate sits nearly still;
        // the side performing the rep sweeps a real range. This is the one
        // rule used throughout: never a guess at which side is "correct",
        // only which one the data shows moving.
        struct Sample { let t: Int; let left: Double?; let right: Double? }
        var samples: [Sample] = []
        samples.reserveCapacity(reader.frameCount)
        for i in 0..<reader.frameCount {
            guard let frame = reader.frame(at: i) else { continue }
            let pose = Pose(points: [], confidence: [], worldPoints: frame.worldPoints)
            samples.append(Sample(
                t: Int(frame.timestampMs),
                left: pose.angle(at: vertex, from: from, to: to),
                right: pose.angle(at: mirrored(vertex), from: mirrored(from), to: mirrored(to))
            ))
        }
        guard !samples.isEmpty else { return nil }

        func range(_ pick: (Sample) -> Double?) -> Double {
            let values = samples.compactMap(pick)
            guard let lo = values.min(), let hi = values.max() else { return 0 }
            return hi - lo
        }
        let useLeft = range { $0.left } >= range { $0.right }
        let angle: (Sample) -> Double? = useLeft ? { $0.left } : { $0.right }

        let overall = samples.compactMap(angle)
        guard let sessionMin = overall.min(), let sessionMax = overall.max(),
              sessionMax - sessionMin >= 20     // below this it isn't really a rep motion
        else { return nil }
        let span = sessionMax - sessionMin

        // One window per rep: from the previous completion (or the first
        // frame) to this one.
        var windows: [(start: Int, end: Int)] = []
        var previous = samples.first!.t
        for mark in marks {
            windows.append((previous, mark))
            previous = mark
        }

        struct RepReading {
            let index: Int
            let depthFraction: Double        // 0 at lockout, 1 at the deepest point of the session
            let bottomTimestamp: Int
            let eccentricSeconds: Double
            let concentricSeconds: Double
        }

        var reps: [RepReading] = []
        for (index, window) in windows.enumerated() {
            let inWindow = samples.filter { $0.t >= window.start && $0.t <= window.end }
            let points = inWindow.compactMap { s -> (Int, Double)? in
                guard let a = angle(s) else { return nil }
                return (s.t, a)
            }
            guard let deepest = points.min(by: { $0.1 < $1.1 }) else { continue }

            let depthFraction = (sessionMax - deepest.1) / span
            let descending = points.filter { $0.0 <= deepest.0 }
            let ascending = points.filter { $0.0 >= deepest.0 }
            let eccentric = descending.isEmpty ? 0 : Double(deepest.0 - (descending.first?.0 ?? deepest.0)) / 1000
            let concentric = ascending.isEmpty ? 0 : Double((ascending.last?.0 ?? deepest.0) - deepest.0) / 1000

            reps.append(RepReading(
                index: index + 1, depthFraction: depthFraction, bottomTimestamp: deepest.0,
                eccentricSeconds: eccentric, concentricSeconds: concentric
            ))
        }
        guard reps.count >= 2 else { return nil }

        var metrics: [(String, String)] = []

        let depths = reps.map(\.depthFraction)
        if let worst = depths.min(), let best = depths.max() {
            let consistency = max(0, 100 - (best - worst) * 100)
            metrics.append(("Depth consistency", "\(Int(consistency.rounded()))%"))
        }

        let avgEccentric = reps.map(\.eccentricSeconds).reduce(0, +) / Double(reps.count)
        let avgConcentric = reps.map(\.concentricSeconds).reduce(0, +) / Double(reps.count)
        if avgEccentric > 0 || avgConcentric > 0 {
            metrics.append(("Tempo", String(format: "%.1fs down / %.1fs up", avgEccentric, avgConcentric)))
        }

        metrics.append(("Reps analysed", "\(reps.count)"))

        // Takeaway: find the point depth fell away and stayed away — the
        // clearest signature of fatigue setting in.
        var takeaways: [Takeaway] = []
        if reps.count >= 4 {
            let bestDepth = depths.max() ?? 0
            if bestDepth > 0 {
                // First rep, scanning forward, after which every remaining
                // rep is at least 15 points shallower than the best. A single
                // shallow rep in the middle isn't fatigue; a sustained drop is.
                var fatigueStart: RepReading?
                for candidate in reps {
                    let remaining = reps[(candidate.index - 1)...]
                    if remaining.allSatisfy({ bestDepth - $0.depthFraction >= 0.15 }) {
                        fatigueStart = candidate
                        break
                    }
                }
                if let fatigueStart {
                    // Average depth from the fatigue point onward, compared
                    // against the best rep — the number the sentence quotes.
                    let affected = reps[(fatigueStart.index - 1)...]
                    let affectedAvg = affected.map(\.depthFraction).reduce(0, +) / Double(affected.count)
                    let dropPercent = Int(((bestDepth - affectedAvg) * 100).rounded())
                    let heldFor = fatigueStart.index - 1
                    takeaways.append(Takeaway(
                        text: "Depth held for \(heldFor) rep\(heldFor == 1 ? "" : "s"), then fell away by rep \(fatigueStart.index)\(dropPercent > 0 ? " — about \(dropPercent)% shallower" : "").",
                        timestampMs: fatigueStart.bottomTimestamp
                    ))
                } else {
                    takeaways.append(Takeaway(text: "Depth held steady across all \(reps.count) reps — no fatigue drop-off."))
                }
            }
        }

        return SessionAnalysis(metrics: metrics, takeaways: takeaways)
    }

    // MARK: - Handstand

    private static func analyzeHold(_ session: WorkoutSession, _ reader: TelemetryReader) -> SessionAnalysis? {
        guard session.movement == .handstand else { return nil }
        let holds = session.holdSegments
        guard let longest = holds.max(by: { $0.duration < $1.duration }), longest.duration >= 3 else {
            return nil     // too brief to say anything about how it changed
        }

        let windowStart = Int32(longest.startTimestampMs)
        let windowEnd = Int32(longest.startTimestampMs + Int(longest.duration * 1000))

        struct Sample { let t: Int; let shoulder: Double?; let hip: Double?; let hipPoint: SIMD3<Double>? }
        var samples: [Sample] = []
        for i in 0..<reader.frameCount {
            guard let frame = reader.frame(at: i), frame.timestampMs >= windowStart, frame.timestampMs <= windowEnd
            else { continue }
            let pose = Pose(points: [], confidence: [], worldPoints: frame.worldPoints)

            // Same principle as the rep analysis: pick whichever side shows
            // real motion/geometry rather than guessing from confidence we
            // don't have. For a single frame that means "not degenerate".
            let shoulder = pose.angle(at: .leftShoulder, from: .leftWrist, to: .leftHip)
                ?? pose.angle(at: .rightShoulder, from: .rightWrist, to: .rightHip)
            let hip = pose.angle(at: .leftHip, from: .leftShoulder, to: .leftAnkle)
                ?? pose.angle(at: .rightHip, from: .rightShoulder, to: .rightAnkle)

            let hipPoint: SIMD3<Double>?
            if let l = pose.worldPoint(.leftHip), let r = pose.worldPoint(.rightHip) {
                hipPoint = (l + r) / 2
            } else {
                hipPoint = nil
            }

            samples.append(Sample(t: Int(frame.timestampMs), shoulder: shoulder, hip: hip, hipPoint: hipPoint))
        }
        guard samples.count >= 6 else { return nil }   // need enough frames for thirds to mean anything

        // Same scoring as HandstandTracker.currentQuality — worst joint, not
        // the average — so this reads consistently with the live LINE score.
        func quality(_ s: Sample) -> Double? {
            let angles = [s.shoulder, s.hip].compactMap { $0 }
            guard !angles.isEmpty else { return nil }
            let worst = angles.map { abs(180 - $0) }.max() ?? 0
            return max(0, 1 - worst / 90)
        }

        let third = samples.count / 3
        guard third > 0 else { return nil }
        let first = samples.prefix(third).compactMap(quality)
        let last = samples.suffix(third).compactMap(quality)
        guard !first.isEmpty, !last.isEmpty else { return nil }

        let firstAvg = first.reduce(0, +) / Double(first.count)
        let lastAvg = last.reduce(0, +) / Double(last.count)

        var metrics: [(String, String)] = [
            ("First third", "\(Int((firstAvg * 100).rounded()))%"),
            ("Last third", "\(Int((lastAvg * 100).rounded()))%"),
        ]

        // Sway: how far the hip midpoint actually travelled in the plane
        // perpendicular to gravity, in centimetres.
        let hipPoints = samples.compactMap(\.hipPoint)
        if hipPoints.count >= 6 {
            let xs = hipPoints.map(\.x), zs = hipPoints.map(\.z)
            if let xLo = xs.min(), let xHi = xs.max(), let zLo = zs.min(), let zHi = zs.max() {
                let sway = max(xHi - xLo, zHi - zLo) * 100   // metres → cm
                metrics.append(("Sway", String(format: "%.0f cm", sway)))
            }
        }

        var takeaways: [Takeaway] = []
        let decay = firstAvg - lastAvg
        if decay >= 0.10 {
            // Which joint actually drove the decay, so the takeaway names
            // the real cause rather than just the symptom.
            let shoulderFirst = samples.prefix(third).compactMap(\.shoulder).map { abs(180 - $0) }
            let shoulderLast = samples.suffix(third).compactMap(\.shoulder).map { abs(180 - $0) }
            let hipFirst = samples.prefix(third).compactMap(\.hip).map { abs(180 - $0) }
            let hipLast = samples.suffix(third).compactMap(\.hip).map { abs(180 - $0) }

            func avg(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
            let shoulderDrift = avg(shoulderLast) - avg(shoulderFirst)
            let hipDrift = avg(hipLast) - avg(hipFirst)
            let culprit = shoulderDrift >= hipDrift ? "shoulder" : "hip"

            takeaways.append(Takeaway(
                text: "Your line held at \(Int((firstAvg * 100).rounded()))% early on and dropped to \(Int((lastAvg * 100).rounded()))% by the end — the \(culprit) opened as the hold went on.",
                timestampMs: samples[samples.count - third].t
            ))
        } else {
            takeaways.append(Takeaway(
                text: "Line stayed steady for the whole hold — no meaningful drop from start to finish."
            ))
        }

        return SessionAnalysis(metrics: metrics, takeaways: takeaways)
    }
}
