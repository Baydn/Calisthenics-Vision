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
    /// Capture-clock instant to seek to once the video has loaded — how a
    /// takeaway on the set summary jumps straight to the frame it names.
    var initialSeekMs: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// `.compact` means landscape on iPhone, where a fixed-height video stage
    /// would leave no room for anything underneath it.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var settings = AppSettings.shared
    @State private var player: AVPlayer?
    @State private var reader: TelemetryReader?
    /// The set's defining angle(s) over time. Built once when the screen
    /// loads — it's a full pass over the telemetry, not something to redo
    /// on every scrub.
    @State private var timelines: [AngleTimeline] = []
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var timeObserver: Any?
    /// Width ÷ height of the recording, so the overlay lands on the body.
    @State private var videoAspect: CGFloat = 9.0 / 16.0
    @State private var showDeleteConfirmation = false
    /// A frame from the recording, blurred behind the video to fill the
    /// letterbox. A portrait clip in a landscape-ish stage leaves bars either
    /// way; grey ones read as a broken layout, a soft backdrop reads as intent.
    @State private var poster: UIImage?
    /// Controls fade out during playback and come back on a tap.
    @State private var showsControls = true
    @State private var controlHideTask: Task<Void, Never>?

    /// Pose logged at the current playback position, if telemetry exists.
    private var poseAtCurrentTime: Pose? {
        guard let reader else { return nil }
        let base = session.videoStartMs ?? 0
        let target = Int32(base + Int(currentTime * 1000))
        guard let frame = reader.frame(nearest: target) else { return nil }

        return Pose(
            points: frame.imagePoints,
            confidence: [Float](repeating: 1, count: Telemetry.landmarkCount),
            aspect: videoAspect,
            worldPoints: frame.worldPoints
        )
    }

    /// The chosen style, except that hiding the skeleton is the mode
    /// picker's job here — "Off" is one of the modes.
    private var reviewStyle: PoseOverlayStyle {
        settings.overlayStyle == .off ? .outline : settings.overlayStyle
    }

    /// Modes this movement actually has something to draw for.
    private var overlayModes: [ReviewOverlayMode] {
        ReviewOverlayMode.available(for: session.movement)
    }

    /// The chosen mode, falling back when it isn't offered for this movement —
    /// picking "Angle" on a handstand shouldn't leave a muscle-up blank.
    private var overlayMode: ReviewOverlayMode {
        overlayModes.contains(settings.reviewOverlayMode) ? settings.reviewOverlayMode : .skeleton
    }

    enum MarkerKind {
        case rep, formBreak, holdStart

        var color: SwiftUI.Color {
            switch self {
            case .rep:       Theme.Color.valid
            case .formBreak: Theme.Color.warning
            case .holdStart: Theme.Color.primaryText
            }
        }
    }

    /// Event positions along the timeline, as fractions of the duration.
    private var markers: [(offset: Int, fraction: CGFloat, kind: MarkerKind)] {
        guard duration > 0 else { return [] }

        let reps = session.repTimestampsMs.compactMap { fraction(of: $0) }
            .map { (fraction: $0, kind: MarkerKind.rep) }
        let breaks = session.formBreakTimestampsMs.compactMap { fraction(of: $0) }
            .map { (fraction: $0, kind: MarkerKind.formBreak) }
        let holds = session.holdStartsMs.compactMap { fraction(of: $0) }
            .map { (fraction: $0, kind: MarkerKind.holdStart) }

        return (reps + breaks + holds).enumerated().map {
            (offset: $0.offset, fraction: $0.element.fraction, kind: $0.element.kind)
        }
    }

    /// Where a capture-clock instant sits along the recording, 0…1.
    private func fraction(of timestampMs: Int) -> CGFloat? {
        guard duration > 0 else { return nil }
        let seconds = Double(timestampMs - (session.videoStartMs ?? 0)) / 1000
        guard seconds >= 0, seconds <= duration else { return nil }
        return CGFloat(seconds / duration)
    }

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                videoStage

                // Scrolls so the detail below the video stays reachable in
                // landscape, where the stage takes most of the screen.
                ScrollView {
                    VStack(spacing: 0) {
                        scrubber
                            .padding(.horizontal, Theme.Metric.screenPadding)
                            .padding(.top, 18)
                        overlayPicker
                            .padding(.horizontal, Theme.Metric.screenPadding)
                            .padding(.top, 20)
                        jointAngles
                            .padding(.horizontal, Theme.Metric.screenPadding)
                            .padding(.top, 26)
                        angleCharts
                            .padding(.horizontal, Theme.Metric.screenPadding)
                        holdBreakdown
                        summary
                            .padding(.top, 22)
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.dark)
        .task { await load() }
        .onDisappear { teardown() }
        // Reaching the end used to leave `isPlaying` stuck true, which hid
        // the only play button on screen and made the video unplayable.
        .onReceive(
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
        ) { _ in
            isPlaying = false
            if duration > 0 { currentTime = duration }
            revealControls(persist: true)
        }
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

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    /// Only a ceiling, so a very tall clip can't push the scrubber off the
    /// screen entirely. Portrait video is meant to be tall here.
    private var maxStageHeight: CGFloat {
        isCompactHeight ? 240 : 720
    }

    private var videoStage: some View {
        ZStack {
            // Black rather than card grey, so the letterbox reads as part of
            // the screen instead of an unfilled container.
            Rectangle().fill(Theme.Color.background)

            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                    .overlay(Theme.Color.background.opacity(0.45))
                    .allowsHitTesting(false)
            }

            if let player {
                VideoPlayerLayer(player: player)
            }

            if overlayMode != .off, let pose = poseAtCurrentTime {
                // The player fits, so every overlay has to fit the same way or
                // it drifts off the body.
                //
                // Line keeps the full skeleton — the reference line is read
                // against the body, so the body has to be there. Angle drops
                // it entirely: the whole point of that mode is one joint with
                // nothing else competing for attention.
                if overlayMode != .angle {
                    PoseOverlayView(
                        pose: pose,
                        isFormValid: true,
                        isEngaged: session.movement.isInPosition(pose) ?? true,
                        style: reviewStyle,
                        sourceAspect: videoAspect,
                        contentMode: .fit
                    )
                }

                PoseAnnotationView(
                    pose: pose,
                    movement: session.movement,
                    mode: overlayMode,
                    sourceAspect: videoAspect,
                    contentMode: .fit
                )
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
                .opacity(showsControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showsControls)
            }
        }
        // The stage takes the recording's own shape at full width, so the
        // whole frame is on screen at its natural proportions with nothing
        // to crop against and no bands to fill. Fixing the height and fitting
        // inside it was the mistake: any height that isn't width ÷ aspect
        // either crops or leaves bars, and I kept adjusting which.
        .aspectRatio(videoAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxStageHeight)
        .clipped()
        .contentShape(.rect)
        // Tapping the video is how people expect to pause. Without it the
        // only control was a button that hid itself while playing.
        .onTapGesture {
            if isPlaying && showsControls {
                togglePlayback()
            } else if isPlaying {
                revealControls()
            } else {
                togglePlayback()
            }
        }
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
                    // form broke, white where a hold began. These are why the
                    // timeline is worth scrubbing at all — you can go straight
                    // to the moment rather than hunting for it.
                    ForEach(markers, id: \.offset) { marker in
                        Capsule()
                            .fill(marker.kind.color)
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
                            seek(to: ratio * duration)
                        }
                        .onEnded { _ in isScrubbing = false }
                )
            }
            .frame(height: 20)

            HStack(spacing: 12) {
                // Always here, whatever the video is doing — the on-video
                // button fades, this one doesn't.
                Button(action: togglePlayback) {
                    Image(systemName: playButtonSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.primaryText)
                        .frame(width: 30, height: 30)
                        .background(Theme.Color.card, in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(player == nil)

                Text(SessionResult.preciseDurationLabel(currentTime))
                Spacer()
                Text(SessionResult.durationLabel(duration))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    /// How to look at the frame on screen.
    ///
    /// Only shown when there's telemetry behind it — with no landmarks logged
    /// there is nothing for any of these modes to draw, and offering the
    /// choice would be offering nothing.
    @ViewBuilder
    private var overlayPicker: some View {
        if reader != nil {
            VStack(alignment: .leading, spacing: 8) {
                SegmentedControl(
                    segments: overlayModes,
                    title: \.title,
                    selection: Binding(
                        get: { overlayMode },
                        set: { settings.reviewOverlayMode = $0 }
                    )
                )
                Text(overlayHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var overlayHint: String {
        switch overlayMode {
        case .skeleton:
            return "Every tracked joint, frame by frame."
        case .line:
            if session.movement.holdsAVerticalLine {
                return "Dashed is straight up from your hands — lean shows as the body drifting off it. Solid is the line you made; the gap between them is the bend."
            }
            let chain = session.movement.alignmentChain
            let ends = [chain?.first, chain?.last].compactMap { $0?.shortName.lowercased() }
            let between = ends.count == 2 ? "from \(ends[0]) to \(ends[1])" : "through your body"
            return "Dashed is the straight line \(between); solid is the line you made. The gap between them is the bend."
        case .angle:
            return "The joint this movement is judged at. The arc is what the camera saw; the number is measured in 3D, so it stays right even filmed head-on."
        case .off:
            return "Just the recording."
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

    /// The movement's own angle, banded and plotted, with the playhead on it.
    ///
    /// Wired to the player both ways: it marks where you are, and dragging
    /// across it seeks. That's what makes this different from a chart you
    /// can only look at — you can see the shoulder open at six seconds and
    /// then go and watch it happen.
    @ViewBuilder
    private var angleCharts: some View {
        if !timelines.isEmpty {
            VStack(spacing: 14) {
                ForEach(timelines) { timeline in
                    AngleChartCard(
                        timeline: timeline,
                        playheadMs: (session.videoStartMs ?? 0) + Int(currentTime * 1000),
                        onSeek: { ms in
                            guard let f = fraction(of: ms) else { return }
                            isScrubbing = true
                            seek(to: f * duration)
                            isScrubbing = false
                        }
                    )
                }
            }
            .padding(.top, 22)
        }
    }

    /// Each hold in the set, tappable to jump straight to it.
    ///
    /// A set of six attempts is six separate things to look at, and the
    /// interesting question is usually "what was different about the good
    /// one?" — so each chip carries its own line score and seeks to its start.
    @ViewBuilder
    private var holdBreakdown: some View {
        let holds = session.holdSegments
        if holds.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("HOLDS")
                    .cardLabelStyle()
                    .padding(.horizontal, Theme.Metric.screenPadding)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(holds.enumerated()), id: \.offset) { index, hold in
                            Button {
                                guard let f = fraction(of: hold.startTimestampMs) else { return }
                                seek(to: f * duration, thenPlay: true)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("HOLD \(index + 1)")
                                        .cardLabelStyle()
                                    Text(SessionResult.preciseDurationLabel(hold.duration))
                                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.Color.primaryText)
                                    Text(hold.quality.map { "\(Int(($0 * 100).rounded()))% line" }
                                         ?? "line —")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(
                                            (hold.quality ?? 0) > 0.75
                                                ? Theme.Color.valid : Theme.Color.secondaryText
                                        )
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Theme.Color.card,
                                    in: .rect(cornerRadius: Theme.Metric.cardRadius)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Metric.screenPadding)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 22)
        }
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Text(session.result.displayValue)
            if let quality = session.formQualityLabel {
                Text("·")
                Text("\(quality) line")
            }
            Text("·")
            Text("\(session.formBreaks) form break\(session.formBreaks == 1 ? "" : "s")")
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
            timelines = AngleTimelineBuilder.timelines(for: session)
        }

        guard let url = session.videoURL,
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return }

        defer {
            if let target = initialSeekMs {
                let base = session.videoStartMs ?? 0
                let seconds = max(0, Double(target - base) / 1000)
                currentTime = seconds
                seek(to: seconds)
            }
        }

        let asset = AVURLAsset(url: url)
        duration = (try? await asset.load(.duration).seconds) ?? session.duration

        // Read the real presentation size so the overlay matches the video
        // rather than assuming portrait.
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let presented = size.applying(transform)
            let w = abs(presented.width), h = abs(presented.height)
            if w > 0, h > 0 { videoAspect = w / h }
        }

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
            // Trust the player over our own flag: pausing can also come from
            // an interruption, a route change, or the end of the item.
            isPlaying = player.timeControlStatus == .playing
        }

        await loadPoster(from: asset, duration: duration)
    }

    private func teardown() {
        controlHideTask?.cancel()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
    }

    private var playButtonSymbol: String {
        if isPlaying { return "pause.fill" }
        return isAtEnd ? "arrow.counterclockwise" : "play.fill"
    }

    private var isAtEnd: Bool {
        duration > 0 && currentTime >= duration - 0.08
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            revealControls(persist: true)
        } else {
            // Playing from the end restarts, rather than sitting there doing
            // nothing — which is what it did before, because `isPlaying` was
            // never cleared when the video finished.
            if isAtEnd { seek(to: 0) }
            player.play()
            isPlaying = true
            revealControls()
        }
    }

    /// Shows the on-video control, hiding it again after a moment unless
    /// playback is stopped.
    private func revealControls(persist: Bool = false) {
        controlHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { showsControls = true }
        guard !persist else { return }
        controlHideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showsControls = false }
        }
    }

    /// Jumps to a point and keeps playing from there. Seeking to a hold and
    /// then having to find the play button is a step nobody wants.
    private func seek(to seconds: TimeInterval, thenPlay: Bool = false) {
        let clamped = max(0, min(duration > 0 ? duration : seconds, seconds))
        currentTime = clamped
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if thenPlay, let player {
            player.play()
            isPlaying = true
            revealControls()
        }
    }

    /// A still from the recording, used as the blurred backdrop.
    private func loadPoster(from asset: AVURLAsset, duration: TimeInterval) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        // A third of the way in: the first frame is often the person still
        // walking into shot.
        let at = CMTime(seconds: max(0.1, duration / 3), preferredTimescale: 600)
        if let image = try? await generator.image(at: at).image {
            poster = UIImage(cgImage: image)
        }
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
        // Fit, so the whole recording is visible. The bands either side are
        // filled with a blurred still from the clip itself, which reads as
        // part of the picture rather than as missing screen.
        view.playerLayer.videoGravity = .resizeAspect
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
