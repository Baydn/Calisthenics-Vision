//
//  PoseSkeleton.swift
//  Calisthenics Vision
//
//  MediaPipe's 33-point pose topology, plus the joint-angle math the movement
//  state machines are built on (SPEC.md §"Math & State Engine").
//

import CoreGraphics
import Foundation

/// Indices into MediaPipe's 33-landmark pose model.
enum PoseJoint: Int, CaseIterable {
    case nose = 0
    case leftShoulder = 11, rightShoulder = 12
    case leftElbow = 13, rightElbow = 14
    case leftWrist = 15, rightWrist = 16
    case leftHip = 23, rightHip = 24
    case leftKnee = 25, rightKnee = 26
    case leftAnkle = 27, rightAnkle = 28
}

/// One detected pose: normalized (0…1) points in image space.
struct Pose {
    /// 33 points, indexed by `PoseJoint`.
    let points: [CGPoint]
    /// Per-landmark presence confidence, same ordering.
    let confidence: [Float]

    func point(_ joint: PoseJoint) -> CGPoint? {
        let index = joint.rawValue
        guard index < points.count else { return nil }
        return points[index]
    }

    /// Interior angle at `vertex`, in degrees, formed by the two other joints.
    ///
    /// This is the primitive behind every movement rule — e.g. a push-up's
    /// elbow angle is `angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)`.
    func angle(at vertex: PoseJoint, from first: PoseJoint, to second: PoseJoint) -> Double? {
        guard let v = point(vertex), let a = point(first), let b = point(second) else { return nil }

        let u = CGVector(dx: a.x - v.x, dy: a.y - v.y)
        let w = CGVector(dx: b.x - v.x, dy: b.y - v.y)

        let dot = u.dx * w.dx + u.dy * w.dy
        let magnitude = sqrt(u.dx * u.dx + u.dy * u.dy) * sqrt(w.dx * w.dx + w.dy * w.dy)
        guard magnitude > 0 else { return nil }

        // Clamped because floating-point error can push the ratio just past ±1.
        let cosine = max(-1, min(1, dot / magnitude))
        return Double(acos(cosine)) * 180 / Double.pi
    }

    /// Bones drawn by the HUD overlay.
    static let connections: [(PoseJoint, PoseJoint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]
}

// MARK: - Smoothing

/// Exponential moving average over landmark positions.
///
/// Raw per-frame landmarks jitter enough to trip angle thresholds on and off,
/// which would double-count reps. Smoothing before the state machine sees the
/// values is what makes the counts stable (SPEC.md §"Math & State Engine").
struct PoseSmoother {
    /// Higher favors the newest frame; lower is steadier but lags.
    var factor: Double = 0.6

    private var previous: [CGPoint]?

    mutating func smooth(_ pose: Pose) -> Pose {
        guard let previous, previous.count == pose.points.count else {
            self.previous = pose.points
            return pose
        }

        let blended = zip(previous, pose.points).map { old, new in
            CGPoint(
                x: old.x + (new.x - old.x) * factor,
                y: old.y + (new.y - old.y) * factor
            )
        }
        self.previous = blended
        return Pose(points: blended, confidence: pose.confidence)
    }

    mutating func reset() { previous = nil }
}
