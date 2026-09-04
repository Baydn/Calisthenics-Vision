//
//  SampleTelemetry.swift
//  Calisthenics Vision
//
//  Synthetic per-frame telemetry for seeded debug sessions.
//
//  Everything that reads a set back — the post-set biometrics, the takeaways,
//  the angle charts — works off the telemetry file, and the Simulator has no
//  camera to produce one. Seeded sessions therefore showed "not enough
//  recorded telemetry" on every analysis screen, which made all of it
//  unreviewable without going and doing a set in front of a phone.
//
//  These frames are *generated*, not recorded: joints are placed to produce a
//  known joint angle rather than by simulating a body. That's the point —
//  a set whose depth per rep and line decay are known in advance is something
//  the analysis can be checked against. Compiled out of release builds, and
//  never written for a session the user actually recorded.
//

#if DEBUG

import Foundation
import simd

enum SampleTelemetry {

    /// Sampling rate of the generated stream. Real capture runs at 30; 20 is
    /// plenty for a seed and keeps the files small.
    private static let frameRate = 20.0

    /// Writes a telemetry file for a seeded session and points the session at
    /// it, filling in the rep marks that go with it.
    @MainActor
    static func attach(to session: WorkoutSession) {
        let frames: [(timestampMs: Int, points: [PoseJoint: SIMD3<Double>])]
        var repMarks: [Int] = []

        if session.movement == .handstand {
            frames = handstandFrames(session)
        } else if session.movement == .pushUps {
            let generated = pushUpFrames(session)
            frames = generated.frames
            repMarks = generated.repMarks
        } else {
            return
        }
        guard !frames.isEmpty else { return }

        guard let writer = try? TelemetryWriter(sessionID: session.id) else { return }
        for frame in frames {
            writer.append(timestampMs: frame.timestampMs, values: flatten(frame.points))
        }
        writer.finish()

        session.telemetryFileName = writer.fileName
        if !repMarks.isEmpty { session.repTimestampsMs = repMarks }
    }

    // MARK: - Push-ups

    /// A set of push-ups whose depth fades as it goes on, which is what a
    /// real set does and what the fatigue takeaway is looking for.
    private static func pushUpFrames(
        _ session: WorkoutSession
    ) -> (frames: [(timestampMs: Int, points: [PoseJoint: SIMD3<Double>])], repMarks: [Int]) {
        let reps = max(session.repCount, 1)
        let secondsPerRep = session.duration / Double(reps)
        guard secondsPerRep > 0.5 else { return ([], []) }

        var frames: [(Int, [PoseJoint: SIMD3<Double>])] = []
        var repMarks: [Int] = []

        let top = 168.0
        for rep in 0..<reps {
            let fatigue = Double(rep) / Double(max(reps - 1, 1))
            // Bottom angle climbs through the set: the first reps reach 72°,
            // the last ones stop 30° short of that.
            let bottom = 72 + 30 * pow(fatigue, 1.6)

            let stepCount = Int((secondsPerRep * frameRate).rounded())
            for step in 0...stepCount {
                let phase = Double(step) / Double(max(stepCount, 1))
                // Down and back up once per rep, held very briefly at each end.
                let depth = (1 - cos(phase * 2 * .pi)) / 2
                let elbow = top - (top - bottom) * depth

                let seconds = (Double(rep) + phase) * secondsPerRep
                frames.append((Int(seconds * 1000), pushUpPose(elbowAngle: elbow)))
            }
            repMarks.append(Int(Double(rep + 1) * secondsPerRep * 1000))
        }
        return (frames, repMarks)
    }

    /// A body laid out horizontally with the elbow bent to a chosen angle.
    private static func pushUpPose(elbowAngle: Double) -> [PoseJoint: SIMD3<Double>] {
        let radians = elbowAngle * .pi / 180

        // Shoulders at the origin, torso running along +x (head-to-toe
        // horizontal), arms dropping toward the floor in +y.
        var points: [PoseJoint: SIMD3<Double>] = [:]

        for side in [-1.0, 1.0] {
            let z = 0.18 * side
            let shoulder = SIMD3(0.0, 0.0, z)
            let elbow = shoulder + SIMD3(0.0, 0.28, 0.0)
            // Forearm rotated away from the upper arm by the target angle, so
            // the interior angle at the elbow is exactly `elbowAngle`.
            let forearm = SIMD3(sin(radians), -cos(radians), 0) * 0.28
            let wrist = elbow + forearm

            let hip = SIMD3(0.52, 0.02, z * 0.7)
            let knee = hip + SIMD3(0.42, 0.01, 0)
            let ankle = knee + SIMD3(0.42, 0.02, 0)

            let joints: [(PoseJoint, PoseJoint, SIMD3<Double>)] = [
                (.leftShoulder, .rightShoulder, shoulder),
                (.leftElbow, .rightElbow, elbow),
                (.leftWrist, .rightWrist, wrist),
                (.leftHip, .rightHip, hip),
                (.leftKnee, .rightKnee, knee),
                (.leftAnkle, .rightAnkle, ankle),
            ]
            for (left, right, value) in joints {
                points[side < 0 ? left : right] = value
            }
        }
        return points
    }

    // MARK: - Handstand

    /// One stretch of frames per recorded hold, positioned on the same clock
    /// the session's hold starts use, so the chart's window lines up with
    /// what's stored.
    private static func handstandFrames(
        _ session: WorkoutSession
    ) -> [(timestampMs: Int, points: [PoseJoint: SIMD3<Double>])] {
        var frames: [(Int, [PoseJoint: SIMD3<Double>])] = []

        for hold in session.holdSegments {
            // Mean deviation from straight that would score the line quality
            // this hold was seeded with, so the chart and the stored
            // percentage tell the same story.
            let meanDeviation = (1 - (hold.quality ?? 0.7)) * 90
            let stepCount = Int(hold.duration * frameRate)
            guard stepCount > 1 else { continue }

            for step in 0...stepCount {
                let progress = Double(step) / Double(stepCount)
                // Wobble on top of a line that opens as the hold goes on.
                let wobble = sin(progress * 14) * 3
                let shoulder = 180 - meanDeviation * (0.7 + 0.6 * progress) + wobble
                let hip = 180 - meanDeviation * 0.8 * (0.8 + 0.4 * progress) - wobble

                let seconds = progress * hold.duration
                frames.append((
                    hold.startTimestampMs + Int(seconds * 1000),
                    handstandPose(shoulderAngle: shoulder, hipAngle: hip)
                ))
            }
        }
        return frames.sorted { $0.0 < $1.0 }
    }

    /// An inverted body with chosen shoulder and hip angles. World y runs
    /// downward, so the hands are the largest y and the feet the smallest.
    private static func handstandPose(
        shoulderAngle: Double, hipAngle: Double
    ) -> [PoseJoint: SIMD3<Double>] {
        let shoulderRadians = shoulderAngle * .pi / 180
        let hipRadians = hipAngle * .pi / 180

        var points: [PoseJoint: SIMD3<Double>] = [:]

        for side in [-1.0, 1.0] {
            let z = 0.18 * side
            let shoulder = SIMD3(0.0, 0.0, z)
            let wrist = shoulder + SIMD3(0.0, 0.55, 0.0)      // hands on the floor
            let elbow = shoulder + SIMD3(0.0, 0.275, 0.0)

            // Torso set off the arm line by the shoulder angle.
            let hip = shoulder + SIMD3(sin(shoulderRadians), cos(shoulderRadians), 0) * 0.5

            // Legs set off the torso line by the hip angle, rotating in the
            // same plane.
            let toShoulder = simd_normalize(shoulder - hip)
            let rotated = SIMD3(
                toShoulder.x * cos(hipRadians) - toShoulder.y * sin(hipRadians),
                toShoulder.x * sin(hipRadians) + toShoulder.y * cos(hipRadians),
                0
            )
            let knee = hip + rotated * 0.42
            let ankle = hip + rotated * 0.84

            let joints: [(PoseJoint, PoseJoint, SIMD3<Double>)] = [
                (.leftShoulder, .rightShoulder, shoulder),
                (.leftElbow, .rightElbow, elbow),
                (.leftWrist, .rightWrist, wrist),
                (.leftHip, .rightHip, hip),
                (.leftKnee, .rightKnee, knee),
                (.leftAnkle, .rightAnkle, ankle),
            ]
            for (left, right, value) in joints {
                points[side < 0 ? left : right] = value
            }
        }
        return points
    }

    // MARK: - Encoding

    /// Packs a joint dictionary into the flat `[x, y, wx, wy, wz]` record the
    /// telemetry file stores. The drawn 2D points are a plain orthographic
    /// projection of the world ones — enough for the review overlay to look
    /// like a body, and never used for measurement.
    private static func flatten(_ points: [PoseJoint: SIMD3<Double>]) -> [Float] {
        var values = [Float](repeating: 0, count: Telemetry.valueCount)
        for (joint, world) in points {
            let base = joint.rawValue * Telemetry.valuesPerLandmark
            values[base] = Float(min(max(0.5 + world.x * 0.55, 0), 1))
            values[base + 1] = Float(min(max(0.5 + world.y * 0.55, 0), 1))
            values[base + 2] = Float(world.x)
            values[base + 3] = Float(world.y)
            values[base + 4] = Float(world.z)
        }
        return values
    }
}

#endif
