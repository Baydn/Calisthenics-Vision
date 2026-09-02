//
//  FrameSource.swift
//  Calisthenics Vision
//
//  Anything that can produce camera-shaped frames for the pose pipeline.
//
//  Two implementations: the live camera, and a video file replayed frame by
//  frame. Everything downstream — pose detection, joint angles, the movement
//  state machines — consumes the protocol and can't tell them apart, so the
//  whole pipeline is testable without hardware.
//

@preconcurrency import AVFoundation
import CoreMedia

protocol FrameSource: AnyObject {
    /// Called for every frame with its presentation timestamp in milliseconds.
    var onFrame: (@Sendable (CMSampleBuffer, Int) -> Void)? { get set }

    func start() async
    func stop()
}

extension CameraController: FrameSource {}

// MARK: - Video file replay

/// Replays a recorded video through the pipeline.
///
/// This is the workhorse for testing rep counting: a clip of a known number of
/// push-ups gives a deterministic, repeatable assertion ("does it count 10?"),
/// which a live camera can never provide since no two sets are identical.
@Observable
final class VideoFileSource: FrameSource {

    enum Status: Equatable {
        case idle
        case playing
        case finished
        case failed(String)
    }

    private(set) var status: Status = .idle

    @ObservationIgnored
    var onFrame: (@Sendable (CMSampleBuffer, Int) -> Void)?

    /// Replay at the video's own frame rate. Turn off to run as fast as the
    /// machine allows, which is what automated tests want.
    var playsInRealTime = true
    var loops = false

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var task: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    /// Looks for a clip bundled with the app, e.g. `test_pushups.mp4`.
    static func bundled(named name: String, extension ext: String = "mp4") -> VideoFileSource? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return VideoFileSource(url: url)
    }

    func start() async {
        stop()
        status = .playing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                repeat {
                    try await self.replayOnce()
                } while self.loops && !Task.isCancelled
                if !Task.isCancelled { self.status = .finished }
            } catch is CancellationError {
                // Stopped deliberately.
            } catch {
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if status == .playing { status = .idle }
    }

    // MARK: - Reading

    private func replayOnce() async throws {
        let asset = AVURLAsset(url: url)

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoSourceError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            // Match the camera's pixel format so downstream code is identical.
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else { throw VideoSourceError.cannotRead }
        reader.add(output)
        reader.startReading()

        var previousPTS: CMTime?

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()

            let pts = buffer.presentationTimeStamp

            // Pace playback so timing-dependent logic (hold timers, tempo)
            // behaves the way it would on a live camera.
            if playsInRealTime, let previous = previousPTS {
                let delta = (pts - previous).seconds
                if delta > 0 {
                    try await Task.sleep(for: .seconds(delta))
                }
            }
            previousPTS = pts

            onFrame?(buffer, Int(pts.seconds * 1000))
        }

        reader.cancelReading()
    }
}

enum VideoSourceError: LocalizedError {
    case noVideoTrack
    case cannotRead

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "That file doesn't contain a video track."
        case .cannotRead:   "The video could not be read."
        }
    }
}
