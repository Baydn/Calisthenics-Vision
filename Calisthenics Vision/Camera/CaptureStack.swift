//
//  CaptureStack.swift
//  Calisthenics Vision
//
//  The live capture stack — camera plus pose detection — owned *above* the
//  tab bar rather than by the Train screen.
//
//  Switching tabs rebuilds the screen's view tree, so when the screen owned
//  these the app tore down an AVCaptureSession and a MediaPipe GPU graph and
//  built new ones on every tab change. `AVCaptureVideoDataOutput` does not
//  retain its sample-buffer delegate, so a frame arriving mid-teardown called
//  into a deallocated object — a dangling pointer, and the crash people saw
//  when flicking between tabs.
//
//  Built once and kept for the life of the app. Leaving the Train tab
//  suspends capture; coming back resumes it. Nothing is deallocated in
//  between, so there is no window for a frame to land on freed memory.
//

@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CaptureStack {

    let camera = CameraController()
    let pose = PoseSession()

    /// Whether capture is currently meant to be running.
    private(set) var isActive = false

    /// Serializes activation against suspension. Without it, tapping away
    /// mid-`start()` lets the start finish *after* the stop and leaves the
    /// camera running behind another tab.
    @ObservationIgnored private var transition: Task<Void, Never>?

    /// Starts capture and pose detection, or does nothing if already running.
    func activate(position: AVCaptureDevice.Position, preferUltraWide: Bool) {
        isActive = true
        let previous = transition
        transition = Task { [camera, pose] in
            await previous?.value
            guard isActive else { return }

            await camera.start(position: position, preferUltraWide: preferUltraWide)
            // The suspend may have landed while the camera was starting.
            guard isActive else {
                camera.stop()
                return
            }
            if case .running = camera.status {
                pose.attach(to: camera)
            }
        }
    }

    /// Suspends capture without dismantling anything, so resuming is cheap
    /// and no object the capture queue touches is ever freed underneath it.
    func suspend() {
        isActive = false
        let previous = transition
        transition = Task { [camera, pose] in
            await previous?.value
            guard !isActive else { return }
            pose.pause()
            camera.stop()
        }
    }
}
