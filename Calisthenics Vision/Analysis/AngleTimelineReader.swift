//
//  AngleTimelineReader.swift
//  Calisthenics Vision
//
//  Reads a finished session's telemetry off disk and hands the angles to
//  AngleBands, which does the banding.
//
//  Split from it so the maths stays harness-pure (POSE.md §12) and this half
//  is the only part that knows about files, sessions, or which window of a
//  recording is worth plotting.
//

import Foundation

enum AngleTimelineBuilder {

    /// Every timeline worth drawing for a finished set, or an empty array
    /// when there's nothing measurable — the caller draws nothing at all
    /// rather than an empty card.
    static func timelines(for session: WorkoutSession) -> [AngleTimeline] {
        guard let url = session.telemetryURL, let reader = TelemetryReader(url: url),
              reader.frameCount > 0
        else { return [] }

        return session.movement.isTimedHold
            ? holdTimelines(session, reader)
            : repTimelines(session, reader)
    }

    // MARK: - Windows

    private static func holdTimelines(
        _ session: WorkoutSession, _ reader: TelemetryReader
    ) -> [AngleTimeline] {
        // Which measurements a hold is judged on is per-movement — a planche
        // is judged level first, a handstand against a plumb line. Anything
        // without its own answer here gets no charts rather than the
        // handstand's, which would be measuring the wrong thing confidently.
        guard session.movement == .handstand || session.movement == .planche else { return [] }

        // The longest attempt, not the whole recording: the walk-in, the
        // kick-up and the fall aren't the hold, and averaged into it they
        // would drag every band down.
        guard let longest = session.holdSegments.max(by: { $0.duration < $1.duration }),
              longest.duration >= 2
        else { return [] }

        let start = longest.startTimestampMs
        let window = start...(start + Int(longest.duration * 1000))
        let subtitle = session.holdSegments.count > 1
            ? "Longest hold · \(SessionResult.preciseDurationLabel(longest.duration))"
            : nil

        if session.movement == .planche {
            return AngleBands.plancheTimelines(
                level: series(reader, window: window) { pose in
                    guard let reading = PlancheGeometry.read(pose), reading.isMeasurable
                    else { return nil }
                    return reading.levelDeviation
                },
                straight: series(reader, window: window) { pose in
                    // Straightness only where the legs were extended, exactly
                    // as the live score does it (`PlancheGeometry.Reading`).
                    guard let reading = PlancheGeometry.read(pose), reading.isMeasurable,
                          let straightness = reading.straightness
                    else { return nil }
                    return abs(180 - straightness)
                },
                subtitle: subtitle
            )
        }

        return AngleBands.handstandTimelines(
            shoulder: angles(reader, joint: (.leftShoulder, .leftWrist, .leftHip), window: window),
            hip: angles(reader, joint: (.leftHip, .leftShoulder, .leftAnkle), window: window),
            subtitle: subtitle
        )
    }

    /// Reads one measurement off every frame in the window.
    ///
    /// The sibling of `angles`, for measurements that aren't a joint triple —
    /// a planche's level is the torso against gravity, which no three joints
    /// describe. Frames the measurement can't speak to are dropped rather
    /// than filled in (POSE.md Law 8), so a gap in the chart means a gap in
    /// what was knowable.
    private static func series(
        _ reader: TelemetryReader,
        window: ClosedRange<Int>?,
        _ measure: (Pose) -> Double?
    ) -> [(Int, Double)] {
        var points: [(Int, Double)] = []
        points.reserveCapacity(reader.frameCount)

        for i in 0..<reader.frameCount {
            if let window {
                guard let t = reader.timestampMs(at: i), window.contains(Int(t)) else { continue }
            }
            guard let frame = reader.frame(at: i) else { continue }
            let pose = Pose(points: [], confidence: [], worldPoints: frame.worldPoints)
            guard let value = measure(pose) else { continue }
            points.append((Int(frame.timestampMs), value))
        }
        return points
    }

    private static func repTimelines(
        _ session: WorkoutSession, _ reader: TelemetryReader
    ) -> [AngleTimeline] {
        guard let joint = AngleBands.drivingJoint(for: session.movement) else { return [] }

        return AngleBands.repTimelines(
            points: angles(reader, joint: joint, window: nil),
            movement: session.movement,
            repCount: session.repCount
        )
    }

    // MARK: - Sampling

    /// Reads one joint angle from every frame in the window, on both sides,
    /// and settles on the side the data says was doing the work.
    private static func angles(
        _ reader: TelemetryReader,
        joint: (PoseJoint, PoseJoint, PoseJoint),
        window: ClosedRange<Int>?
    ) -> [(Int, Double)] {
        var samples: [AngleBands.SidedSample] = []
        samples.reserveCapacity(reader.frameCount)

        for i in 0..<reader.frameCount {
            // Timestamp first: a long recording's frames outside the window
            // shouldn't be decoded just to be discarded.
            if let window {
                guard let t = reader.timestampMs(at: i), window.contains(Int(t)) else { continue }
            }
            guard let frame = reader.frame(at: i) else { continue }

            let pose = Pose(points: [], confidence: [], worldPoints: frame.worldPoints)
            samples.append(AngleBands.SidedSample(
                timestampMs: Int(frame.timestampMs),
                left: pose.angle(at: joint.0, from: joint.1, to: joint.2),
                right: pose.angle(
                    at: AngleBands.mirrored(joint.0),
                    from: AngleBands.mirrored(joint.1),
                    to: AngleBands.mirrored(joint.2)
                )
            ))
        }
        return AngleBands.pick(samples)
    }
}
