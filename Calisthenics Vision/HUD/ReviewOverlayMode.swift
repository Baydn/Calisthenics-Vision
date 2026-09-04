//
//  ReviewOverlayMode.swift
//  Calisthenics Vision
//
//  Which way of looking at a recorded frame the review screen is showing.
//
//  Kept free of SwiftUI so the rule that matters — which modes a movement can
//  offer at all — compiles into the standalone harness with the rest of the
//  movement geometry (POSE.md §12). PoseAnnotationView does the drawing.
//

import Foundation

/// What the review overlay is showing. The user picks this per session; the
/// segments offered depend on the movement, since not every movement has a
/// line to hold or a single joint it turns on.
enum ReviewOverlayMode: String, CaseIterable, Identifiable, Codable {
    case skeleton, line, angle, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skeleton: "Skeleton"
        case .line:     "Line"
        case .angle:    "Angle"
        case .off:      "Off"
        }
    }

    /// The modes worth offering for a movement — a mode with nothing to draw
    /// would be a control that does nothing.
    static func available(for movement: Movement) -> [ReviewOverlayMode] {
        var modes: [ReviewOverlayMode] = [.skeleton]
        if movement.alignmentChain != nil { modes.append(.line) }
        if movement.focusAngle != nil { modes.append(.angle) }
        modes.append(.off)
        return modes
    }
}

extension PoseJoint {
    /// How a joint is named in a one-line readout over the video.
    var shortName: String {
        switch self {
        case .leftShoulder, .rightShoulder: "Shoulder"
        case .leftElbow, .rightElbow:       "Elbow"
        case .leftWrist, .rightWrist:       "Wrist"
        case .leftHip, .rightHip:           "Hip"
        case .leftKnee, .rightKnee:         "Knee"
        case .leftAnkle, .rightAnkle:       "Ankle"
        case .nose:                         "Head"
        }
    }
}
