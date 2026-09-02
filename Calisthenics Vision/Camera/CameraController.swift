//
//  CameraController.swift
//  Calisthenics Vision
//
//  Owns the AVCaptureSession and fans each frame out to two consumers:
//  the pose landmarker and (while recording) the video writer.
//
//  See SPEC.md §"Camera & Video". The "dual sink" is a single
//  AVCaptureVideoDataOutput rather than a data output plus a movie file
//  output — one clock, one frame stream, so telemetry and video stay aligned.
//

// AVFoundation's capture types aren't Sendable-annotated. We confine every
// one of them to `sessionQueue`/`captureQueue`, so the warnings are noise.
@preconcurrency import AVFoundation
import CoreMedia
import Observation

@Observable
final class CameraController {

    enum Status: Equatable {
        case idle
        case unauthorized
        /// No capture device — notably the iOS Simulator, which has no camera.
        case unavailable(String)
        case running
    }

    private(set) var status: Status = .idle
    private(set) var isRecording = false

    /// Called on the capture queue for every frame, with the frame's
    /// presentation timestamp in milliseconds.
    @ObservationIgnored
    var onFrame: (@Sendable (CMSampleBuffer, Int) -> Void)?

    @ObservationIgnored
    private let session = AVCaptureSession()
    @ObservationIgnored
    private let sessionQueue = DispatchQueue(label: "camera.session")
    @ObservationIgnored
    private let captureQueue = DispatchQueue(label: "camera.frames")
    @ObservationIgnored
    private let output = AVCaptureVideoDataOutput()
    @ObservationIgnored
    private let recorder = VideoRecorder()
    @ObservationIgnored
    private lazy var frameHandler = FrameHandler()
    @ObservationIgnored
    private var dimensions = CMVideoDimensions(width: 1920, height: 1080)

    /// Exposed so the preview layer can attach to the same session.
    var captureSession: AVCaptureSession { session }

    // MARK: - Lifecycle

    /// Requests permission if needed, configures the session, and starts it.
    func start() async {
        guard await requestAccess() else {
            status = .unauthorized
            return
        }

        do {
            try await configureIfNeeded()
        } catch {
            status = .unavailable(error.localizedDescription)
            return
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        status = .running
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        status = .idle
    }

    // MARK: - Recording

    func startRecording() {
        let dimensions = dimensions
        captureQueue.async { [recorder] in
            try? recorder.start(dimensions: dimensions)
        }
        isRecording = true
    }

    /// Stops recording and returns the finished MP4, if one was written.
    @discardableResult
    func stopRecording() async -> URL? {
        isRecording = false
        return await recorder.finish()
    }

    // MARK: - Setup

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            false
        }
    }

    private var isConfigured = false

    private func configureIfNeeded() async throws {
        guard !isConfigured else { return }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            throw CameraError.noCaptureDevice
        }

        let input = try AVCaptureDeviceInput(device: device)

        // Forward frames to the landmarker and, when recording, the writer.
        frameHandler.onFrame = { [weak self] sampleBuffer in
            guard let self else { return }
            self.recorder.append(sampleBuffer)

            let timestampMs = Int(
                sampleBuffer.presentationTimeStamp.seconds * 1000
            )
            self.onFrame?(sampleBuffer, timestampMs)
        }

        output.setSampleBufferDelegate(frameHandler, queue: captureQueue)
        // MediaPipe wants BGRA; this also keeps the asset writer happy.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // Pose estimation is more useful on the newest frame than on a stale
        // backlog, so drop rather than queue when we fall behind.
        output.alwaysDiscardsLateVideoFrames = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [session, output] in
                session.beginConfiguration()
                session.sessionPreset = .hd1920x1080

                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }
                session.addInput(input)
                session.addOutput(output)

                if let connection = output.connection(with: .video) {
                    connection.videoRotationAngle = 90   // portrait
                }

                session.commitConfiguration()
                continuation.resume()
            }
        }

        dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        isConfigured = true
    }
}

enum CameraError: LocalizedError {
    case noCaptureDevice
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .noCaptureDevice:
            "No camera is available on this device."
        case .configurationFailed:
            "The camera could not be configured."
        }
    }
}

// MARK: - Frame delegate

/// Capture callbacks arrive on a background queue, so this stays off the
/// main actor and simply forwards buffers to the controller.
private nonisolated final class FrameHandler: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    var onFrame: ((CMSampleBuffer) -> Void)?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
    }
}
