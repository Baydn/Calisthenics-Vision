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
    @Environment(CaptureStack.self) private var capture
    @Environment(\.modelContext) private var modelContext
    /// Existing sessions, so a set can be measured against your record while
    /// you're still in it. Strong's whole loop is "beat your last number",
    /// and ours was invisible until the set was over.
    @Query private var allSessions: [WorkoutSession]

    @State private var settings = AppSettings.shared
    /// The tracker for the selected movement, or nil where none exists yet.
    @State private var tracker: (any MovementTracker)? = PushUpTracker()
    @State private var progress = MovementProgress()
    /// Whether the tracker considers the body to be in position right now.
    /// Drives the overlay: faded while it's false, solid once the movement
    /// is actually being judged.
    @State private var isInPosition = false
    @State private var lastEvent: FormIssue?

    @State private var phase: Phase = .idle
    @State private var startedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var telemetry: TelemetryWriter?
    @State private var repTimestamps: [Int] = []
    @State private var formBreakTimestamps: [Int] = []

    @State private var selected: Movement = .pushUps
    @State private var showLibrary = false
    @State private var showPaywall = false
    @State private var showMovementSettings = false
    @State private var timerExpanded = false
    /// The set that just finished, shown as a summary sheet.
    @State private var completed: WorkoutSession?
    @Namespace private var lensPill
    @Namespace private var timerPill
    /// Record for the selected movement when the set began. Captured at the
    /// start so beating it doesn't move the target mid-set.
    @State private var recordToBeat: Double = 0
    @State private var hasBeatenRecord = false

    /// Quick-pick movements; the rest live behind "+ Library".
    /// Only movements that are actually tracked. An untracked movement in the
    /// quick row is a promise the app can't keep; the rest live in Library.
    /// Chosen from the library, not hardcoded — see AppSettings.pinnedMovements.
    private var quickPicks: [Movement] { settings.pinnedMovements }

    /// Unpinning the selected movement in the library would leave Train set to
    /// something no chip shows as active, so follow the list back.
    private func reconcileSelection() {
        guard phase == .idle, !quickPicks.isEmpty, !quickPicks.contains(selected),
              let first = quickPicks.first
        else { return }
        select(first)
    }

    /// 20 Hz, so the hundredths on the elapsed clock actually move. The hold
    /// clock is driven by pose frames instead and updates with them.
    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var camera: CameraController { capture.camera }
    private var poseSession: PoseSession { capture.pose }

    var body: some View {
        ZStack {
            cameraLayer

            // Landscape isn't just a stretched portrait here: filming a
            // planche or a side-on push-up wants the long axis of the frame
            // along the body, and a record button at the bottom would sit
            // under the tab bar. Controls move to the trailing edge instead,
            // the way a camera app does it.
            GeometryReader { proxy in
                let isLandscape = proxy.size.width > proxy.size.height
                Group {
                    if isLandscape { landscapeControls } else { portraitControls }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }

            if case .countdown(let value) = phase {
                countdownOverlay(value)
            }
        }
        .task {
            poseSession.onPose = handlePose
            capture.activate()
            // A workout is minutes of not touching the phone. Letting the
            // screen dim mid-set would be the single most annoying bug here.
            UIApplication.shared.isIdleTimerDisabled = settings.keepsScreenAwake
            Haptics.prepare()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            countdownTask?.cancel()
            poseSession.onPose = nil
            AudioCoach.shared.end()
            capture.suspend()
        }
        .onReceive(ticker) { _ in
            if phase == .recording, let startedAt {
                elapsed = Date().timeIntervalSince(startedAt)
            }
        }
        .sheet(isPresented: $showLibrary) {
            MovementLibraryView()
        }
        .onChange(of: settings.pinnedMovements) { _, _ in reconcileSelection() }
        .sheet(isPresented: $showMovementSettings) {
            MovementSettingsView(movement: selected)
        }
        .sheet(item: $completed) { session in
            SetSummaryView(session: session)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var portraitControls: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                Spacer()

                centrepiece

                Spacer()

                // Zoom sits directly above the shutter, where a camera app
                // puts it — it's part of framing the shot you're about to
                // take, not a side feature.
                VStack(spacing: 14) {
                    lensButton
                    recordButton
                }
                .padding(.bottom, Theme.Metric.tabBarClearance + 8)
            }

            // Coaching and tuning live together on the trailing edge, above
            // centre — trailing-aligned so the timer can widen when it opens
            // without shoving tune sideways.
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    timerButton
                    tuneButton
                }
                .padding(.trailing, 18)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.bottom, 80)

            // Flip sits beside the shutter, at the same height, the way a
            // camera app puts it — not grouped with coaching/tuning (it's
            // part of taking the shot, closer in spirit to the lens toggle
            // above the shutter than to a setting), and not pinned near the
            // tab bar either, which is what put it in the way of the bar's
            // own height and the countdown control's expansion before.
            HStack {
                Spacer()
                flipCameraButton
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.trailing, 18)
            .padding(.bottom, Theme.Metric.tabBarClearance + 25)
        }
    }

    private var landscapeControls: some View {
        ZStack {
            centrepiece
                .padding(.trailing, 96)     // clear of the control column

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        if phase == .idle { movementPicker }
                        performanceReadout
                            .padding(.horizontal, 16)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }

            // Same fold-in as portrait: flip lives with the rest of the
            // trailing-edge controls instead of pinned near the tab bar.
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    flipCameraButton
                    timerButton
                    tuneButton
                    lensButton
                    recordButton
                        .scaleEffect(0.78)
                }
                .padding(.trailing, 18)
            }
        }
    }

    // MARK: - Pose handling

    private func handlePose(_ pose: Pose?, timestampMs: Int) {
        // Telemetry is only worth keeping for a session being recorded — but
        // it's worth keeping whether or not the movement has a tracker, so
        // this sits above the guard. Landmarks are the one thing that can't
        // be reconstructed afterwards, and Review draws its skeleton, its
        // alignment line and its angles from them. Filming a muscle-up we
        // can't count yet should still leave something to look at.
        if phase == .recording, let pose {
            telemetry?.append(timestampMs: timestampMs, values: Self.flatten(pose))
        }

        // Trackers are value types, so mutate a local copy and write it back.
        guard var current = tracker else { return }
        let event = current.update(pose: pose, timestampMs: timestampMs)
        tracker = current
        progress = current.progress
        isInPosition = current.diagnostics.isReady

        switch event {
        case .repCompleted(let total):
            if phase == .recording { repTimestamps.append(timestampMs) }
            Haptics.repCounted()
            AudioCoach.shared.repCounted(total)
        case .holdTick(let seconds):
            // A quiet pulse each second, so a hold can be timed without
            // looking at the screen — which is the whole point upside down.
            // Speech carries the actual number, which a pulse can't.
            Haptics.holdTick()
            AudioCoach.shared.holdTick(seconds: seconds)
        case .holdCompleted(let index, let duration):
            // A firmer tap: that attempt is banked and the next one starts
            // from zero.
            Haptics.holdCompleted()
            AudioCoach.shared.holdCompleted(index: index, duration: duration)
        case .formBreak(let issue):
            if phase == .recording { formBreakTimestamps.append(timestampMs) }
            lastEvent = issue
            Haptics.formBreak()
            AudioCoach.shared.formIssue(issue)
        case .formRecovered:
            lastEvent = nil
        case nil:
            break
        }
    }

    /// Flattened `[x, y, wx, wy, wz]` per landmark — image space for drawing,
    /// world space for measuring.
    private static func flatten(_ pose: Pose) -> [Float] {
        (0..<Telemetry.landmarkCount).flatMap { index -> [Float] in
            let point = index < pose.points.count ? pose.points[index] : .zero
            let world = index < pose.worldPoints.count ? pose.worldPoints[index] : .zero
            return [
                Float(point.x), Float(point.y),
                Float(world.x), Float(world.y), Float(world.z),
            ]
        }
    }

    // MARK: - Session lifecycle

    private func startCountdown() {
        guard phase == .idle else { return }
        withAnimation(Theme.Motion.expand) { timerExpanded = false }
        countdownTask?.cancel()
        let seconds = settings.countdownSeconds
        guard seconds > 0 else { beginRecording(); return }

        countdownTask = Task {
            for value in stride(from: seconds, through: 1, by: -1) {
                phase = .countdown(value)
                Haptics.countdownTick()
                AudioCoach.shared.countdown(value)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { phase = .idle; return }
            }
            beginRecording()
        }
    }

    private func beginRecording() {
        recordToBeat = currentRecord
        hasBeatenRecord = false
        tracker?.reset()
        progress = tracker?.progress ?? MovementProgress()
        isInPosition = false
        lastEvent = nil
        elapsed = 0
        repTimestamps = []
        formBreakTimestamps = []
        startedAt = Date()
        telemetry = try? TelemetryWriter(sessionID: UUID())
        if settings.recordsVideo { camera.startRecording() }
        phase = .recording
        Haptics.sessionStart()
        AudioCoach.shared.begin()
        AudioCoach.shared.setStarted()
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        phase = .saving

        // Close any hold still running. Stopping the recording while you're
        // still inverted shouldn't throw away the attempt in progress.
        if var current = tracker {
            current.finish()
            tracker = current
            progress = current.progress
        }

        let movement = selected
        let started = startedAt ?? Date()
        let duration = Date().timeIntervalSince(started)
        let reps = tracker?.progress.reps ?? 0
        let breaks = tracker?.progress.formBreaks ?? 0
        // For a timed movement the meaningful number is validated hold time,
        // not how long the recording ran.
        let holdSeconds = tracker?.progress.holdDuration ?? 0
        let holds = tracker?.progress.holds ?? []
        let attempts = tracker?.progress.kickUpAttempts ?? 0
        let quality = tracker?.progress.formQuality
        let telemetryName = telemetry?.fileName
        let repMarks = repTimestamps
        let breakMarks = formBreakTimestamps

        telemetry?.finish()
        telemetry = nil

        Task {
            let recording = settings.recordsVideo ? await camera.stopRecording() : nil

            let session = WorkoutSession(
                movement: movement,
                startedAt: started,
                duration: movement.isTimedHold ? holdSeconds : duration,
                repCount: reps,
                formBreaks: breaks,
                videoFileName: recording?.url.lastPathComponent,
                telemetryFileName: telemetryName,
                videoStartMs: recording?.firstFrameTimestampMs,
                repTimestampsMs: repMarks,
                formBreakTimestampsMs: breakMarks,
                formQuality: quality,
                holdDurationsSec: holds.map(\.duration),
                holdStartsMs: holds.map(\.startTimestampMs),
                // -1 stands in for "not measurable", since the stored array
                // has to be plain doubles.
                holdQualities: holds.map { $0.quality ?? -1 },
                kickUpAttempts: attempts
            )
            modelContext.insert(session)
            try? modelContext.save()

            // Every set gets a verdict, not just the record-breaking ones.
            completed = session

            Haptics.sessionComplete()
            AudioCoach.shared.setFinished(
                summary: movement.isTimedHold
                    ? "Set complete. Best hold \(Int(holds.map(\.duration).max() ?? 0)) seconds."
                    : "Set complete. \(reps) reps."
            )
            AudioCoach.shared.end()
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
                CameraPreviewView(
                    session: camera.captureSession,
                    onRotationChange: { camera.setRotation($0) }
                )
                // The frames physically rotate with the interface, so the
                // overlay has to use the pose's own aspect rather than
                // assuming portrait — otherwise the skeleton lands beside
                // the body in landscape.
                // Must match the preview's gravity or the skeleton drifts
                // off the body — the overlay maps normalized landmarks into
                // whatever box the video is actually drawn in.
                PoseOverlayView(
                    pose: poseSession.pose,
                    isFormValid: progress.isFormValid,
                    isEngaged: isInPosition,
                    style: settings.overlayStyle,
                    sourceAspect: poseSession.pose?.aspect ?? 9.0 / 16.0,
                    contentMode: .fill
                )
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
                Spacer(minLength: 0)
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
        switch phase {
        case .idle:
            // Nothing at all before a set starts.
            //
            // There used to be a "you're in frame / step into frame" prompt
            // here. It was wrong about how the app is actually used: you prop
            // the phone up, tap record, and *then* walk into shot — so being
            // out of frame at this moment is the normal case, not a problem
            // to report. The only thing worth saying is when the camera
            // itself can't run.
            cameraProblem

        case .countdown:
            // Deliberately empty: the countdown overlay owns the centre of the
            // screen, and anything here shows through behind the number.
            EmptyView()

        case .recording, .saving:
            repCounter
        }
    }

    /// Shown only when the camera genuinely can't run. Silence otherwise.
    @ViewBuilder
    private var cameraProblem: some View {
        switch camera.status {
        case .running, .idle:
            EmptyView()
        case .unauthorized:
            problemNotice("Camera access is off", "Enable it in Settings to track a set.")
        case .unavailable(let reason):
            problemNotice("No camera available", reason)
        }
    }

    private func problemNotice(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.system(size: 26))
                .foregroundStyle(Theme.Color.secondaryText)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)
            Text(detail)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 16))
    }

    private var repCounter: some View {
        VStack(spacing: 12) {
            if phase == .recording {
                Text(SessionResult.preciseDurationLabel(elapsed))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.primaryText.opacity(0.85))
            }

            if tracker == nil {
                unsupportedNotice
            } else if selected.isTimedHold {
                holdReadout
            } else {
                Text("\(progress.reps)")
                    .font(Theme.Font.hudCounter())
                    .foregroundStyle(Theme.Color.primaryText)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: progress.reps)
                    .shadow(color: .black.opacity(0.5), radius: 8)
            }

            if let record = recordLine {
                Text(record.text)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(Theme.Metric.labelTracking)
                    .foregroundStyle(record.beaten
                                     ? Theme.Color.valid : Theme.Color.secondaryText)
                    .shadow(color: .black.opacity(0.5), radius: 6)
                    .contentTransition(.opacity)
            }

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
        .animation(.snappy(duration: 0.3), value: recordLine?.beaten)
        .onChange(of: recordLine?.beaten) { _, beaten in
            // One celebration per set, at the instant it's beaten — you're
            // usually mid-rep and not looking at the screen, so it has to be
            // felt rather than read.
            guard beaten == true, !hasBeatenRecord else { return }
            hasBeatenRecord = true
            Haptics.sessionComplete()
            AudioCoach.shared.recordBeaten()
        }
    }

    /// The clock for the attempt under way, plus how the set is going.
    ///
    /// A hold is measured in validated seconds, not wall time, and a set is
    /// several attempts rather than one — the big number is the hold you're
    /// in right now, and it resets each time you come down.
    private var holdReadout: some View {
        VStack(spacing: 6) {
            // Hundredths, because whole seconds make a running clock look
            // frozen — the digits moving are what say "this is counting".
            Text(SessionResult.preciseDurationLabel(holdClock))
                .font(Theme.Font.hudCounter())
                .monospacedDigit()
                .foregroundStyle(isHolding
                                 ? Theme.Color.primaryText
                                 : Theme.Color.primaryText.opacity(0.55))
                .shadow(color: .black.opacity(0.5), radius: 8)

            Text(holdSetSummary)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(Theme.Metric.labelTracking)
                .foregroundStyle(Theme.Color.secondaryText)
                .shadow(color: .black.opacity(0.5), radius: 6)

            // Straightness is feedback, never a gate — the clock above runs
            // regardless of what this says.
            if let quality = progress.formQuality {
                Text("LINE \(Int((quality * 100).rounded()))%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(Theme.Metric.labelTracking)
                    .foregroundStyle(quality > 0.75
                                     ? Theme.Color.valid : Theme.Color.secondaryText)
                    .shadow(color: .black.opacity(0.5), radius: 6)
            }
        }
    }

    private var isHolding: Bool { progress.currentHold > 0 }

    /// The running attempt, or the last one finished so you can read what you
    /// just did instead of watching it snap back to zero.
    private var holdClock: TimeInterval {
        isHolding ? progress.currentHold : (progress.holds.last?.duration ?? 0)
    }

    private var holdSetSummary: String {
        let completed = progress.holds.count
        guard completed > 0 || isHolding else { return "GET INVERTED TO START" }

        let number = completed + (isHolding ? 1 : 0)
        var parts = ["HOLD \(number)"]
        if completed > 0 {
            parts.append("BEST \(SessionResult.durationLabel(progress.bestHold))")
            parts.append("TOTAL \(SessionResult.durationLabel(progress.holdDuration))")
        }
        return parts.joined(separator: " · ")
    }

    /// Shown for movements that are selectable but have no state machine yet.
    private var unsupportedNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Color.secondaryText)
            Text("\(selected.displayName) tracking isn't ready yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)
            Text("You can still record the set — it just won't be scored.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 16))
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .frame(width: 48, height: 48)
                    .background(Theme.Color.card.opacity(0.85), in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    /// Zoom, shown as the options this camera actually has.
    ///
    /// Hidden entirely on the front camera: it has one lens, and a control
    /// with a single choice is decoration. The ultra-wide lives on the back
    /// camera, so flipping is how you reach 0.5×.
    @ViewBuilder
    private var lensButton: some View {
        if case .running = camera.status, camera.availableLenses.count > 1 {
            HStack(spacing: 2) {
                ForEach(camera.availableLenses, id: \.self) { option in
                    let isActive = option == camera.lens
                    Button {
                        guard option != camera.lens else { return }
                        // Not wrapped in withAnimation: the change lands after
                        // an await, so the container's `.animation(value:)`
                        // below is what actually drives the slide.
                        Task { await camera.setLens(option) }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isActive
                                             ? Theme.Color.background : Theme.Color.primaryText)
                            .frame(width: 42, height: 34)
                            .background {
                                // The selection slides between options rather
                                // than fading in place.
                                if isActive {
                                    Capsule()
                                        .fill(Theme.Color.primaryText)
                                        .matchedGeometryEffect(id: "lensPill", in: lensPill)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Theme.Color.card.opacity(0.8), in: .capsule)
            .animation(Theme.Motion.selection, value: camera.lens)
        }
    }

    /// Countdown length. Tapping opens the choices rather than cycling
    /// through them — with four values, cycling means up to three taps and a
    /// wrong guess to land on the one you wanted.
    private var timerButton: some View {
        HStack(spacing: 2) {
            if timerExpanded {
                ForEach(Self.countdownOptions, id: \.self) { option in
                    let isActive = option == settings.countdownSeconds
                    Button {
                        withAnimation(Theme.Motion.expand) {
                            settings.countdownSeconds = option
                            timerExpanded = false
                        }
                    } label: {
                        Text(option == 0 ? "Off" : "\(option)s")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isActive
                                             ? Theme.Color.background : Theme.Color.primaryText)
                            .frame(width: 38, height: 30)
                            .background {
                                if isActive {
                                    Capsule()
                                        .fill(Theme.Color.primaryText)
                                        .matchedGeometryEffect(id: "timerPill", in: timerPill)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    withAnimation(Theme.Motion.expand) { timerExpanded = true }
                } label: {
                    Group {
                        if settings.countdownSeconds == 0 {
                            Image(systemName: "timer")
                                .font(.system(size: 14, weight: .semibold))
                        } else {
                            Text("\(settings.countdownSeconds)s")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }
                    .foregroundStyle(settings.countdownSeconds == 0
                                     ? Theme.Color.primaryText : Theme.Color.background)
                    .frame(width: 30, height: 30)
                    .background {
                        if settings.countdownSeconds != 0 {
                            Capsule()
                                .fill(Theme.Color.primaryText)
                                .matchedGeometryEffect(id: "timerPill", in: timerPill)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Color.card.opacity(0.8), in: .capsule)
    }

    private static let countdownOptions = [0, 3, 5, 10]

    /// Everything about how this movement is coached and counted — spoken
    /// coaching included. Coaching had its own button here, which was a
    /// second place to change one setting; it belongs with the rest of the
    /// per-movement controls rather than beside them.
    private var tuneButton: some View {
        Button { showMovementSettings = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)
                .frame(width: 36, height: 36)
                .background(Theme.Color.card.opacity(0.8), in: .circle)
        }
        .buttonStyle(.plain)
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
                if poseSession.rejectedDetections > 0 {
                    Text("rejected \(poseSession.rejectedDetections)")
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                if let d = tracker?.diagnostics {
                    Text(d.readyLabel)
                        .foregroundStyle(d.isReady ? Theme.Color.valid : Theme.Color.secondaryText)
                    Text("\(d.primaryAngleLabel) \(angleText(d.primaryAngle))")
                    Text("\(d.secondaryAngleLabel) \(angleText(d.secondaryAngle))")
                    if let note = d.note {
                        Text(note)
                            .foregroundStyle(d.noteIsWarning
                                             ? Theme.Color.warning : Theme.Color.valid)
                    }
                } else {
                    Text("no tracker").foregroundStyle(Theme.Color.warning)
                }
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

    /// The number to beat for the selected movement: best single hold, or
    /// best set. Never the session total — six 5s handstands are not a 30s
    /// handstand (POSE.md §8).
    private var currentRecord: Double {
        let relevant = allSessions.filter { $0.movement == selected }
        return selected.isTimedHold
            ? (relevant.map(\.bestHold).max() ?? 0)
            : Double(relevant.map(\.repCount).max() ?? 0)
    }

    /// How the set is going against that record, or nil when there's nothing
    /// to beat yet — a first-ever set shouldn't be told it's behind.
    private var recordLine: (text: String, beaten: Bool)? {
        guard phase == .recording, recordToBeat > 0 else { return nil }
        let current = selected.isTimedHold
            ? progress.bestHold
            : Double(progress.reps)

        if current > recordToBeat {
            return ("NEW BEST", true)
        }
        let label = selected.isTimedHold
            ? SessionResult.durationLabel(recordToBeat)
            : "\(Int(recordToBeat))"
        return ("PB \(label)", false)
    }

    private func select(_ movement: Movement) {
        guard entitlements.canTrack(movement) else {
            showPaywall = true
            return
        }
        withAnimation(.snappy(duration: 0.2)) { selected = movement }
        // Swap in the matching state machine. Nil means the movement has no
        // tracker yet, which the HUD says out loud rather than counting
        // nothing and looking broken.
        tracker = TrackerFactory.make(for: movement)
        progress = tracker?.progress ?? MovementProgress()
        isInPosition = false
        lastEvent = nil
    }
}

#Preview {
    TrainIdleView()
        .environment(Entitlements())
        .modelContainer(SampleSessions.previewContainer)
        .preferredColorScheme(.dark)
}
