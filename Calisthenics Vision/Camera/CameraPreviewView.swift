//
//  CameraPreviewView.swift
//  Calisthenics Vision
//
//  SwiftUI wrapper around AVCaptureVideoPreviewLayer.
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Degrees clockwise, from the camera's rotation coordinator, so the
    /// preview stays upright when the phone is turned on its side.
    var rotationAngle: CGFloat = 90

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        apply(rotationAngle, to: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        apply(rotationAngle, to: uiView)
    }

    private func apply(_ angle: CGFloat, to view: PreviewView) {
        guard let connection = view.previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle),
              connection.videoRotationAngle != angle
        else { return }
        connection.videoRotationAngle = angle
    }

    /// Backing view whose layer *is* the preview layer, so it resizes with
    /// the view instead of needing manual frame bookkeeping.
    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
