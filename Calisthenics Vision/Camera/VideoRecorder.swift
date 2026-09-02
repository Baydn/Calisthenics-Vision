//
//  VideoRecorder.swift
//  Calisthenics Vision
//
//  Writes capture frames to a local MP4 via AVAssetWriter.
//
//  We deliberately do NOT use AVCaptureMovieFileOutput. Recording from the
//  same CMSampleBuffer stream that feeds pose detection means video frames
//  and telemetry share one clock, which is what makes the Session Review
//  scrubber frame-accurate (SPEC.md §3).
//

import AVFoundation
import CoreMedia

/// Thread confinement: every method is called from the capture queue.
nonisolated final class VideoRecorder {

    enum State {
        case idle
        case recording
        case finishing
    }

    private(set) var state: State = .idle
    private(set) var outputURL: URL?

    /// Presentation timestamp of the first frame written, in milliseconds.
    ///
    /// Video time 0 corresponds to this instant, while telemetry is logged
    /// against the raw capture clock. Keeping it is what lets the review
    /// scrubber map a playback position back to the exact logged frame
    /// (SPEC.md §3) instead of guessing at an offset.
    private(set) var firstFrameTimestampMs: Int?

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var sessionStarted = false

    /// Directory holding session recordings.
    static var recordingsDirectory: URL {
        let base = URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Begin a new recording sized to the incoming video frames.
    /// - Parameter dimensions: pixel dimensions of the capture output.
    func start(dimensions: CMVideoDimensions) throws {
        guard state == .idle else { return }

        let url = Self.recordingsDirectory
            .appending(path: "\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        // Frames arrive in real time; let the writer drop to keep up rather
        // than stalling the capture queue.
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw NSError(
                domain: "VideoRecorder", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not add a video input to the asset writer."]
            )
        }
        writer.add(input)
        writer.startWriting()

        self.writer = writer
        self.videoInput = input
        self.outputURL = url
        self.sessionStarted = false
        self.firstFrameTimestampMs = nil
        self.state = .recording
    }

    /// Append one capture frame. Safe to call when not recording — it no-ops.
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording,
              let writer, let videoInput,
              writer.status == .writing
        else { return }

        // The writer's timeline starts at the first frame we actually see, so
        // the recording lines up with the telemetry we log for the same frame.
        if !sessionStarted {
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            firstFrameTimestampMs = Int(sampleBuffer.presentationTimeStamp.seconds * 1000)
            sessionStarted = true
        }

        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    /// A finished recording and the capture-clock instant it starts at.
    struct Result {
        let url: URL
        let firstFrameTimestampMs: Int?
    }

    /// Finish the file. Returns the finished recording, or nil if nothing was written.
    func finish() async -> Result? {
        guard state == .recording, let writer, let videoInput else { return nil }
        state = .finishing

        videoInput.markAsFinished()
        await writer.finishWriting()

        let url = writer.status == .completed ? outputURL : nil
        let startMs = firstFrameTimestampMs

        self.writer = nil
        self.videoInput = nil
        self.outputURL = nil
        self.sessionStarted = false
        self.firstFrameTimestampMs = nil
        self.state = .idle

        return url.map { Result(url: $0, firstFrameTimestampMs: startMs) }
    }
}
