//
//  MediaLibrary.swift
//  Calisthenics Vision
//
//  Where session media lives on disk, and how it gets cleaned up.
//
//  1080p H.264 runs roughly 100–150 MB per ten minutes, so retention is a
//  real feature here rather than an afterthought — an unbounded library will
//  fill a phone within weeks of daily use.
//

import Foundation

enum MediaLibrary {

    static var recordingsDirectory: URL {
        directory(named: "Recordings")
    }

    static var telemetryDirectory: URL {
        directory(named: "Telemetry")
    }

    private static func directory(named name: String) -> URL {
        var url = URL.applicationSupportDirectory
            .appending(path: name, directoryHint: .isDirectory)

        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true
            )
            // Recordings are large and re-creatable by training again; keeping
            // them out of iCloud backup avoids silently eating the user's
            // storage quota. Cloud sync is a separate Pro feature (SPEC.md §4).
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return url
    }

    // MARK: - Housekeeping

    /// Total bytes used by recordings and telemetry.
    static func totalBytes() -> Int64 {
        [recordingsDirectory, telemetryDirectory].reduce(into: Int64(0)) { total, dir in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey]
            ) else { return }

            for file in files {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += Int64(size)
            }
        }
    }

    static func formattedTotalSize() -> String {
        ByteCountFormatStyle(style: .file).format(totalBytes())
    }

    /// Removes the media belonging to one session. Safe if files are absent.
    static func deleteMedia(for session: WorkoutSession) {
        for url in [session.videoURL, session.telemetryURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes any file on disk not referenced by a stored session — cleans up
    /// after crashes that leave a recording behind without a saved record.
    static func removeOrphans(keeping sessions: [WorkoutSession]) {
        let referenced = Set(
            sessions.flatMap { [$0.videoFileName, $0.telemetryFileName].compactMap { $0 } }
        )

        for dir in [recordingsDirectory, telemetryDirectory] {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }

            for file in files where !referenced.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
