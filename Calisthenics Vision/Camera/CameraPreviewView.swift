//
//  CameraPreviewView.swift
//  Calisthenics Vision
//
//  SwiftUI wrapper around AVCaptureVideoPreviewLayer.
//
//  This view is also where rotation is decided. UIKit lays it out exactly
//  when the interface rotates, so reading the interface orientation here
//  needs no orientation notifications and can't miss one. The same angle is
//  handed to the capture connection, because the skeleton overlay is drawn
//  over this preview from landmarks measured in the capture buffers — if the
//  two rotations disagreed the skeleton would sit rotated off the body.
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Receives the interface's rotation angle so captured frames match what
    /// is on screen.
    var onRotationChange: ((CGFloat) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        // Fit, not fill.
        //
        // The capture is 9:16 and the screen is taller than that, so filling
        // cropped the sides — you were framing yourself against a picture
        // narrower than the one being recorded, and couldn't tell whether
        // your hands or feet had made it in. For an app whose whole job is
        // seeing your whole body, showing less than it captures is the wrong
        // trade; letterboxing is the honest one.
        view.previewLayer.videoGravity = .resizeAspect
        view.onRotationChange = onRotationChange
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.onRotationChange = onRotationChange
    }

    /// Backing view whose layer *is* the preview layer, so it resizes with
    /// the view instead of needing manual frame bookkeeping.
    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        var onRotationChange: ((CGFloat) -> Void)?

        private var appliedAngle: CGFloat?

        override func layoutSubviews() {
            super.layoutSubviews()
            applyRotation()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyRotation()
        }

        private func applyRotation() {
            guard let orientation = window?.windowScene?.interfaceOrientation else { return }
            let angle = CameraController.rotationAngle(for: orientation)
            guard angle != appliedAngle else { return }
            appliedAngle = angle

            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            onRotationChange?(angle)
        }
    }
}
