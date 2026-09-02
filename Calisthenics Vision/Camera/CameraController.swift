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
//  Threading: everything touching the capture session runs on `sessionQueue`;
//  everything touching frames runs on `captureQueue`. Nothing reaches across
//  without synchronization — an earlier version read the frame handler and the
//  recorder directly from the capture queue while the main actor mutated them,
//  which crashed with SIGSEGV once pose detection started attaching/detaching.
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

    /// Wide (1×) or ultra-wide (0.5×). Ultra-wide matters more here than in a
    /// normal camera app: fitting a whole body in frame usually means backing
    /// the phone a long way off, which most rooms don't allow.
    enum Lens: Equatable {
        case wide, ultraWide

        var deviceType: AVCaptureDevice.DeviceType {
            switch self {
            case .wide:      .builtInWideAngleCamera
            case .ultraWide: .builtInUltraWideCamera
            }
        }
        var label: String {
            switch self {
            case .wide:      "1×"
            case .ultraWide: "0.5×"
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var isRecording = false
    /// Starts on the front camera: while setting up you're looking at the
    /// phone to frame yourself, and seeing your own skeleton is how you know
    /// it's working before committing to a set.
    private(set) var position: AVCaptureDevice.Position = .front
    private(set) var lens: Lens = .wide
    /// Whether a 0.5× lens exists on the current camera — front cameras
    /// generally don't have one.
    private(set) var hasUltraWide = false

    /// Receives every frame on the capture queue, with the frame's
    /// presentation timestamp in milliseconds.
    func setFrameHandler(_ handler: (@Sendable (CMSampleBuffer, Int) -> Void)?) {
        frameSink.setHandler(handler)
    }

    @ObservationIgnored private let session = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "camera.session")
    @ObservationIgnored private let captureQueue = DispatchQueue(label: "camera.frames")
    @ObservationIgnored private let output = AVCaptureVideoDataOutput()
    @ObservationIgnored private let frameSink = FrameSink()
    @ObservationIgnored private lazy var frameHandler = FrameHandler()

    /// Touched only on `captureQueue`.
    @ObservationIgnored private let recorder = VideoRecorder()
    @ObservationIgnored private var dimensions = CMVideoDimensions(width: 1920, height: 1080)
    @ObservationIgnored private var videoInput: AVCaptureDeviceInput?
    @ObservationIgnored private var isConfigured = false

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

    // MARK: - Switching cameras

    /// Swaps between the front and back camera, keeping the session running.
    func flipCamera() async {
        let target: AVCaptureDevice.Position = position == .back ? .front : .back
        // Ultra-wide rarely exists on the front camera, so don't carry the
        // lens across a flip that can't honour it.
        let targetLens: Lens = Self.device(at: target, lens: lens) != nil ? lens : .wide
        await use(position: target, lens: targetLens)
    }

    /// Switches between 1× and 0.5× on the current camera.
    func setLens(_ target: Lens) async {
        guard target != lens else { return }
        await use(position: position, lens: target)
    }

    private func use(position target: AVCaptureDevice.Position, lens targetLens: Lens) async {
        guard let device = Self.device(at: target, lens: targetLens) else { return }

        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            sessionQueue.async { [session, output, videoInput] in
                guard let newInput = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: false)
                    return
                }

                session.beginConfiguration()
                if let videoInput { session.removeInput(videoInput) }

                guard session.canAddInput(newInput) else {
                    // Put the old input back rather than leaving a dead session.
                    if let videoInput, session.canAddInput(videoInput) {
                        session.addInput(videoInput)
                    }
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }

                session.addInput(newInput)
                Self.configureConnection(output.connection(with: .video), position: target)
                session.commitConfiguration()

                continuation.resume(returning: true)
            }
        }

        guard succeeded, let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        videoInput = newInput
        position = target
        lens = targetLens
        hasUltraWide = Self.device(at: target, lens: .ultraWide) != nil
        dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
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
    ///
    /// Hops onto the capture queue first: the recorder is only safe to touch
    /// there, since that's where frames are appended.
    @discardableResult
    func stopRecording() async -> VideoRecorder.Result? {
        isRecording = false
        return await withCheckedContinuation { (continuation: CheckedContinuation<VideoRecorder.Result?, Never>) in
            captureQueue.async { [recorder] in
                Task {
                    let result = await recorder.finish()
                    continuation.resume(returning: result)
                }
            }
        }
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

    /// Camera at a given position, falling back to any video device.
    ///
    /// The fallback matters for two cases: unusual hardware, and virtual
    /// cameras (CMIOExtension tools like SimulatorCamera/SimCam) that let the
    /// Simulator see a Mac webcam. Those never report as
    /// `.builtInWideAngleCamera`, so looking up that type alone would miss them.
    private static func device(
        at position: AVCaptureDevice.Position,
        lens: Lens = .wide
    ) -> AVCaptureDevice? {
        // Ultra-wide is optional hardware — never fall back to another lens for
        // it, or asking for 0.5× would silently hand back the 1× camera.
        if lens == .ultraWide {
            return AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera],
                mediaType: .video,
                position: position
            ).devices.first
        }

        if let match = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: position
        ) {
            return match
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
    }

    /// Portrait orientation, plus mirroring for the front camera so the
    /// preview matches what a mirror would show.
    private static func configureConnection(
        _ connection: AVCaptureConnection?,
        position: AVCaptureDevice.Position
    ) {
        guard let connection else { return }

        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
    }

    private func configureIfNeeded() async throws {
        guard !isConfigured else { return }

        guard let device = Self.device(at: position, lens: lens) else {
            throw CameraError.noCaptureDevice
        }
        hasUltraWide = Self.device(at: position, lens: .ultraWide) != nil
        let input = try AVCaptureDeviceInput(device: device)

        // Frames go to the recorder and then out to whoever is listening.
        // Both hops are safe from the capture queue: the recorder is confined
        // to it, and the sink synchronizes internally.
        frameHandler.onFrame = { [recorder, frameSink] sampleBuffer in
            recorder.append(sampleBuffer)
            frameSink.deliver(
                sampleBuffer,
                timestampMs: Int(sampleBuffer.presentationTimeStamp.seconds * 1000)
            )
        }

        output.setSampleBufferDelegate(frameHandler, queue: captureQueue)
        // MediaPipe wants BGRA; this also keeps the asset writer happy.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // Pose estimation is more useful on the newest frame than on a stale
        // backlog, so drop rather than queue when we fall behind.
        output.alwaysDiscardsLateVideoFrames = true

        let position = position
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [session, output] in
                session.beginConfiguration()
                // Prefer 1080p, but fall back — virtual cameras used for
                // Simulator testing typically only offer 720p.
                session.sessionPreset = session.canSetSessionPreset(.hd1920x1080)
                    ? .hd1920x1080
                    : .hd1280x720

                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                Self.configureConnection(output.connection(with: .video), position: position)

                session.commitConfiguration()
                continuation.resume()
            }
        }

        videoInput = input
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
/// main actor and simply forwards buffers.
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
