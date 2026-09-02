//
//  Session.swift
//  Calisthenics Vision
//
//  UI-layer models. These are intentionally simple value types — once the
//  SQLite persistence layer lands (see SPEC.md §"Local Persistence"), these
//  become the read models hydrated from the telemetry store.
//

import Foundation

/// A trackable movement. `Free` tier ships push-ups and handstands;
/// the rest are Pro (SPEC.md §4).
enum Movement: String, CaseIterable, Identifiable, Hashable {
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

    /// Whether the movement requires a Pro subscription.
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

/// How a session's result is reported — a rep count or a hold duration.
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

struct Session: Identifiable, Hashable {
    let id: UUID
    let movement: Movement
    let date: Date
    let result: SessionResult
    /// Form breaks detected during the session (see SPEC.md §2).
    let formBreaks: Int

    init(
        id: UUID = UUID(),
        movement: Movement,
        date: Date,
        result: SessionResult,
        formBreaks: Int = 0
    ) {
        self.id = id
        self.movement = movement
        self.date = date
        self.result = result
        self.formBreaks = formBreaks
    }

    var timeLabel: String {
        date.formatted(Self.timeLabelFormatter)
    }

    private static let timeLabelFormatter: Date.FormatStyle =
        .dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute()
}

// MARK: - Sample data

/// Placeholder content matching the Figma frames so the screens can be built
/// and previewed before the persistence and pose layers exist.
enum SampleData {

    static let sessions: [Session] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        return [
            Session(movement: .pushUps,   date: date(daysAgo: 0, hour: 7, minute: 14), result: .reps(24)),
            Session(movement: .handstand, date: date(daysAgo: 0, hour: 7, minute: 22), result: .hold(38), formBreaks: 1),
            Session(movement: .pushUps,   date: date(daysAgo: 1, hour: 6, minute: 50), result: .reps(18)),
            Session(movement: .handstand, date: date(daysAgo: 2, hour: 7, minute: 10), result: .hold(62)),
            Session(movement: .pushUps,   date: date(daysAgo: 3, hour: 8, minute: 3),  result: .reps(21), formBreaks: 2),
            Session(movement: .pushUps,   date: date(daysAgo: 5, hour: 7, minute: 30), result: .reps(20)),
            Session(movement: .handstand, date: date(daysAgo: 6, hour: 7, minute: 45), result: .hold(51)),
            Session(movement: .pushUps,   date: date(daysAgo: 8, hour: 7, minute: 12), result: .reps(19)),
        ]
    }()

    static let dayStreak = 5
    static let repsThisWeek = 82
    static let totalSessions = 12

    static let bestPushUpSet = 24
    static let longestHandstand: TimeInterval = 62
}
