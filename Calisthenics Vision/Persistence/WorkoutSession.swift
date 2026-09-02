//
//  WorkoutSession.swift
//  Calisthenics Vision
//
//  SwiftData record for one completed session.
//
//  Only lightweight metadata lives here. The per-frame landmark stream is far
//  too high-frequency for a row-per-frame table, so it goes to a flat binary
//  file (see TelemetryStore) and the MP4 goes to the filesystem — this record
//  just points at both.
//

import Foundation
import SwiftData

@Model
final class WorkoutSession {
    /// Stable id, also used to name the session's media files on disk.
    var id: UUID = UUID()
    var movement: Movement = Movement.pushUps
    var startedAt: Date = Date()
    var duration: TimeInterval = 0

    /// Completed reps. Always 0 for timed holds.
    var repCount: Int = 0
    /// Form breaks detected during the session (SPEC.md §2).
    var formBreaks: Int = 0

    /// Filenames — not absolute URLs, which don't survive app reinstalls
    /// because the container path changes.
    var videoFileName: String?
    var telemetryFileName: String?
    /// Capture-clock timestamp of the video's first frame, in milliseconds.
    /// Review needs it to turn a playback position into a telemetry lookup.
    var videoStartMs: Int?

    /// Capture-clock instants where a rep completed, and where form broke.
    /// These become the markers on the review scrubber, so you can jump
    /// straight to the moment something happened instead of hunting for it.
    var repTimestampsMs: [Int] = []
    var formBreakTimestampsMs: [Int] = []

    /// Mean line quality for a timed hold, 0…1. Nil for movements that don't
    /// score form, and for sessions recorded before it was measured.
    var formQuality: Double?

    init(
        id: UUID = UUID(),
        movement: Movement,
        startedAt: Date = Date(),
        duration: TimeInterval = 0,
        repCount: Int = 0,
        formBreaks: Int = 0,
        videoFileName: String? = nil,
        telemetryFileName: String? = nil,
        videoStartMs: Int? = nil,
        repTimestampsMs: [Int] = [],
        formBreakTimestampsMs: [Int] = [],
        formQuality: Double? = nil
    ) {
        self.id = id
        self.movement = movement
        self.startedAt = startedAt
        self.duration = duration
        self.repCount = repCount
        self.formBreaks = formBreaks
        self.videoFileName = videoFileName
        self.telemetryFileName = telemetryFileName
        self.videoStartMs = videoStartMs
        self.repTimestampsMs = repTimestampsMs
        self.formBreakTimestampsMs = formBreakTimestampsMs
        self.formQuality = formQuality
    }
}

extension WorkoutSession {

    /// Line quality as a percentage string, where it was measured.
    var formQualityLabel: String? {
        formQuality.map { "\(Int(($0 * 100).rounded()))%" }
    }

    var result: SessionResult {
        movement.isTimedHold ? .hold(duration) : .reps(repCount)
    }

    var timeLabel: String {
        startedAt.formatted(
            .dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute()
        )
    }

    /// Resolved location of the recording, if one was kept.
    var videoURL: URL? {
        videoFileName.map { MediaLibrary.recordingsDirectory.appending(path: $0) }
    }

    var telemetryURL: URL? {
        telemetryFileName.map { MediaLibrary.telemetryDirectory.appending(path: $0) }
    }
}
