//
//  SessionReviewView.swift
//  Calisthenics Vision
//
//  Frame 05 — Session Review. Plays back a recorded set with the skeleton
//  overlaid, and reports the joint angles logged at whatever instant the
//  scrubber is sitting on (SPEC.md §3).
//
//  The telemetry file is what makes this frame-accurate: seeking is a lookup
//  in a flat array of fixed-size records, not a query.
//

import AVKit
import SwiftData
import SwiftUI

struct SessionReviewView: View {
    let session: WorkoutSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var player: AVPlayer?
    @State private var reader: TelemetryReader?
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var isPlaying = false
    @State private var showsSkeleton = true
    @State private var isScrubbing = false
    @State private var timeObserver: Any?
    @State private var showDeleteConfirmation = false

    /// Pose logged at the current playback position, if telemetry exists.
    private var poseAtCurrentTime: Pose? {
        guard let reader else { return nil }
        let base = session.videoStartMs ?? 0
        let target = Int32(base + Int(currentTime * 1000))
        guard let frame = reader.frame(nearest: target) else { return nil }

        let points = stride(from: 0, to: frame.values.count, by: 3).map { i in
            CGPoint(x: Double(frame.values[i]), y: Double(frame.values[i + 1]))
        }
        let world = stride(from: 0, to: frame.values.count, by: 3).map { i in
            SIMD3<Double>(
                Double(frame.values[i]),
                Double(frame.values[i + 1]),
                Double(frame.values[i + 2])
            )
        }
        return Pose(
            points: points,
            confidence: [Float](repeating: 1, count: points.count),
            worldPoints: world
        )
    }

    /// Event positions along the timeline, as fractions of the duration.
    private var markers: [(offset: Int, fraction: CGFloat, isBreak: Bool)] {
        guard duration > 0 else { return [] }
        let base = session.videoStartMs ?? 0

        func fraction(_ timestampMs: Int) -> CGFloat? {
            let seconds = Double(timestampMs - base) / 1000
            guard seconds >= 0, seconds <= duration else { return nil }
            return CGFloat(seconds / duration)
        }

        let reps = session.repTimestampsMs.compactMap { fraction($0) }
            .map { (fraction: $0, isBreak: false) }
        let breaks = session.formBreakTimestampsMs.compactMap { fraction($0) }
            .map { (fraction: $0, isBreak: true) }

        return (reps + breaks).enumerated().map {
            (offset: $0.offset, fraction: $0.element.fraction, isBreak: $0.element.isBreak)
        }
    }

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                videoStage
                scrubber
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.top, 18)
                jointAngles
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.top, 26)
                summary
                    .padding(.top, 22)
                Spacer(minLength: 0)
            }
        }
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.dark)
        .task { await load() }
        .onDisappear { teardown() }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                SessionStore.delete(session, context: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recording and its telemetry will be removed too.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.movement.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text("\(relativeDay) · \(session.timeLabel)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .padding(.leading, 8)

            Spacer()

            // Only meaningful when there's telemetry to draw.
            if reader != nil {
                Toggle("", isOn: $showsSkeleton)
                    .labelsHidden()
                    .tint(Theme.Color.valid)
            }

            Menu {
                Button("Delete Session", role: .destructive) {
                    showDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, Theme.Metric.screenPadding)
        .padding(.bottom, 18)
    }

    private var relativeDay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(session.startedAt) { return "Today" }
        if calendar.isDateInYesterday(session.startedAt) { return "Yesterday" }
        return session.startedAt.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Video

    private var videoStage: some View {
        ZStack {
            Rectangle().fill(Theme.Color.card)

            if let player {
                VideoPlayerLayer(player: player)
            }

            if showsSkeleton, let pose = poseAtCurrentTime {
                PoseOverlayView(pose: pose, isFormValid: true)
            }

            if player == nil {
                // A session can exist without a recording — recording can fail,
                // and older sessions predate it entirely.
                VStack(spacing: 10) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.Color.secondaryText)
                    Text("No recording saved for this session")
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            } else {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Color.primaryText)
                        .frame(width: 64, height: 64)
                        .background(.black.opacity(0.45), in: .circle)
                }
                .buttonStyle(.plain)
                .opacity(isPlaying ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
            }
        }
        .frame(height: 340)
        .clipped()
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let fraction = duration > 0 ? currentTime / duration : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Color.card)
                        .frame(height: 4)

                    // Event markers: green where a rep completed, red where
                    // form broke. These are why the timeline is worth
                    // scrubbing at all — you can go straight to the moment
                    // rather than hunting for it.
                    ForEach(markers, id: \.offset) { marker in
                        Capsule()
                            .fill(marker.isBreak ? Theme.Color.warning : Theme.Color.valid)
                            .frame(width: 2, height: 12)
                            .offset(x: marker.fraction * (width - 2))
                    }

                    Circle()
                        .fill(Theme.Color.primaryText)
                        .frame(width: 16, height: 16)
                        .offset(x: max(0, min(width - 16, fraction * width - 8)))
                }
                .frame(height: 20)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let ratio = max(0, min(1, value.location.x / width))
                            currentTime = ratio * duration
                            seek(to: currentTime)
                        }
                        .onEnded { _ in isScrubbing = false }
                )
            }
            .frame(height: 20)

            HStack {
                Text(SessionResult.durationLabel(currentTime))
                Spacer()
                Text(SessionResult.durationLabel(duration))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    // MARK: - Joint angles

    private var jointAngles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JOINT ANGLES · T = \(SessionResult.durationLabel(currentTime))")
                .cardLabelStyle()

            if let pose = poseAtCurrentTime {
                HStack(spacing: 0) {
                    angleReadout("Elbow", pose.angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist))
                    angleReadout("Hip", pose.angle(at: .leftHip, from: .leftShoulder, to: .leftAnkle))
                    angleReadout("Knee", pose.angle(at: .leftKnee, from: .leftHip, to: .leftAnkle))
                }
            } else {
                Text(session.telemetryFileName == nil
                     ? "No telemetry recorded for this session"
                     : "No pose logged at this moment")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private func angleReadout(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.secondaryText)
            Text(value.map { String(format: "%.0f°", $0) } ?? "—")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Text(session.result.displayValue)
            Text("·")
            Text("\(session.formBreaks) form break\(session.formBreaks == 1 ? "" : "s")")
            Text("·")
            Text(SessionResult.durationLabel(session.duration))
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.Color.secondaryText)
    }

    // MARK: - Playback

    private func load() async {
        if let name = session.telemetryFileName {
            reader = TelemetryReader(
                url: MediaLibrary.telemetryDirectory.appending(path: name)
            )
        }

        guard let url = session.videoURL,
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return }

        let asset = AVURLAsset(url: url)
        duration = (try? await asset.load(.duration).seconds) ?? session.duration

        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player

        // 10 Hz is enough for the readout to feel live without churning
        // through telemetry lookups on every frame.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !isScrubbing else { return }
            currentTime = time.seconds
        }
    }

    private func teardown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // Restart from the top rather than sticking at the end.
            if duration > 0, currentTime >= duration - 0.05 { seek(to: 0) }
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(to seconds: TimeInterval) {
        player?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
}

// MARK: - Player layer

/// Thin AVPlayerLayer wrapper — `VideoPlayer` would bring its own controls,
/// and this screen has a custom scrubber with event markers.
private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
