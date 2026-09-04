//
//  AngleChartView.swift
//  Calisthenics Vision
//
//  Draws an AngleTimeline: the movement's defining angle over the set, on
//  bands that say what each part of the range means.
//
//  The line is coloured by the band it's in rather than drawn in one colour
//  over a striped background — the question a chart like this answers is
//  "was I in the right range, and when did that change", and colouring the
//  line answers it at a glance instead of asking the eye to compare a
//  wobbling line against a background.
//
//  In review the chart is wired to the video: it shows a playhead and you can
//  drag along it to scrub. That's the part a still image of a chart can't do,
//  and it turns "your shoulder opened at 6 seconds" into the frame where it
//  happened.
//

import SwiftUI

struct AngleChartCard: View {
    let timeline: AngleTimeline
    /// Capture-clock instant of the frame on screen, when there is one.
    var playheadMs: Int?
    /// Seeking, when the chart is attached to a player.
    var onSeek: ((Int) -> Void)?

    @State private var showsExplanation = false

    private var chartHeight: CGFloat { 150 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if showsExplanation { explanation }
            legend
            chart
            axis
        }
        .padding(18)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeline.title)
                    .cardLabelStyle()
                if let subtitle = timeline.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.tertiaryText)
                }
            }
            Spacer(minLength: 8)

            Button {
                withAnimation(Theme.Motion.expand) { showsExplanation.toggle() }
            } label: {
                Image(systemName: showsExplanation ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What this chart means")
        }
    }

    private var explanation: some View {
        Text(timeline.explanation)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Legend

    private var legend: some View {
        // Wraps rather than scrolls: three short labels fit a phone, and a
        // legend you have to swipe is a legend nobody reads.
        HStack(spacing: 14) {
            ForEach(timeline.zones) { zone in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.lineColor(zone.tone))
                        .frame(width: 8, height: 8)
                    Text("\(percent(timeline.share(of: zone))) \(zone.name)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.lineColor(zone.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // MARK: - Chart

    private var chart: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(.rect)
            .gesture(seekGesture(width: proxy.size.width))
        }
        .frame(height: chartHeight)
        .clipShape(.rect(cornerRadius: 8))
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let onSeek, width > 0, !timeline.samples.isEmpty else { return }
                let fraction = max(0, min(1, value.location.x / width))
                // Snap to a real sample rather than interpolating a
                // timestamp: every point on this line is a frame that
                // exists, and seeking should land on one.
                let index = Int((Double(timeline.samples.count - 1) * fraction).rounded())
                onSeek(timeline.samples[index].timestampMs)
            }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let lower = timeline.displayRange.lowerBound
        let upper = timeline.displayRange.upperBound
        let span = max(upper - lower, 1)

        func y(_ degrees: Double) -> CGFloat {
            let clamped = min(max(degrees, lower), upper)
            // Degrees run up the chart: a straighter joint reads as higher,
            // which is how everyone draws "better".
            return size.height * (1 - CGFloat((clamped - lower) / span))
        }

        // Bands
        for zone in timeline.zones {
            let top = y(zone.upper)
            let bottom = y(zone.lower)
            guard bottom - top > 0.5 else { continue }
            let rect = CGRect(x: 0, y: top, width: size.width, height: bottom - top)
            context.fill(Path(rect), with: .color(Self.bandColor(zone.tone)))

            // Hairline where one band becomes the next, so the boundary is
            // findable without labelling every axis tick.
            if zone.lower > lower {
                var separator = Path()
                separator.move(to: CGPoint(x: 0, y: bottom))
                separator.addLine(to: CGPoint(x: size.width, y: bottom))
                context.stroke(
                    separator,
                    with: .color(Theme.Color.primaryText.opacity(0.14)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )
            }
        }

        guard timeline.samples.count > 1, timeline.duration > 0 else { return }

        func x(_ seconds: Double) -> CGFloat {
            size.width * CGFloat(min(max(seconds / timeline.duration, 0), 1))
        }

        // One stroke per band, so each stretch of the line carries its own
        // colour without redrawing the whole path per segment.
        var paths: [String: Path] = [:]
        for index in 0..<(timeline.samples.count - 1) {
            let a = timeline.samples[index]
            let b = timeline.samples[index + 1]
            guard let zone = timeline.zones.first(where: { $0.contains(a.degrees) })
                    ?? timeline.zones.last
            else { continue }

            var path = paths[zone.name] ?? Path()
            path.move(to: CGPoint(x: x(a.seconds), y: y(a.degrees)))
            path.addLine(to: CGPoint(x: x(b.seconds), y: y(b.degrees)))
            paths[zone.name] = path
        }

        for zone in timeline.zones {
            guard let path = paths[zone.name] else { continue }
            context.stroke(
                path,
                with: .color(Self.lineColor(zone.tone)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }

        // Playhead
        if let playheadMs, let first = timeline.samples.first {
            let seconds = Double(playheadMs - first.timestampMs) / 1000
            guard seconds >= 0, seconds <= timeline.duration else { return }
            let position = x(seconds)

            var head = Path()
            head.move(to: CGPoint(x: position, y: 0))
            head.addLine(to: CGPoint(x: position, y: size.height))
            context.stroke(
                head,
                with: .color(Theme.Color.primaryText.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.5)
            )

            if let sample = nearestSample(to: playheadMs) {
                let center = CGPoint(x: position, y: y(sample.degrees))
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9
                    )),
                    with: .color(Theme.Color.primaryText)
                )
            }
        }
    }

    private func nearestSample(to timestampMs: Int) -> AngleTimeline.Sample? {
        timeline.samples.min {
            abs($0.timestampMs - timestampMs) < abs($1.timestampMs - timestampMs)
        }
    }

    // MARK: - Axis

    private var axis: some View {
        HStack {
            Text("0s")
            Spacer()
            Text(secondsLabel(timeline.duration / 2))
            Spacer()
            Text(secondsLabel(timeline.duration))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.Color.tertiaryText)
    }

    private func secondsLabel(_ seconds: Double) -> String {
        seconds >= 60
            ? SessionResult.durationLabel(seconds)
            : "\(Int(seconds.rounded()))s"
    }

    // MARK: - Colour

    /// Grades are green / amber / red; a rep's phases are not graded at all,
    /// so they stay white. Nothing is wrong with being at lockout.
    static func lineColor(_ tone: AngleZone.Tone) -> SwiftUI.Color {
        switch tone {
        case .good:    Theme.Color.valid
        case .fair:    Theme.Color.caution
        case .poor:    Theme.Color.warning
        case .neutral: Theme.Color.primaryText
        }
    }

    static func bandColor(_ tone: AngleZone.Tone) -> SwiftUI.Color {
        switch tone {
        case .neutral: Theme.Color.primaryText.opacity(0.04)
        default:       lineColor(tone).opacity(0.11)
        }
    }
}
