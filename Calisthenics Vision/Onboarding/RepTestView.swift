//
//  RepTestView.swift
//  Calisthenics Vision
//
//  The last step of onboarding: do one set, watch it get counted.
//
//  Onboarding used to end on a permissions screen, which is the least
//  convincing possible last impression for an app whose whole claim is that
//  it can see you. It now ends with the camera live and a real number on
//  screen, and the set is saved — so History has genuine data in it from the
//  first minute and the first personal record is something you actually did.
//
//  Deliberately not recorded to disk: no video, no telemetry. The point is
//  the count, and asking for storage before someone has decided to keep using
//  the app is the wrong trade.
//

import SwiftData
import SwiftUI

struct RepTestView: View {

    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case running
        case done
    }

    /// Called once the set is saved, with anything newly unlocked.
    let onFinish: ([Achievement]) -> Void

    @Environment(CaptureStack.self) private var capture
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]

    @State private var settings = AppSettings.shared
    @State private var movement: Movement = .pushUps
    @State private var tracker: (any MovementTracker)? = PushUpTracker()
    @State private var progress = MovementProgress()
    @State private var phase: Phase = .ready
    @State private var countdownTask: Task<Void, Never>?
    @State private var startedAt: Date?

    private var camera: CameraController { capture.camera }
    private var poseSession: PoseSession { capture.pose }

    var body: some View {
        ZStack {
            cameraLayer

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)

                Spacer()

                centre

                Spacer()

                controls
                    .padding(.bottom, 28)
            }

            if case .countdown(let value) = phase {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    Text("\(value)")
                        .font(.system(size: 140, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.primaryText)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.2), value: value)
                }
                .allowsHitTesting(false)
            }
        }
        .task {
            poseSession.onPose = handlePose
            capture.activate(
                position: settings.cameraPosition,
                preferUltraWide: settings.prefersUltraWide
            )
            Haptics.prepare()
        }
        .onDisappear {
            countdownTask?.cancel()
            poseSession.onPose = nil
            capture.suspend()
        }
    }

    // MARK: - Pose

    private func handlePose(_ pose: Pose?, timestampMs: Int) {
        guard phase == .running, var current = tracker else { return }
        let event = current.update(pose: pose, timestampMs: timestampMs)
        tracker = current
        progress = current.progress

        switch event {
        case .repCompleted:   Haptics.repCounted()
        case .holdTick:       Haptics.holdTick()
        case .holdCompleted:  Haptics.holdCompleted()
        default:              break
        }
    }

    // MARK: - Flow

    private func start() {
        countdownTask?.cancel()
        tracker?.reset()
        progress = tracker?.progress ?? MovementProgress()

        countdownTask = Task {
            for value in stride(from: 3, through: 1, by: -1) {
                phase = .countdown(value)
                Haptics.countdownTick()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { phase = .ready; return }
            }
            startedAt = Date()
            phase = .running
            Haptics.sessionStart()
        }
    }

    private func finish() {
        guard phase == .running else { return }
        countdownTask?.cancel()

        // Close anything still open, so ending mid-handstand keeps the hold.
        if var current = tracker {
            current.finish()
            tracker = current
            progress = current.progress
        }

        let before = AchievementContext(
            sessions: sessions,
            stats: SessionStore.stats(for: sessions)
        )

        let holds = progress.holds
        let started = startedAt ?? Date()
        let session = WorkoutSession(
            movement: movement,
            startedAt: started,
            duration: movement.isTimedHold
                ? progress.holdDuration
                : Date().timeIntervalSince(started),
            repCount: progress.reps,
            formBreaks: progress.formBreaks,
            formQuality: progress.formQuality,
            holdDurationsSec: holds.map(\.duration),
            holdStartsMs: holds.map(\.startTimestampMs),
            holdQualities: holds.map { $0.quality ?? -1 },
            kickUpAttempts: progress.kickUpAttempts
        )
        modelContext.insert(session)
        try? modelContext.save()

        let after = AchievementContext(
            sessions: sessions + [session],
            stats: SessionStore.stats(for: sessions + [session])
        )

        phase = .done
        Haptics.sessionComplete()
        onFinish(Achievements.newlyEarned(from: before, to: after))
    }

    private func select(_ next: Movement) {
        guard phase == .ready else { return }
        withAnimation(.snappy(duration: 0.2)) { movement = next }
        tracker = next.makeTracker()
        progress = tracker?.progress ?? MovementProgress()
    }

    // MARK: - Pieces

    @ViewBuilder
    private var cameraLayer: some View {
        if case .running = camera.status {
            ZStack {
                CameraPreviewView(
                    session: camera.captureSession,
                    onRotationChange: { camera.setRotation($0) }
                )
                PoseOverlayView(
                    pose: poseSession.pose,
                    isFormValid: progress.isFormValid,
                    sourceAspect: poseSession.pose?.aspect ?? 9.0 / 16.0
                )
            }
            .ignoresSafeArea()
        } else {
            Theme.Color.background.ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text(phase == .ready ? "Let's count your first set" : title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 8)

            if phase == .ready {
                HStack(spacing: 8) {
                    ForEach([Movement.pushUps, .handstand]) { option in
                        FilterChip(
                            title: option.displayName,
                            isActive: option == movement,
                            horizontalPadding: 16
                        ) { select(option) }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var title: String {
        movement.isTimedHold ? "Hold as long as you can" : "Go as long as you can"
    }

    @ViewBuilder
    private var centre: some View {
        switch phase {
        case .ready:
            VStack(spacing: 12) {
                Image(systemName: poseSession.pose == nil ? "figure.stand" : "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(poseSession.pose == nil
                                     ? Theme.Color.secondaryText : Theme.Color.valid)
                Text(poseSession.pose == nil
                     ? "Prop the phone up and step into frame"
                     : "Got you — this counts for real")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Color.primaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.black.opacity(0.4), in: .rect(cornerRadius: 16))

        case .countdown:
            EmptyView()

        case .running, .done:
            VStack(spacing: 4) {
                Text(movement.isTimedHold
                     ? SessionResult.preciseDurationLabel(progress.holdDuration)
                     : "\(progress.reps)")
                    .font(Theme.Font.hudCounter())
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.primaryText)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: progress.reps)
                    .shadow(color: .black.opacity(0.5), radius: 8)

                Text(movement.isTimedHold ? "HELD" : "REPS")
                    .cardLabelStyle()
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch phase {
        case .ready:
            VStack(spacing: 10) {
                PrimaryButton(title: "Start") { start() }
                    .padding(.horizontal, Theme.Metric.screenPadding)
                Button("Skip this") { onFinish([]) }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

        case .countdown:
            EmptyView()

        case .running:
            PrimaryButton(title: "I'm done") { finish() }
                .padding(.horizontal, Theme.Metric.screenPadding)

        case .done:
            EmptyView()
        }
    }
}
