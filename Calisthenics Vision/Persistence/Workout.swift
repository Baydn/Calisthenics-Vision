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

@Model
final class Workout {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    /// Ids of the `WorkoutSession`s in this workout, in the order performed.
    var sessionIDs: [UUID] = []

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sessionIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sessionIDs = sessionIDs
    }
}

extension Workout {
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
