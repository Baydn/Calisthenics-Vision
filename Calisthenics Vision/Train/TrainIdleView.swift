//
//  TrainIdleView.swift
//  Calisthenics Vision
//
//  Frame 02 — Train · Idle. The dark backdrop stands in for the live camera
//  preview until the AVCaptureSession pipeline lands; the ghost figure and
//  framing hint sit on top of it.
//

import SwiftUI

struct TrainIdleView: View {
    @Environment(Entitlements.self) private var entitlements

    @State private var camera = CameraController()
    @State private var poseSession = PoseSession()
    @State private var selected: Movement = .pushUps
    @State private var showLibrary = false
    @State private var showPaywall = false

    /// Quick-pick movements; the rest live behind "+ Library".
    private let quickPicks: [Movement] = [.pushUps, .handstand, .lSit]

    var body: some View {
        ZStack {
            cameraLayer

            VStack(spacing: 0) {
                movementPicker
                    .padding(.top, 8)

                performanceReadout
                    .padding(.top, 10)

                Spacer()

                // Once a pose is being tracked the ghost guide has done its
                // job — the live skeleton takes over as the framing feedback.
                if poseSession.pose == nil {
                    framingHint
                }

                Spacer()

                recordButton
                    .padding(.bottom, Theme.Metric.tabBarHeight + 8)
            }
        }
        .task {
            await camera.start()
            if case .running = camera.status {
                poseSession.attach(to: camera)
            }
        }
        .onDisappear {
            poseSession.detach()
            camera.stop()
        }
        .sheet(isPresented: $showLibrary) {
            MovementLibraryView(selected: $selected)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Camera

    @ViewBuilder
    private var cameraLayer: some View {
        if case .running = camera.status {
            ZStack {
                CameraPreviewView(session: camera.captureSession)
                PoseOverlayView(pose: poseSession.pose)
            }
            .ignoresSafeArea()
        } else {
            Color(red: 0.09, green: 0.09, blue: 0.09)
                .ignoresSafeArea()
        }
    }

    /// Debug readout for checking on-device inference speed — the number that
    /// decides whether pose detection is actually viable in real time.
    @ViewBuilder
    private var performanceReadout: some View {
        #if DEBUG
        if case .running = camera.status {
            HStack(spacing: 6) {
                Circle()
                    .fill(poseSession.pose == nil ? Theme.Color.warning : Theme.Color.valid)
                    .frame(width: 6, height: 6)
                Text(poseSession.pose == nil
                     ? "no pose"
                     : "\(Int(poseSession.processedFPS)) fps")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Theme.Color.card.opacity(0.8), in: .capsule)
        }
        #endif
    }

    /// Copy under the ghost figure, reflecting why the camera isn't live.
    private var framingMessage: String {
        switch camera.status {
        case .running, .idle:  "Step into frame to begin"
        case .unauthorized:    "Camera access is off — enable it in Settings"
        case .unavailable:     "No camera available on this device"
        }
    }

    // MARK: - Pieces

    private var movementPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(quickPicks) { movement in
                    FilterChip(
                        title: movement.displayName,
                        isActive: movement == selected,
                        horizontalPadding: 14
                    ) {
                        select(movement)
                    }
                }

                Button { showLibrary = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Library")
                            .font(Theme.Font.control())
                    }
                    .foregroundStyle(Theme.Color.primaryText)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                Theme.Color.secondaryText,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var framingHint: some View {
        VStack(spacing: 28) {
            // Once pose detection is wired in, the ghost gives way to the
            // live skeleton overlay.
            if case .running = camera.status {} else {
                GhostFigure()
                    .frame(width: 120, height: 160)
            }

            Text(framingMessage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var recordButton: some View {
        Button {
            // Session start is wired once the camera + pose layers exist.
        } label: {
            Circle()
                .fill(Theme.Color.primaryText)
                .frame(width: 68, height: 68)
                .overlay {
                    Circle()
                        .strokeBorder(Theme.Color.primaryText, lineWidth: 4)
                        .frame(width: 82, height: 82)
                }
        }
        .buttonStyle(.plain)
    }

    private func select(_ movement: Movement) {
        guard entitlements.canTrack(movement) else {
            showPaywall = true
            return
        }
        withAnimation(.snappy(duration: 0.2)) { selected = movement }
    }
}

// MARK: - Ghost figure

/// The faint standing figure used as a framing guide.
private struct GhostFigure: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let stroke = Theme.Color.secondaryText.opacity(0.55)

            ZStack {
                Circle()
                    .fill(Theme.Color.secondaryText.opacity(0.45))
                    .frame(width: w * 0.36, height: w * 0.36)
                    .position(x: w / 2, y: h * 0.14)

                Path { path in
                    // Torso
                    path.move(to: CGPoint(x: w / 2, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w / 2, y: h * 0.72))
                    // Arms
                    path.move(to: CGPoint(x: w * 0.14, y: h * 0.46))
                    path.addLine(to: CGPoint(x: w / 2, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.46))
                    // Legs
                    path.move(to: CGPoint(x: w * 0.22, y: h * 0.94))
                    path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.94))
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

#Preview {
    TrainIdleView()
        .environment(Entitlements())
        .preferredColorScheme(.dark)
}
