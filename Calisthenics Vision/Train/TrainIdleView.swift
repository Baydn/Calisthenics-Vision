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
    @State private var tracker = PushUpTracker()
    @State private var progress = MovementProgress()
    @State private var lastEvent: FormIssue?
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

                HStack {
                    performanceReadout
                    Spacer()
                    flipCameraButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                // Once a pose is being tracked the ghost guide has done its
                // job — the live skeleton and counter take over.
                if poseSession.pose == nil {
                    framingHint
                } else {
                    repCounter
                }

                Spacer()

                recordButton
                    .padding(.bottom, Theme.Metric.tabBarHeight + 8)
            }
        }
        .task {
            poseSession.onPose = { pose, timestampMs in
                let event = tracker.update(pose: pose, timestampMs: timestampMs)
                progress = tracker.progress

                switch event {
                case .repCompleted:
                    // Haptic + sound land here once the feedback layer exists
                    // (SPEC.md §5) — the count shouldn't need to be watched.
                    Haptics.repCounted()
                case .formBreak(let issue):
                    lastEvent = issue
                    Haptics.formBreak()
                case .formRecovered:
                    lastEvent = nil
                case nil:
                    break
                }
            }

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
                PoseOverlayView(pose: poseSession.pose, isFormValid: progress.isFormValid)
            }
            .ignoresSafeArea()
        } else {
            Color(red: 0.09, green: 0.09, blue: 0.09)
                .ignoresSafeArea()
        }
    }

    private func angleText(_ angle: Double?) -> String {
        angle.map { String(format: "%3.0f°", $0) } ?? "  —"
    }

    /// Rep count at glanceable size, plus any active form warning.
    private var repCounter: some View {
        VStack(spacing: 12) {
            Text("\(progress.reps)")
                .font(Theme.Font.hudCounter())
                .foregroundStyle(Theme.Color.primaryText)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: progress.reps)
                .shadow(color: .black.opacity(0.5), radius: 8)

            if let lastEvent {
                Text(lastEvent.rawValue)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Color.warning)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(.black.opacity(0.45), in: .capsule)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: lastEvent)
    }

    /// Front/back toggle. Front is usually what you want with the phone
    /// propped up facing you, so you can see the skeleton while training.
    @ViewBuilder
    private var flipCameraButton: some View {
        if case .running = camera.status {
            Button {
                Task { await camera.flipCamera() }
            } label: {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.camera")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .frame(width: 36, height: 36)
                    .background(Theme.Color.card.opacity(0.8), in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    /// Debug readout for checking on-device inference speed — the number that
    /// decides whether pose detection is actually viable in real time.
    @ViewBuilder
    private var performanceReadout: some View {
        #if DEBUG
        if case .running = camera.status {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(poseSession.pose == nil ? Theme.Color.warning : Theme.Color.valid)
                        .frame(width: 6, height: 6)
                    Text(poseSession.pose == nil
                         ? "no pose"
                         : "\(Int(poseSession.processedFPS)) fps")
                }
                Text(tracker.isInPosition ? "in position" : "not in position")
                    .foregroundStyle(tracker.isInPosition
                                     ? Theme.Color.valid : Theme.Color.secondaryText)
                Text("elbow \(angleText(tracker.lastElbowAngle))")
                Text("range \(angleText(tracker.observedMin))–\(angleText(tracker.observedMax))")
                Text(tracker.isCalibrated
                     ? "gates \(angleText(tracker.bottomThreshold))/\(angleText(tracker.topThreshold))"
                     : "calibrating…")
                    .foregroundStyle(tracker.isCalibrated
                                     ? Theme.Color.valid : Theme.Color.warning)
                Text("hip   \(angleText(tracker.lastHipAngle))")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.Color.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.Color.card.opacity(0.8), in: .rect(cornerRadius: 8))
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
