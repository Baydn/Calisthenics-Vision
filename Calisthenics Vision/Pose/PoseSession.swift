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
//  Threading: inference state lives in `PoseInferenceEngine`, off the main
//  actor and behind a lock, because frames arrive on the capture queue while
//  the main actor attaches and detaches. Reading the landmarker directly from
//  the capture queue raced with its deallocation and crashed with SIGSEGV.
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
    /// Last landmarker failure, so the UI can say why nothing is detected
    /// instead of just showing an empty overlay.
    private(set) var setupError: String?

    @ObservationIgnored private var source: FrameSource?
    @ObservationIgnored private let engine = PoseInferenceEngine()
    @ObservationIgnored private var smoother = PoseSmoother()
    @ObservationIgnored private var frameTimes: [Double] = []

    /// Begins detecting on frames from `source`.
    ///
    /// The caller owns the source's lifecycle — this only subscribes. That
    /// keeps the camera's start/stop with the view that presents it, and lets
    /// a replayed video be scrubbed independently.
    /// - Returns: an error description if the landmarker couldn't be created.
    @discardableResult
    func attach(to source: FrameSource) -> String? {
        detach()

        engine.onResult = { [weak self] result in
            Task { @MainActor [weak self] in
                self?.ingest(result)
            }
        }

        if let error = engine.prepare() {
            setupError = error
            return error
        }
        setupError = nil

        source.setFrameHandler { [engine] sampleBuffer, timestampMs in
            engine.process(sampleBuffer, timestampMs: timestampMs)
        }
        self.source = source
        return nil
    }

    /// Stops detecting. Does not stop the underlying source.
    func detach() {
        source?.setFrameHandler(nil)
        source = nil
        engine.teardown()
        smoother.reset()
        pose = nil
        frameTimes.removeAll()
        processedFPS = 0
    }

    func stop() { detach() }

    // MARK: - Results

    @MainActor
    private func ingest(_ result: PoseLandmarkerResult?) {
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

// MARK: - Inference engine

/// Owns the landmarker and the frame clock, guarded by a lock so the capture
/// queue and the main actor can't trip over each other.
private nonisolated final class PoseInferenceEngine: NSObject,
    PoseLandmarkerLiveStreamDelegate, @unchecked Sendable {

    var onResult: ((PoseLandmarkerResult?) -> Void)?

    private let lock = NSLock()
    private var landmarker: PoseLandmarkerService?
    private var lastTimestampMs = -1

    /// - Returns: an error description if the landmarker couldn't be created.
    func prepare() -> String? {
        do {
            let service = try PoseLandmarkerService(delegate: self)
            lock.lock()
            landmarker = service
            lastTimestampMs = -1
            lock.unlock()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func teardown() {
        lock.lock()
        landmarker = nil
        lastTimestampMs = -1
        lock.unlock()
    }

    /// Called on the capture queue.
    func process(_ sampleBuffer: CMSampleBuffer, timestampMs: Int) {
        // Take a strong reference under the lock so the landmarker can't be
        // released out from under `detectAsync`.
        lock.lock()
        guard let landmarker, timestampMs > lastTimestampMs else {
            lock.unlock()
            return
        }
        lastTimestampMs = timestampMs
        lock.unlock()

        // MediaPipe's live-stream mode requires strictly increasing
        // timestamps and throws otherwise, which the guard above enforces.
        guard let image = try? MPImage(sampleBuffer: sampleBuffer) else { return }
        try? landmarker.detectAsync(image: image, timestampMs: timestampMs)
    }

    // MARK: PoseLandmarkerLiveStreamDelegate

    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        onResult?(result)
    }
}
