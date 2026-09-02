//
//  PoseLandmarkerService.swift
//  Calisthenics Vision
//
//  Thin wrapper around MediaPipe's pose landmarker. Owns model loading and
//  configuration; joint-angle math and the movement state machines live
//  above this layer (see SPEC.md §"Math & State Engine").
//

import Foundation
import MediaPipeTasksVision

enum PoseLandmarkerError: LocalizedError {
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            "Could not find \(name) in the app bundle. Confirm it's included in the target's resources."
        }
    }
}

/// Loads `pose_landmarker_full.task` and runs pose detection on camera frames.
///
/// Configured for `.liveStream` so results arrive asynchronously via the
/// delegate as frames are delivered by the capture session at 30–60 FPS.
final class PoseLandmarkerService {

    private static let modelName = "pose_landmarker_full"
    private static let modelExtension = "task"

    private let landmarker: PoseLandmarker

    /// - Parameter delegate: receives async results in `.liveStream` mode.
    init(delegate liveStreamDelegate: PoseLandmarkerLiveStreamDelegate) throws {
        guard let modelPath = Bundle.main.path(
            forResource: Self.modelName,
            ofType: Self.modelExtension
        ) else {
            throw PoseLandmarkerError.modelNotFound(
                "\(Self.modelName).\(Self.modelExtension)"
            )
        }

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        // Metal GPU delegate — see SPEC.md §"ML Engine".
        options.baseOptions.delegate = .GPU
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.poseLandmarkerLiveStreamDelegate = liveStreamDelegate

        landmarker = try PoseLandmarker(options: options)
    }

    /// Feed a camera frame. Results are delivered to the live-stream delegate.
    /// - Parameter timestampMs: monotonically increasing, in milliseconds.
    func detectAsync(image: MPImage, timestampMs: Int) throws {
        try landmarker.detectAsync(image: image, timestampInMilliseconds: timestampMs)
    }
}
