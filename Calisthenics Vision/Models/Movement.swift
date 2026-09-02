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

/// How a session's result reads — a rep count, a single hold, or a set of
/// them.
enum SessionResult: Hashable {
    case reps(Int)
    case hold(TimeInterval)
    /// Several holds in one set. `best` is what a hold session is judged on;
    /// the total is the sum of every counted hold.
    case holdSet(count: Int, best: TimeInterval, total: TimeInterval)

    var displayValue: String {
        switch self {
        case .reps(let count):
            "\(count) reps"
        case .hold(let duration):
            "\(Self.durationLabel(duration)) hold"
        case .holdSet(let count, let best, _):
            "\(count) holds · \(Self.durationLabel(best)) best"
        }
    }

    /// `m:ss` — minutes unpadded, seconds zero-padded (e.g. "0:38", "1:02").
    static func durationLabel(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// `m:ss.hh` — the same clock with hundredths, for a timer that's actually
    /// running. Whole seconds alone make a live hold look frozen between
    /// ticks, which reads as the app having stopped counting.
    ///
    /// Truncates rather than rounds: rounding would show "0:01.00" at 0.995 s,
    /// so the clock would briefly claim time that hasn't elapsed.
    static func preciseDurationLabel(_ duration: TimeInterval) -> String {
        let clamped = max(0, duration)
        let whole = Int(clamped)
        let hundredths = Int((clamped - Double(whole)) * 100)
        return "\(whole / 60):"
            + String(format: "%02d", whole % 60)
            + String(format: ".%02d", min(99, hundredths))
    }
}
