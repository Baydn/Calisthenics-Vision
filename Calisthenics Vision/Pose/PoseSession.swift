//
//  PoseSession.swift
//  Calisthenics Vision
//
//  Connects a FrameSource to the pose landmarker and publishes the latest
//  smoothed pose for the HUD to draw.
//
//  Frame source agnostic by design: the live camera and a replayed video file
//  drive this identically, so rep counting can be tested without hardware.
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import MediaPipeTasksVision
import Observation

@Observable
final class PoseSession {

    /// Most recent pose, or nil when nobody is detected in frame.
    private(set) var pose: Pose?
    /// Frames per second actually being processed, for a debug readout.
    private(set) var processedFPS: Double = 0

    @ObservationIgnored private var source: FrameSource?
    @ObservationIgnored private var landmarker: PoseLandmarkerService?
    @ObservationIgnored private let relay = PoseResultRelay()
    @ObservationIgnored private var smoother = PoseSmoother()

    @ObservationIgnored private var lastTimestampMs = 0
    @ObservationIgnored private var frameTimes: [Double] = []

    /// Last landmarker failure, surfaced so the UI can say why nothing is
    /// being detected instead of just showing an empty overlay.
    private(set) var setupError: String?

    /// Begins detecting on frames from `source`.
    ///
    /// The caller owns the source's lifecycle — this only subscribes. That
    /// keeps the camera's start/stop with the view that presents it, and lets
    /// a replayed video be scrubbed independently.
    /// - Returns: an error description if the landmarker couldn't be created.
    @discardableResult
    func attach(to source: FrameSource) -> String? {
        detach()

        do {
            landmarker = try PoseLandmarkerService(delegate: relay)
        } catch {
            setupError = error.localizedDescription
            return setupError
        }
        setupError = nil

        relay.onResult = { [weak self] result, timestampMs in
            Task { @MainActor [weak self] in
                self?.ingest(result, timestampMs: timestampMs)
            }
        }

        source.onFrame = { [weak self] sampleBuffer, timestampMs in
            self?.process(sampleBuffer, timestampMs: timestampMs)
        }

        self.source = source
        return nil
    }

    /// Stops detecting. Does not stop the underlying source.
    func detach() {
        source?.onFrame = nil
        source = nil
        landmarker = nil
        smoother.reset()
        pose = nil
        lastTimestampMs = 0
    }

    func stop() { detach() }

    // MARK: - Frame handling

    /// Called on the capture queue.
    private nonisolated func process(_ sampleBuffer: CMSampleBuffer, timestampMs: Int) {
        guard let landmarker else { return }

        // MediaPipe's live-stream mode requires strictly increasing
        // timestamps and throws otherwise — a replayed video that loops would
        // otherwise fail on the second pass.
        guard timestampMs > lastTimestampMs else { return }
        lastTimestampMs = timestampMs

        guard let image = try? MPImage(sampleBuffer: sampleBuffer) else { return }
        try? landmarker.detectAsync(image: image, timestampMs: timestampMs)
    }

    @MainActor
    private func ingest(_ result: PoseLandmarkerResult?, timestampMs: Int) {
        recordFrameTime()

        guard let landmarks = result?.landmarks.first, !landmarks.isEmpty else {
            pose = nil
            smoother.reset()
            return
        }

        let points = landmarks.map { CGPoint(x: Double($0.x), y: Double($0.y)) }
        let confidence = landmarks.map { $0.visibility?.floatValue ?? 1 }

        pose = smoother.smooth(Pose(points: points, confidence: confidence))
    }

    @MainActor
    private func recordFrameTime() {
        let now = CACurrentMediaTime()
        frameTimes.append(now)
        frameTimes.removeAll { now - $0 > 1 }
        processedFPS = Double(frameTimes.count)
    }
}

// MARK: - Delegate relay

/// MediaPipe delivers results on its own queue; this forwards them without
/// dragging the main actor into the callback.
private final class PoseResultRelay: NSObject, PoseLandmarkerLiveStreamDelegate, @unchecked Sendable {

    var onResult: ((PoseLandmarkerResult?, Int) -> Void)?

    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        onResult?(result, timestampInMilliseconds)
    }
}
