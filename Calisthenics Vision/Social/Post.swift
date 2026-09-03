//
//  Post.swift
//  Calisthenics Vision
//
//  Something you chose to publish.
//
//  A post wraps one *or more* sets. A single set is the degenerate case, not
//  a second type — Strava's unit is one continuous activity, which is wrong
//  here, and Hevy's is the whole workout with the set-by-set breakdown one tap
//  deeper, which is right. Modelling them separately would mean writing the
//  feed card, the detail view and the share renderer twice.
//
//  Recording is private. Posting is the deliberate act, and a post is public
//  once made — you decide at the moment you press Post, not in a setting you
//  forgot you set.
//
//  There is no backend, so nothing leaves the phone: posts are stored locally
//  and only you can see them. The UI says so rather than implying an audience
//  that doesn't exist.
//

import Foundation
import SwiftData

@Model
final class Post {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var caption: String = ""
    /// Sets included, in performed order.
    var sessionIDs: [UUID] = []
    /// Set when the post came from a saved grouping rather than loose sets.
    var workoutID: UUID?
    /// Local-only engagement, so the card can be built and felt before there
    /// is anyone to engage.
    var likeCount: Int = 0
    var isLikedByMe: Bool = false
    var commentCount: Int = 0

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        caption: String = "",
        sessionIDs: [UUID] = [],
        workoutID: UUID? = nil,
        likeCount: Int = 0,
        isLikedByMe: Bool = false,
        commentCount: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.caption = caption
        self.sessionIDs = sessionIDs
        self.workoutID = workoutID
        self.likeCount = likeCount
        self.isLikedByMe = isLikedByMe
        self.commentCount = commentCount
    }
}

extension Post {
    func sessions(from all: [WorkoutSession]) -> [WorkoutSession] {
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return sessionIDs.compactMap { byID[$0] }.sorted { $0.startedAt < $1.startedAt }
    }

    var isSingleSet: Bool { sessionIDs.count == 1 }

    /// The one number the card leads with.
    func headline(from all: [WorkoutSession]) -> String {
        let sets = sessions(from: all)
        guard let first = sets.first else { return "—" }

        if isSingleSet {
            return first.movement.isTimedHold
                ? SessionResult.preciseDurationLabel(first.bestHold)
                : "\(first.repCount) reps"
        }
        let reps = sets.reduce(0) { $0 + $1.repCount }
        let held = sets.filter { $0.movement.isTimedHold }.reduce(0) { $0 + $1.duration }
        if reps > 0 { return "\(reps) reps" }
        return SessionResult.durationLabel(held)
    }

    func title(from all: [WorkoutSession]) -> String {
        let sets = sessions(from: all)
        guard let first = sets.first else { return "Post" }
        return isSingleSet
            ? first.movement.displayName
            : Workout.suggestedName(for: sets)
    }
}
