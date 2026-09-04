//
//  PoseOverlayStyle.swift
//  Calisthenics Vision
//
//  How the skeleton is drawn, and what its appearance is allowed to mean.
//
//  Two separate ideas got tangled in the first overlay: it was green because
//  form was fine, and it was the same green whether or not the movement was
//  even being judged. Green-for-valid is decoration — form being fine is the
//  normal state and needs no colour — while red-for-broken and
//  solid-vs-faded are information. So the default is white, and the two
//  things the overlay is allowed to say are:
//
//    · faded  → you're visible, but not in a position this movement counts in
//    · solid  → you're in position and the tracker is judging you
//    · red    → a form break is live right now
//
//  Colour still follows the app's rule: accents only where they carry
//  meaning (CLAUDE.md, design tokens).
//

import SwiftUI

enum PoseOverlayStyle: String, CaseIterable, Identifiable, Codable {
    /// White bones over a dark contrast halo. Legible on any background —
    /// gym floors, white walls, sunlight — which plain green never was.
    case outline
    /// The original: green while form holds, red when it breaks.
    case classic
    /// Bones only, no joint dots, thin. For when the skeleton is in the way
    /// of watching the movement itself.
    case minimal
    /// No skeleton. The recording and the counting are unaffected.
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outline: "Outline"
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .off:     "Off"
        }
    }

    var detail: String {
        switch self {
        case .outline: "White with a dark edge — reads on any background"
        case .classic: "Green while your form holds, red when it breaks"
        case .minimal: "Thin lines, no joint markers"
        case .off:     "Hide the skeleton entirely"
        }
    }

    var drawsSkeleton: Bool { self != .off }
    var drawsJoints: Bool { self == .outline || self == .classic }
    /// A dark stroke laid under the bones so they don't disappear against a
    /// light floor.
    var drawsHalo: Bool { self == .outline }

    var boneWidth: CGFloat {
        switch self {
        case .outline: 3
        case .classic: 2.5
        case .minimal: 1.6
        case .off:     0
        }
    }

    var jointRadius: CGFloat {
        switch self {
        case .outline: 4
        case .classic: 3.5
        default:       0
        }
    }

    /// Colour when nothing is wrong. Red on a form break is added on top of
    /// this by the view, in every style — it's the one thing the overlay
    /// must always be able to say.
    var restingColor: SwiftUI.Color {
        switch self {
        case .classic: Theme.Color.valid
        default:       Theme.Color.primaryText
        }
    }

    /// How visible the skeleton is while you're *not* in position for the
    /// selected movement — visible enough to confirm you're being tracked,
    /// faint enough that going solid is unmistakable.
    var idleOpacity: Double {
        switch self {
        case .minimal: 0.3
        default:       0.38
        }
    }
}

extension Pose {
    /// A standing figure in normalized image space, for drawing a style
    /// swatch in Settings. Not a measurement — world points are empty on
    /// purpose, so nothing can accidentally compute an angle from it.
    static let mannequin: Pose = {
        var points = [CGPoint](repeating: .zero, count: 33)
        let placed: [(PoseJoint, CGPoint)] = [
            (.nose,          CGPoint(x: 0.50, y: 0.09)),
            (.leftShoulder,  CGPoint(x: 0.38, y: 0.24)),
            (.rightShoulder, CGPoint(x: 0.62, y: 0.24)),
            (.leftElbow,     CGPoint(x: 0.31, y: 0.39)),
            (.rightElbow,    CGPoint(x: 0.69, y: 0.39)),
            (.leftWrist,     CGPoint(x: 0.27, y: 0.54)),
            (.rightWrist,    CGPoint(x: 0.73, y: 0.54)),
            (.leftHip,       CGPoint(x: 0.43, y: 0.52)),
            (.rightHip,      CGPoint(x: 0.57, y: 0.52)),
            (.leftKnee,      CGPoint(x: 0.42, y: 0.71)),
            (.rightKnee,     CGPoint(x: 0.58, y: 0.71)),
            (.leftAnkle,     CGPoint(x: 0.41, y: 0.90)),
            (.rightAnkle,    CGPoint(x: 0.59, y: 0.90)),
        ]
        for (joint, point) in placed { points[joint.rawValue] = point }
        return Pose(
            points: points,
            confidence: [Float](repeating: 1, count: 33),
            aspect: 0.7
        )
    }()
}
