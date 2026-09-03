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

    /// Called on the main actor with each new pose, for whatever movement
    /// tracker is currently running.
    @ObservationIgnored var onPose: ((Pose?, Int) -> Void)?

    @ObservationIgnored private var source: FrameSource?
    @ObservationIgnored private let engine = PoseInferenceEngine()
    @ObservationIgnored private var smoother = PoseSmoother()
    @ObservationIgnored private var frameTimes: [Double] = []

    // MARK: - Detection gate
    //
    // MediaPipe has no "that isn't a person" output, so a coat on a chair or
    // a pattern on a wall can produce a full skeleton for a frame or two.
    // A real body persists; a spurious detection doesn't — so a pose has to
    // survive a few consecutive frames before anything is told about it.

    /// Frames a plausible body must appear in before it's published.
    /// 3 at 30 FPS is ~100 ms — below noticing, above a flicker.
    @ObservationIgnored private let framesToConfirm = 3
    /// Frames it must be absent before it's dropped. Higher than the confirm
    /// count on purpose: briefly losing a limb behind your own body is
    /// normal, and dropping the pose would stop a hold clock mid-hold.
    @ObservationIgnored private let framesToDrop = 6

    @ObservationIgnored private var plausibleFrames = 0
    @ObservationIgnored private var missingFrames = 0
    @ObservationIgnored private var isConfirmed = false

    #if DEBUG
    /// Detections rejected as implausible, for the on-device readout.
    private(set) var rejectedDetections = 0
    #endif

    /// Begins detecting on frames from `source`.
    ///
    /// The caller owns the source's lifecycle — this only subscribes. That
    /// keeps the camera's start/stop with the view that presents it, and lets
    /// a replayed video be scrubbed independently.
    /// - Returns: an error description if the landmarker couldn't be created.
    @discardableResult
    func attach(to source: FrameSource) -> String? {
        pause()

        engine.onResult = { [weak self] result, timestampMs in
            Task { @MainActor [weak self] in
                self?.ingest(result, timestampMs: timestampMs)
            }
        }

        // Only build the landmarker once. Rebuilding a MediaPipe GPU graph
        // every time the Train tab reappears is expensive and needless — the
        // engine survives suspension precisely so it doesn't have to.
        if let error = engine.prepareIfNeeded() {
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

    /// Stops detecting but keeps the landmarker loaded, ready to resume.
    ///
    /// This is what leaving the Train tab does. Nothing the capture queue
    /// touches is released, so a frame already in flight has somewhere safe
    /// to land.
    func pause() {
        source?.setFrameHandler(nil)
        source = nil
        smoother.reset()
        pose = nil
        frameTimes.removeAll()
        processedFPS = 0
        plausibleFrames = 0
        missingFrames = 0
        isConfirmed = false
    }

    /// Stops detecting and releases the landmarker.
    func detach() {
        pause()
        engine.teardown()
    }

    func stop() { detach() }

    // MARK: - Results

    @MainActor
    private func ingest(_ result: PoseLandmarkerResult?, timestampMs: Int) {
        recordFrameTime()

        guard let landmarks = result?.landmarks.first, !landmarks.isEmpty else {
            release(at: timestampMs)
            return
        }

        let points = landmarks.map { CGPoint(x: Double($0.x), y: Double($0.y)) }
        let confidence = landmarks.map { $0.visibility?.floatValue ?? 1 }

        // Metric 3D landmarks, so angles don't depend on where the camera is.
        let world = (result?.worldLandmarks.first ?? []).map {
            SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z))
        }

        let candidate = Pose(
            points: points,
            confidence: confidence,
            aspect: engine.sourceAspect,
            worldPoints: world
        )

        guard candidate.isPlausibleBody else {
            #if DEBUG
            rejectedDetections += 1
            #endif
            release(at: timestampMs)
            return
        }

        missingFrames = 0
        plausibleFrames += 1

        // Hold everything back until the detection has proved it's persistent.
        // Smoothing still runs, so the first published pose is already settled
        // rather than snapping in from the raw first frame.
        let smoothed = smoother.smooth(candidate)
        guard isConfirmed || plausibleFrames >= framesToConfirm else { return }
        isConfirmed = true

        pose = smoothed
        onPose?(smoothed, timestampMs)
    }

    /// Handles a frame with no usable body in it.
    @MainActor
    private func release(at timestampMs: Int) {
        plausibleFrames = 0
        missingFrames += 1

        // Ride out a brief dropout rather than tearing the pose down, which
        // would pause a hold clock every time a limb passed behind the torso.
        guard isConfirmed else {
            smoother.reset()
            return
        }
        guard missingFrames >= framesToDrop else { return }

        isConfirmed = false
        pose = nil
        smoother.reset()
        onPose?(nil, timestampMs)
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

    var onResult: ((PoseLandmarkerResult?, Int) -> Void)?

    private let lock = NSLock()
    private var landmarker: PoseLandmarkerService?
    private var lastTimestampMs = -1

    /// Creates the landmarker if there isn't one already.
    ///
    /// `lastTimestampMs` is deliberately *not* reset on a reattach: capture
    /// timestamps come from the host clock and keep climbing while suspended,
    /// and MediaPipe's live-stream mode rejects a timestamp that isn't
    /// strictly increasing.
    /// - Returns: an error description if the landmarker couldn't be created.
    func prepareIfNeeded() -> String? {
        lock.lock()
        let existing = landmarker != nil
        lock.unlock()
        guard !existing else { return nil }

        do {
            let service = try PoseLandmarkerService(delegate: self)
            lock.lock()
            landmarker = service
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

    /// Source frame aspect (width ÷ height), needed to undo MediaPipe's
    /// per-axis normalization before any angle is measured.
    ///
    /// Written from the capture queue and read from the main actor, so it
    /// goes through the same lock as everything else here.
    private var _sourceAspect: CGFloat = 1
    var sourceAspect: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return _sourceAspect
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

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            if height > 0 {
                lock.lock()
                _sourceAspect = width / height
                lock.unlock()
            }
        }

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
        onResult?(result, timestampInMilliseconds)
    }
}
