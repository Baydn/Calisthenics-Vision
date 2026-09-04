//
//  Workout.swift
//  Calisthenics Vision
//
//  Several sets, grouped into one thing you can look at or post.
//
//  Grouping happens *after* the fact rather than before. You prop the phone
//  up and do things; deciding in advance that the next twenty minutes is "a
//  workout" is admin, and if you get it wrong mid-session you're stuck with
//  it. So: record freely, then tick the sets that belong together.
//
//  Sets are referenced by id rather than by a SwiftData relationship, so
//  deleting a workout never touches the sets in it — the recording is the
//  primary artefact and a grouping is just a view over it.
//

import Foundation
import SwiftData

/// Who can see a workout.
///
/// Recording is always private; this is about the grouping once it exists.
/// Public by default — the point of grouping sets is usually to have
/// something worth showing — but the choice is made at the moment you save,
/// not in a preference you set once and forgot.
enum WorkoutVisibility: String, Codable, CaseIterable, Identifiable {
    case everyone, followers, onlyYou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone:  "Everyone"
        case .followers: "Followers"
        case .onlyYou:   "Only you"
        }
    }

    var detail: String {
        switch self {
        case .everyone:  "Anyone can find and see this workout"
        case .followers: "Only people who follow you"
        case .onlyYou:   "Kept private — nobody else sees it"
        }
    }

    var symbol: String {
        switch self {
        case .everyone:  "globe"
        case .followers: "person.2.fill"
        case .onlyYou:   "lock.fill"
        }
    }
}

@Model
final class Workout {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    /// Stored as a raw value so the schema stays plain primitives.
    var visibilityRaw: String = WorkoutVisibility.everyone.rawValue
    /// Ids of the `WorkoutSession`s in this workout, in the order performed.
    var sessionIDs: [UUID] = []

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        createdAt: Date = Date(),
        visibility: WorkoutVisibility = .everyone,
        sessionIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.visibilityRaw = visibility.rawValue
        self.sessionIDs = sessionIDs
    }
}

extension Workout {

    var visibility: WorkoutVisibility {
        get { WorkoutVisibility(rawValue: visibilityRaw) ?? .everyone }
        set { visibilityRaw = newValue.rawValue }
    }

    /// Per-movement totals, which is how you actually read a workout back —
    /// "how many push-ups did I do" rather than "what was set four".
    func breakdown(from all: [WorkoutSession]) -> [(movement: Movement, sets: [WorkoutSession])] {
        let sets = sessions(from: all)
        let grouped = Dictionary(grouping: sets, by: \.movement)
        return grouped
            .map { (movement: $0.key, sets: $0.value.sorted { $0.startedAt < $1.startedAt }) }
            .sorted { $0.sets[0].startedAt < $1.sets[0].startedAt }
    }

    /// End to end, in seconds.
    func elapsed(from all: [WorkoutSession]) -> TimeInterval {
        let sets = sessions(from: all)
        guard let first = sets.first, let last = sets.last else { return 0 }
        return last.startedAt.addingTimeInterval(last.duration).timeIntervalSince(first.startedAt)
    }

    /// Longest gap allowed between one set and the next in the same workout.
    ///
    /// Without it you could group this morning's push-ups with yesterday's,
    /// which isn't a workout — it's two workouts with a night in between, and
    /// any total or duration computed across it would be nonsense. Three
    /// hours is generous enough for a long session with a break in it and
    /// short enough to rule out grouping across a day.
    static let maxGapBetweenSets: TimeInterval = 3 * 60 * 60

    /// The sets themselves, in performed order. Tolerates a missing set — a
    /// deleted recording shouldn't take the whole workout with it.
    func sessions(from all: [WorkoutSession]) -> [WorkoutSession] {
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return sessionIDs.compactMap { byID[$0] }.sorted { $0.startedAt < $1.startedAt }
    }

    /// "4 movements · 86 reps · 2:14 held" — whichever parts apply.
    func summary(from all: [WorkoutSession]) -> String {
        let sets = sessions(from: all)
        guard !sets.isEmpty else { return "No sets" }

        let movements = Set(sets.map(\.movement)).count
        let reps = sets.reduce(0) { $0 + $1.repCount }
        let held = sets.filter { $0.movement.isTimedHold }.reduce(0) { $0 + $1.duration }

        var parts = ["\(movements) movement\(movements == 1 ? "" : "s")"]
        if reps > 0 { parts.append("\(reps) reps") }
        if held > 0 { parts.append("\(SessionResult.durationLabel(held)) held") }
        return parts.joined(separator: " · ")
    }

    /// A name worth defaulting to: the day, plus what it was mostly.
    static func suggestedName(for sets: [WorkoutSession]) -> String {
        guard let first = sets.first else { return "Workout" }

        let categories = Set(sets.map(\.movement.category))
        let hour = Calendar.current.component(.hour, from: first.startedAt)
        let timeOfDay = hour < 12 ? "Morning" : (hour < 18 ? "Afternoon" : "Evening")

        if categories.count == 1, let only = categories.first {
            return "\(timeOfDay) \(only.displayName.lowercased()) session"
        }
        return "\(timeOfDay) session"
    }
}
