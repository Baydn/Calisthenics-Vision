//
//  TrainIdleView.swift
//  Calisthenics Vision
//
//  Frame 02 — Train. Live preview, skeleton overlay, and the workout session
//  lifecycle: countdown → record → save.
//

import AVFoundation
import Combine
import SwiftData
import SwiftUI
import UIKit

struct TrainIdleView: View {

    /// Where we are in a workout, start to finish.
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case recording
        case saving
    }

    @Environment(Entitlements.self) private var entitlements
    @Environment(\.modelContext) private var modelContext

    @State private var camera = CameraController()
    @State private var poseSession = PoseSession()
    @State private var tracker = PushUpTracker()
    @State private var progress = MovementProgress()
    @State private var lastEvent: FormIssue?

    @State private var phase: Phase = .idle
    @State private var startedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var telemetry: TelemetryWriter?

    @State private var selected: Movement = .pushUps
    @State private var showLibrary = false
    @State private var showPaywall = false

    /// Quick-pick movements; the rest live behind "+ Library".
    private let quickPicks: [Movement] = [.pushUps, .handstand, .lSit]

    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            cameraLayer

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                Spacer()

                centrepiece

                Spacer()

                recordButton
                    .padding(.bottom, Theme.Metric.tabBarHeight + 8)
            }

            if case .countdown(let value) = phase {
                countdownOverlay(value)
            }
        }
        .task {
            poseSession.onPose = handlePose
            await camera.start()
            if case .running = camera.status {
                poseSession.attach(to: camera)
            }
            // A workout is minutes of not touching the phone. Letting the
            // screen dim mid-set would be the single most annoying bug here.
            UIApplication.shared.isIdleTimerDisabled = true
            Haptics.prepare()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            countdownTask?.cancel()
            poseSession.detach()
            camera.stop()
        }
        .onReceive(ticker) { _ in
            if phase == .recording, let startedAt {
                elapsed = Date().timeIntervalSince(startedAt)
            }
        }
        .sheet(isPresented: $showLibrary) {
            MovementLibraryView(selected: $selected)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Pose handling

    private func handlePose(_ pose: Pose?, timestampMs: Int) {
        let event = tracker.update(pose: pose, timestampMs: timestampMs)
        progress = tracker.progress

        // Telemetry is only worth keeping for a session being recorded.
        if phase == .recording, let pose {
            telemetry?.append(timestampMs: timestampMs, values: Self.flatten(pose))
        }

        switch event {
        case .repCompleted:
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

    /// Flattened x/y/z per landmark, preferring metric world coordinates.
    private static func flatten(_ pose: Pose) -> [Float] {
        if pose.worldPoints.count == Telemetry.landmarkCount {
            return pose.worldPoints.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        }
        return pose.points.prefix(Telemetry.landmarkCount)
            .flatMap { [Float($0.x), Float($0.y), 0] }
    }

    // MARK: - Session lifecycle

    private func startCountdown() {
        guard phase == .idle else { return }
        countdownTask?.cancel()
        countdownTask = Task {
            for value in stride(from: 3, through: 1, by: -1) {
                phase = .countdown(value)
                Haptics.countdownTick()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { phase = .idle; return }
            }
            beginRecording()
        }
    }

    private func beginRecording() {
        tracker.reset()
        progress = tracker.progress
        lastEvent = nil
        elapsed = 0
        startedAt = Date()
        telemetry = try? TelemetryWriter(sessionID: UUID())
        camera.startRecording()
        phase = .recording
        Haptics.sessionStart()
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        phase = .saving

        let movement = selected
        let started = startedAt ?? Date()
        let duration = Date().timeIntervalSince(started)
        let reps = tracker.progress.reps
        let breaks = tracker.progress.formBreaks
        let telemetryName = telemetry?.fileName

        telemetry?.finish()
        telemetry = nil

        Task {
            let videoURL = await camera.stopRecording()

            let session = WorkoutSession(
                movement: movement,
                startedAt: started,
                duration: duration,
                repCount: reps,
                formBreaks: breaks,
                videoFileName: videoURL?.lastPathComponent,
                telemetryFileName: telemetryName
            )
            modelContext.insert(session)
            try? modelContext.save()

            Haptics.sessionComplete()
            startedAt = nil
            phase = .idle
        }
    }

    private func toggleRecording() {
        switch phase {
        case .idle:
            startCountdown()
        case .countdown:
            countdownTask?.cancel()
            countdownTask = nil
            phase = .idle
        case .recording:
            finishRecording()
        case .saving:
            break
        }
    }

    // MARK: - Camera layer

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

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 10) {
            // Movement choice is locked once a set is under way — switching
            // mid-session would silently invalidate the reps already counted.
            if phase == .idle {
                movementPicker
            }

            HStack(alignment: .top) {
                performanceReadout
                Spacer()
                VStack(spacing: 8) {
                    flipCameraButton
                    lensButton
                }
            }
            .padding(.horizontal, 16)
        }
    }

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

    // MARK: - Centre

    @ViewBuilder
    private var centrepiece: some View {
        if phase == .recording || poseSession.pose != nil {
            repCounter
        } else {
            framingHint
        }
    }

    private var repCounter: some View {
        VStack(spacing: 12) {
            if phase == .recording {
                Text(SessionResult.durationLabel(elapsed))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Color.primaryText.opacity(0.85))
            }

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
            } else if phase == .idle {
                Text("Tap record when you're ready")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .animation(.snappy(duration: 0.2), value: lastEvent)
    }

    private var framingHint: some View {
        VStack(spacing: 28) {
            GhostFigure()
                .frame(width: 120, height: 160)

            Text(framingMessage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var framingMessage: String {
        switch camera.status {
        case .running, .idle:  "Step into frame to begin"
        case .unauthorized:    "Camera access is off — enable it in Settings"
        case .unavailable:     "No camera available on this device"
        }
    }

    private func countdownOverlay(_ value: Int) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            Text("\(value)")
                .font(.system(size: 140, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.primaryText)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.2), value: value)
                .shadow(color: .black.opacity(0.5), radius: 12)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Controls

    private var recordButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.Color.primaryText, lineWidth: 4)
                    .frame(width: 82, height: 82)

                switch phase {
                case .idle, .countdown:
                    Circle()
                        .fill(Theme.Color.primaryText)
                        .frame(width: 68, height: 68)
                case .recording:
                    // Camera-app convention: a square means "this will stop".
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.Color.warning)
                        .frame(width: 34, height: 34)
                case .saving:
                    ProgressView().tint(Theme.Color.primaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(phase == .saving)
        .animation(.snappy(duration: 0.2), value: phase)
    }

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

    /// 1× / 0.5× toggle, shown only when the hardware has an ultra-wide.
    @ViewBuilder
    private var lensButton: some View {
        if case .running = camera.status, camera.hasUltraWide {
            Button {
                Task { await camera.setLens(camera.lens == .wide ? .ultraWide : .wide) }
            } label: {
                Text(camera.lens.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(camera.lens == .ultraWide
                                     ? Theme.Color.background : Theme.Color.primaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        camera.lens == .ultraWide
                            ? AnyShapeStyle(Theme.Color.primaryText)
                            : AnyShapeStyle(Theme.Color.card.opacity(0.8)),
                        in: .circle
                    )
            }
            .buttonStyle(.plain)
        }
    }

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
                Text("form  \(tracker.isFormMeasurable ? "measurable" : "not measurable")")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.Color.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.Color.card.opacity(0.8), in: .rect(cornerRadius: 8))
        }
        #endif
    }

    private func angleText(_ angle: Double?) -> String {
        angle.map { String(format: "%3.0f°", $0) } ?? "  —"
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
                    path.move(to: CGPoint(x: w / 2, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w / 2, y: h * 0.72))
                    path.move(to: CGPoint(x: w * 0.14, y: h * 0.46))
                    path.addLine(to: CGPoint(x: w / 2, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.46))
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
        .modelContainer(SampleSessions.previewContainer)
        .preferredColorScheme(.dark)
}
