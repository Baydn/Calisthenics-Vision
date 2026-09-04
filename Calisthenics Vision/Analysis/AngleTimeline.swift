//
//  AngleTimeline.swift
//  Calisthenics Vision
//
//  The angle that defines a movement, plotted for a set, split into the bands
//  that mean something for *that* movement.
//
//  The summary already says how it went in words. This says it in shape: a
//  handstand's shoulder opening as the hold goes on, a push-up's depth
//  creeping up rep by rep. Both are obvious in a line and invisible in a
//  number, and the telemetry to draw them has been on disk since the first
//  session — nothing new is recorded for this.
//
//  Two rules decide how the bands are drawn, and they differ by movement on
//  purpose:
//
//  · A hold is scored against geometry. 180° is a straight line whoever you
//    are, so the bands are absolute and match what HandstandTracker scores
//    live — the chart and the LINE percentage can never disagree.
//  · A rep is scored against *your own* range (POSE.md Law 3). Fixed
//    thresholds counted nothing for a person whose lockout was 150°, so the
//    bands here are cut from the range this set actually showed. "Deep" means
//    the bottom of your range, not a number from a textbook.
//
//  POSE.md Law 8 applies throughout: a set with too little to say produces no
//  timeline at all, rather than an empty chart.
//
//  This file is pure — angles in, timelines out, no storage and no SwiftData —
//  so it compiles into the standalone test harness the same way the trackers
//  do (POSE.md §12). AngleTimelineReader is the half that reads a session off
//  disk.
//

import Foundation

/// One band of the angle range, with what being in it means.
struct AngleZone: Identifiable {
    enum Tone {
        /// The range the movement is aiming for.
        case good
        /// Acceptable, but not what you're working toward.
        case fair
        /// Far enough out to be the thing to fix.
        case poor
        /// A phase of a rep, not a grade — nothing is wrong with being at
        /// lockout, it's half of every rep.
        case neutral
    }

    var id: String { name }
    let name: String
    /// Degrees. Half-open at the top so the bands tile without overlap.
    let lower: Double
    let upper: Double
    let tone: Tone

    func contains(_ angle: Double) -> Bool {
        angle >= lower && (angle < upper || upper >= 180)
    }
}

/// An angle worth plotting, already sampled and banded.
struct AngleTimeline: Identifiable {
    struct Sample {
        /// Seconds from the start of the plotted window.
        let seconds: Double
        /// Capture-clock instant, so a tap on the chart can seek the video.
        let timestampMs: Int
        let degrees: Double
    }

    var id: String { title }
    /// e.g. "SHOULDER ANGLE".
    let title: String
    /// What window this covers, when it isn't the whole set.
    let subtitle: String?
    /// Plain-English explanation of the bands, shown behind the ⓘ.
    let explanation: String
    let samples: [Sample]
    /// Ordered best-first, which is also top-to-bottom on the chart.
    let zones: [AngleZone]
    /// Share of the plotted time spent in each zone, 0…1, weighted by real
    /// elapsed time rather than by frame count — a dropped frame shouldn't
    /// change the percentages.
    let shares: [String: Double]
    let duration: Double
    /// Degrees at the bottom and top of the drawn chart.
    let displayRange: ClosedRange<Double>

    func share(of zone: AngleZone) -> Double { shares[zone.name] ?? 0 }
}

enum AngleBands {

    /// One frame's reading of the same joint on both sides of the body.
    struct SidedSample {
        let timestampMs: Int
        let left: Double?
        let right: Double?
    }


    /// Longest gap between frames that still counts as elapsed time. Beyond
    /// it, tracking was lost, and crediting the gap to whichever zone the
    /// last frame happened to be in would be inventing data.
    private static let maxFrameGapMs = 500

    /// Picks one side for the whole window and keeps it.
    ///
    /// Telemetry carries no per-landmark confidence, so there's no
    /// "which side is trustworthy" to read — but a side that's occluded or
    /// guessed sits nearly still while the working side sweeps a real range.
    /// Choosing per frame instead would splice two different measurements
    /// into one line and put a step in it where nothing happened.
    static func pick(_ samples: [SidedSample]) -> [(Int, Double)] {
        func range(_ values: [Double]) -> Double {
            guard let lo = values.min(), let hi = values.max() else { return -1 }
            return hi - lo
        }
        let left = samples.compactMap(\.left)
        let right = samples.compactMap(\.right)

        // Prefer the side that was actually visible; between two visible
        // sides, the one that moved.
        let useLeft: Bool
        if left.isEmpty || right.isEmpty {
            useLeft = !left.isEmpty
        } else {
            useLeft = range(left) >= range(right)
        }

        return samples.compactMap { sample in
            guard let value = useLeft ? sample.left : sample.right else { return nil }
            return (sample.timestampMs, value)
        }
    }

    /// Time-weighted share of each zone.
    static func shares(_ points: [(Int, Double)], _ zones: [AngleZone]) -> [String: Double] {
        var totals: [String: Double] = [:]
        var total: Double = 0

        for (index, point) in points.enumerated() {
            // A sample is credited with the time until the next one, which is
            // the interval it actually describes.
            let next = index + 1 < points.count ? points[index + 1].0 : point.0
            let delta = min(max(next - point.0, 0), maxFrameGapMs)
            guard delta > 0 else { continue }
            guard let zone = zones.first(where: { $0.contains(point.1) }) else { continue }
            totals[zone.name, default: 0] += Double(delta)
            total += Double(delta)
        }
        guard total > 0 else { return [:] }
        return totals.mapValues { $0 / total }
    }

    /// Thins the series to something a chart can draw, averaging within each
    /// bucket so a spike isn't lost to whichever frame the stride landed on.
    static func downsample(_ points: [(Int, Double)], to limit: Int) -> [(Int, Double)] {
        guard points.count > limit, limit > 0 else { return points }

        let bucketSize = Double(points.count) / Double(limit)
        var result: [(Int, Double)] = []
        result.reserveCapacity(limit)

        for bucket in 0..<limit {
            let start = Int(Double(bucket) * bucketSize)
            let end = min(points.count, Int(Double(bucket + 1) * bucketSize))
            guard start < end else { continue }
            let slice = points[start..<end]
            let mean = slice.reduce(0.0) { $0 + $1.1 } / Double(slice.count)
            result.append((slice[slice.startIndex].0, mean))
        }
        return result
    }

    static func mirrored(_ joint: PoseJoint) -> PoseJoint { joint.mirrored }

    /// Assembles a timeline, or nil if the window turned out to hold too
    /// little to plot.
    static func make(
        title: String,
        subtitle: String?,
        explanation: String,
        points: [(Int, Double)],
        zones: [AngleZone],
        displayRange: ClosedRange<Double>
    ) -> AngleTimeline? {
        guard points.count >= 8, let start = points.first?.0, let end = points.last?.0 else {
            return nil
        }
        let duration = Double(end - start) / 1000
        guard duration >= 1 else { return nil }

        let zoneShares = shares(points, zones)
        let drawn = downsample(points, to: 220).map {
            AngleTimeline.Sample(
                seconds: Double($0.0 - start) / 1000,
                timestampMs: $0.0,
                degrees: $0.1
            )
        }

        return AngleTimeline(
            title: title,
            subtitle: subtitle,
            explanation: explanation,
            samples: drawn,
            zones: zones,
            shares: zoneShares,
            duration: duration,
            displayRange: displayRange
        )
    }

    // MARK: - Holds

    /// The bands a handstand's shoulder angle is read against.
    static let handstandShoulderZones = [
        AngleZone(name: "Stacked", lower: 165, upper: 180, tone: .good),
        AngleZone(name: "Open", lower: 140, upper: 165, tone: .fair),
        AngleZone(name: "Piked", lower: 0, upper: 140, tone: .poor),
    ]

    /// …and its hip angle.
    static let handstandHipZones = [
        AngleZone(name: "Straight", lower: 168, upper: 180, tone: .good),
        AngleZone(name: "Soft", lower: 150, upper: 168, tone: .fair),
        AngleZone(name: "Piked", lower: 0, upper: 150, tone: .poor),
    ]

    /// Bands for the angle a movement is judged at, where that angle is
    /// graded against geometry rather than against your own range.
    ///
    /// Nil for rep movements on purpose: the overlay would have to invent a
    /// fixed threshold to colour a push-up's elbow, and fixed thresholds are
    /// what POSE.md Law 3 exists to keep out. Those are drawn white.
    static func focusZones(for movement: Movement) -> [AngleZone]? {
        movement == .handstand ? handstandShoulderZones : nil
    }

    /// The two angles a handstand is judged on, over one hold.
    static func handstandTimelines(
        shoulder: [(Int, Double)], hip: [(Int, Double)], subtitle: String?
    ) -> [AngleTimeline] {
        var result: [AngleTimeline] = []

        if let timeline = make(
            title: "SHOULDER ANGLE",
            subtitle: subtitle,
            explanation: """
            The angle between your arms and your torso. Stacked means your \
            shoulders are open over your hands, which is what holds a \
            handstand up with the least effort. Piked means they're closed \
            and your hips are behind your hands, so your arms are doing the \
            work your skeleton should be doing.
            """,
            points: shoulder,
            zones: handstandShoulderZones,
            displayRange: displayRange(for: shoulder, floor: 110, ceiling: 180)
        ) {
            result.append(timeline)
        }

        if let timeline = make(
            title: "HIP ANGLE",
            subtitle: subtitle,
            explanation: """
            How straight your body is from shoulder to ankle. Straight is a \
            line; piked is the banana most handstands start as. This is the \
            half of the line score you can fix with hollow work rather than \
            with shoulder mobility.
            """,
            points: hip,
            zones: handstandHipZones,
            displayRange: displayRange(for: hip, floor: 120, ceiling: 180)
        ) {
            result.append(timeline)
        }

        return result
    }

    static func displayRange(
        for points: [(Int, Double)], floor: Double, ceiling: Double
    ) -> ClosedRange<Double> {
        let values = points.map(\.1)
        let low = min(floor, (values.min() ?? floor) - 4)
        return max(0, low)...ceiling
    }

    // MARK: - Reps

    /// The one angle a rep movement is driven by, over the whole set.
    static func repTimelines(
        points: [(Int, Double)], movement: Movement, repCount: Int
    ) -> [AngleTimeline] {
        guard let low = points.map(\.1).min(), let high = points.map(\.1).max(),
              high - low >= 20      // below this nothing rep-shaped happened
        else { return [] }

        // Bands cut from this set's own range, thirds of it. Absolute
        // thresholds are exactly what Law 3 exists to prevent.
        let span = high - low
        let deepTop = low + span * 0.34
        let midTop = low + span * 0.72

        let names = phaseNames(for: movement)
        let zones = [
            AngleZone(name: names.extended, lower: midTop, upper: 180, tone: .neutral),
            AngleZone(name: names.middle, lower: deepTop, upper: midTop, tone: .neutral),
            AngleZone(name: names.deep, lower: 0, upper: deepTop, tone: .good),
        ]

        return [make(
            title: "\(names.jointLabel) ANGLE",
            subtitle: "\(repCount) rep\(repCount == 1 ? "" : "s")",
            explanation: """
            Every rep as it happened, measured at the \
            \(names.jointLabel.lowercased()). The bands are cut from your own \
            range in this set, not from a fixed number — \(names.deep.lowercased()) \
            is the deepest third of what you actually did. Reps that stop \
            short of the band you started in are where depth began to go.
            """,
            points: points,
            zones: zones,
            displayRange: (low - 5)...(high + 5)
        )].compactMap { $0 }
    }

    static func drivingJoint(for movement: Movement) -> (PoseJoint, PoseJoint, PoseJoint)? {
        switch movement {
        case .pushUps, .pullUps, .dip: (.leftElbow, .leftShoulder, .leftWrist)
        case .squat:                   (.leftKnee, .leftHip, .leftAnkle)
        default:                       nil
        }
    }

    /// What the three phases of a rep are called for this movement — the top
    /// of a pull-up and the bottom of a push-up are both "the finished
    /// position", and calling either one "deep" would read as wrong to
    /// anyone who trains.
    static func phaseNames(
        for movement: Movement
    ) -> (jointLabel: String, deep: String, middle: String, extended: String) {
        switch movement {
        case .pushUps: ("ELBOW", "Deep", "Mid rep", "Lockout")
        case .dip:     ("ELBOW", "Deep", "Mid rep", "Lockout")
        case .pullUps: ("ELBOW", "Chin over", "Mid pull", "Dead hang")
        case .squat:   ("KNEE", "Deep", "Mid squat", "Standing")
        default:       ("JOINT", "Deep", "Mid", "Extended")
        }
    }
}
