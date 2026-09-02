//
//  Movement.swift
//  Calisthenics Vision
//
//  The movement catalogue and how a session's result is presented.
//

import Foundation

/// A trackable movement. Free tier ships push-ups and handstands; the rest
/// are Pro (SPEC.md §4).
enum Movement: String, CaseIterable, Identifiable, Hashable, Codable {
    case pushUps
    case handstand
    case pullUps
    case muscleUps
    case lSit
    case planche

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushUps:   "Push-Ups"
        case .handstand: "Handstand"
        case .pullUps:   "Pull-Ups"
        case .muscleUps: "Muscle-Ups"
        case .lSit:      "L-Sit"
        case .planche:   "Planche"
        }
    }

    /// SF Symbol standing in for the custom glyphs in the Figma frames.
    var symbolName: String {
        switch self {
        case .pushUps:   "chevron.up"
        case .handstand: "figure.gymnastics"
        case .pullUps:   "figure.strengthtraining.functional"
        case .muscleUps: "figure.play"
        case .lSit:      "figure.core.training"
        case .planche:   "figure.flexibility"
        }
    }

    var isPro: Bool {
        switch self {
        case .pushUps, .handstand: false
        default: true
        }
    }

    /// Reps are counted; holds are timed.
    var isTimedHold: Bool {
        switch self {
        case .handstand, .lSit, .planche: true
        default: false
        }
    }
}

/// How a session's result reads — a rep count or a hold duration.
enum SessionResult: Hashable {
    case reps(Int)
    case hold(TimeInterval)

    var displayValue: String {
        switch self {
        case .reps(let count):
            "\(count) reps"
        case .hold(let duration):
            "\(Self.durationLabel(duration)) hold"
        }
    }

    /// `m:ss` — minutes unpadded, seconds zero-padded (e.g. "0:38", "1:02").
    static func durationLabel(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
