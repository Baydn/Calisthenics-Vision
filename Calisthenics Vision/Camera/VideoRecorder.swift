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
        /// Armed, but waiting for the first frame to learn its true size.
        case starting
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

    /// Arm the recorder. The file is created here; the video input waits for
    /// the first frame.
    ///
    /// Sizing from the capture device's active format was wrong: that reports
    /// the sensor's native landscape dimensions, while the connection is
    /// rotated to portrait, so the writer scaled every frame into the wrong
    /// aspect and the whole recording came out stretched. The frames
    /// themselves are the only reliable source of their own size — and they
    /// stay right across camera flips and lens changes too.
    func start(dimensions: CMVideoDimensions) throws {
        guard state == .idle else { return }

        let url = Self.recordingsDirectory
            .appending(path: "\(UUID().uuidString).mp4")

        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        outputURL = url
        videoInput = nil
        sessionStarted = false
        firstFrameTimestampMs = nil
        state = .starting
    }

    /// Append one capture frame. Safe to call when not recording — it no-ops.
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard state == .starting || state == .recording,
              let writer
        else { return }

        if videoInput == nil {
            guard configureInput(for: sampleBuffer, writer: writer) else { return }
        }

        guard let videoInput, writer.status == .writing else { return }

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

    /// Builds the writer input to match the frames actually arriving.
    private func configureInput(for sampleBuffer: CMSampleBuffer, writer: AVAssetWriter) -> Bool {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return false }

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        // Frames arrive in real time; let the writer drop to keep up rather
        // than stalling the capture queue.
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else { return false }
        writer.add(input)
        writer.startWriting()

        videoInput = input
        state = .recording
        return true
    }

    /// A finished recording and the capture-clock instant it starts at.
    struct Result {
        let url: URL
        let firstFrameTimestampMs: Int?
    }

    /// Finish the file. Returns the finished recording, or nil if nothing was written.
    func finish() async -> Result? {
        guard state == .starting || state == .recording else { return nil }

        // Armed but never fed a frame: nothing was written, so there's no file
        // worth keeping.
        guard let writer, let videoInput, sessionStarted else {
            cleanUp(removingFile: true)
            return nil
        }
        state = .finishing

        videoInput.markAsFinished()
        await writer.finishWriting()

        let url = writer.status == .completed ? outputURL : nil
        let startMs = firstFrameTimestampMs

        cleanUp(removingFile: url == nil)
        return url.map { Result(url: $0, firstFrameTimestampMs: startMs) }
    }

    private func cleanUp(removingFile: Bool) {
        if removingFile, let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        writer = nil
        videoInput = nil
        outputURL = nil
        sessionStarted = false
        firstFrameTimestampMs = nil
        state = .idle
    }
}
