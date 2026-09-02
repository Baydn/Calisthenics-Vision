//
//  PoseSkeleton.swift
//  Calisthenics Vision
//
//  MediaPipe's 33-point pose topology, plus the joint-angle math the movement
//  state machines are built on.
//
//  POSE.md is the normative spec for this file: coordinate spaces, the angle
//  primitive, confidence tiers, and the rules every tracker follows. Read it
//  before changing anything here.
//

import CoreGraphics
import Foundation
import simd

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

    /// Source frame width ÷ height.
    ///
    /// Landmarks are normalized independently on each axis, so on a 9:16 frame
    /// one normalized unit of x is a very different real distance from one unit
    /// of y. Angles measured without undoing that are wrong for anything not
    /// axis-aligned, so every angle here works in aspect-corrected space.
    let aspect: CGFloat

    /// Metric 3D landmarks in meters, origin at the hip midpoint.
    ///
    /// All angle math uses these. The 2D projection can't measure a joint
    /// whose motion runs along the camera axis — facing the lens during a
    /// push-up collapses the whole torso to a few pixels — whereas world
    /// coordinates are view-independent. `points` stays for drawing only.
    let worldPoints: [SIMD3<Double>]

    init(
        points: [CGPoint],
        confidence: [Float],
        aspect: CGFloat = 1,
        worldPoints: [SIMD3<Double>] = []
    ) {
        self.points = points
        self.confidence = confidence
        self.aspect = aspect
        self.worldPoints = worldPoints
    }

    func worldPoint(_ joint: PoseJoint) -> SIMD3<Double>? {
        let index = joint.rawValue
        guard index < worldPoints.count else { return nil }
        return worldPoints[index]
    }

    func point(_ joint: PoseJoint) -> CGPoint? {
        let index = joint.rawValue
        guard index < points.count else { return nil }
        return points[index]
    }

    /// Point in a space where one unit means the same distance on both axes.
    private func corrected(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * aspect, y: point.y)
    }

    /// Whether the torso is closer to horizontal than vertical.
    ///
    /// This is what separates a push-up from someone standing up and waving
    /// their arms — the elbow angle sweep looks identical otherwise.
    var isTorsoHorizontal: Bool? {
        // In world space the torso can run across the frame (filmed side-on) or
        // straight into depth (filmed head-on). Both are "horizontal"; what
        // distinguishes standing is how much of the torso runs along the
        // image-vertical axis, so measure that rather than comparing x to y.
        if let shoulder = worldMidpoint(.leftShoulder, .rightShoulder),
           let hip = worldMidpoint(.leftHip, .rightHip) {
            let torso = hip - shoulder
            let length = simd_length(torso)
            guard length > 0.01 else { return nil }

            // cos of the angle off vertical. Upright ≈ 1, lying flat ≈ 0.
            let verticality = abs(torso.y) / length
            return verticality < 0.7          // more than ~45° off vertical
        }

        guard let shoulder = midpoint(.leftShoulder, .rightShoulder),
              let hip = midpoint(.leftHip, .rightHip)
        else { return nil }

        return abs(shoulder.x - hip.x) > abs(shoulder.y - hip.y)
    }

    /// How much of the shoulder→ankle line runs along the camera axis, 0…1.
    ///
    /// Depth is by far the weakest axis in a monocular pose estimate. Joint
    /// angles measured across the image survive that fine, but body-line
    /// straightness measured end-on is dominated by z error — it will read as
    /// bent no matter how straight the person is. This is what tells the form
    /// checks when to stay quiet.
    var bodyLineDepthFraction: Double? {
        guard let shoulder = worldMidpoint(.leftShoulder, .rightShoulder),
              let ankle = worldMidpoint(.leftAnkle, .rightAnkle)
        else { return nil }

        let line = ankle - shoulder
        let length = simd_length(line)
        guard length > 0.01 else { return nil }
        return abs(line.z) / length
    }

    private func worldMidpoint(_ a: PoseJoint, _ b: PoseJoint) -> SIMD3<Double>? {
        guard let pa = worldPoint(a), let pb = worldPoint(b) else { return nil }
        return (pa + pb) / 2
    }

    private func midpoint(_ a: PoseJoint, _ b: PoseJoint) -> CGPoint? {
        guard let pa = point(a), let pb = point(b) else { return nil }
        return corrected(CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2))
    }

    /// Interior angle at `vertex`, in degrees, formed by the two other joints.
    ///
    /// This is the primitive behind every movement rule — e.g. a push-up's
    /// elbow angle is `angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)`.
    func angle(at vertex: PoseJoint, from first: PoseJoint, to second: PoseJoint) -> Double? {
        // Prefer metric 3D — it measures the same angle regardless of where the
        // camera is standing.
        if let v = worldPoint(vertex), let a = worldPoint(first), let b = worldPoint(second) {
            let u = a - v
            let w = b - v
            let magnitude = simd_length(u) * simd_length(w)
            guard magnitude > 0 else { return nil }

            let cosine = max(-1, min(1, simd_dot(u, w) / magnitude))
            return acos(cosine) * 180 / Double.pi
        }

        guard let rawV = point(vertex),
              let rawA = point(first),
              let rawB = point(second)
        else { return nil }

        let v = corrected(rawV)
        let a = corrected(rawA)
        let b = corrected(rawB)

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
    private var previousWorld: [SIMD3<Double>]?

    mutating func smooth(_ pose: Pose) -> Pose {
        // World points drive every angle, so they need smoothing at least as
        // much as the drawn ones.
        var world = pose.worldPoints
        if let previousWorld, previousWorld.count == pose.worldPoints.count {
            world = zip(previousWorld, pose.worldPoints).map { old, new in
                old + (new - old) * factor
            }
        }
        previousWorld = world

        guard let previous, previous.count == pose.points.count else {
            self.previous = pose.points
            return Pose(
                points: pose.points,
                confidence: pose.confidence,
                aspect: pose.aspect,
                worldPoints: world
            )
        }

        let blended = zip(previous, pose.points).map { old, new in
            CGPoint(
                x: old.x + (new.x - old.x) * factor,
                y: old.y + (new.y - old.y) * factor
            )
        }
        self.previous = blended
        return Pose(
            points: blended,
            confidence: pose.confidence,
            aspect: pose.aspect,
            worldPoints: world
        )
    }

    mutating func reset() {
        previous = nil
        previousWorld = nil
    }
}
