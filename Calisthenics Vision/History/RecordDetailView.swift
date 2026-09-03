//
//  RecordDetailView.swift
//  Calisthenics Vision
//
//  One number, explained and drawn properly.
//
//  A personal record card gives you a figure with no context: you can't tell
//  whether it's recent, whether it's climbing, or how it sits against every
//  other attempt. This is the screen behind the card — what the metric means,
//  how it's moved, and where today falls in the spread.
//
//  Uses Swift Charts rather than hand-rolled bars: three chart types earn
//  their place here (trend over time, distribution, and per-session values),
//  and each answers a different question about the same number.
//

import Charts
import SwiftData
import SwiftUI

struct RecordDetailView: View {

    /// What the card was measuring — each maps to one number per session.
    enum Metric: String, Identifiable {
        case bestHold, averageHold, straightness, kickUp
        case bestSet, totalReps

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bestHold:     "Longest hold"
            case .averageHold:  "Average hold"
            case .straightness: "Straightness"
            case .kickUp:       "Kick-up success"
            case .bestSet:      "Best set"
            case .totalReps:    "Total reps"
            }
        }

        /// What it means and, more usefully, what it doesn't.
        var explanation: String {
            switch self {
            case .bestHold:
                "Your longest single attempt — never the total across a set. Six five-second handstands are not a thirty-second handstand, so summing them would flatter you."
            case .averageHold:
                "The mean of every attempt. The best hold is a ceiling; this is the floor you can rely on, and it's the one that moves when you're genuinely getting better."
            case .straightness:
                "How close your line was to straight, scored from the worst joint rather than the average — a straight shoulder shouldn't mask a piked hip. Time-weighted, so a long scrappy hold counts more than a brief clean one."
            case .kickUp:
                "How often going up turned into a hold worth the name. Every entry into inversion counts as an attempt; anything reaching two seconds counts as landed."
            case .bestSet:
                "The most reps in one unbroken set. Stopping and starting again begins a new set."
            case .totalReps:
                "Every rep counted for this movement in the window, across all sets."
            }
        }

        var isPercentage: Bool { self == .straightness || self == .kickUp }
        var isDuration: Bool { self == .bestHold || self == .averageHold }
    }

    let metric: Metric
    let movement: Movement
    let sessions: [WorkoutSession]

    @Environment(\.dismiss) private var dismiss

    // MARK: - Data

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var points: [Point] {
        sessions
            .filter { $0.movement == movement }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { session in
                guard let value = value(for: session) else { return nil }
                return Point(date: session.startedAt, value: value)
            }
    }

    private func value(for session: WorkoutSession) -> Double? {
        switch metric {
        case .bestHold:
            session.bestHold > 0 ? session.bestHold : nil
        case .averageHold:
            session.holdSegments.isEmpty
                ? nil
                : session.holdSegments.reduce(0) { $0 + $1.duration } / Double(session.holdSegments.count)
        case .straightness:
            session.formQuality.map { $0 * 100 }
        case .kickUp:
            session.kickUpAttempts > 0
                ? Double(session.landedKickUps) / Double(session.kickUpAttempts) * 100
                : nil
        case .bestSet:
            session.repCount > 0 ? Double(session.repCount) : nil
        case .totalReps:
            session.repCount > 0 ? Double(session.repCount) : nil
        }
    }

    private var best: Double { points.map(\.value).max() ?? 0 }
    private var average: Double {
        points.isEmpty ? 0 : points.reduce(0) { $0 + $1.value } / Double(points.count)
    }
    private var latest: Double { points.last?.value ?? 0 }

    /// Change against the average of everything before the most recent third,
    /// so a single good day doesn't read as a trend.
    private var trend: Double? {
        guard points.count >= 4 else { return nil }
        let split = points.count * 2 / 3
        let earlier = points.prefix(split)
        let recent = points.suffix(points.count - split)
        guard !earlier.isEmpty, !recent.isEmpty else { return nil }

        let before = earlier.reduce(0) { $0 + $1.value } / Double(earlier.count)
        let after = recent.reduce(0) { $0 + $1.value } / Double(recent.count)
        guard before > 0 else { return nil }
        return (after - before) / before * 100
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    headline

                    if points.count < 2 {
                        notEnoughYet
                    } else {
                        chartSection(
                            "OVER TIME",
                            note: "Every session, oldest first.",
                            chart: trendChart
                        )
                        chartSection(
                            "SPREAD",
                            note: "How often you land in each band — a tight spread means it's repeatable, not lucky.",
                            chart: distributionChart
                        )
                    }

                    meaning
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Color.background)
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(format(best))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(movement.displayName.uppercased())
                    .cardLabelStyle()
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                stat("AVERAGE", format(average))
                stat("MOST RECENT", format(latest))
                stat("SESSIONS", "\(points.count)")
            }

            if let trend {
                HStack(spacing: 6) {
                    Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(trend >= 0 ? "+" : "")\(Int(trend.rounded()))% against your earlier sessions")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(trend >= 0 ? Theme.Color.valid : Theme.Color.warning)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Color.primaryText)
            Text(label).cardLabelStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private func chartSection(
        _ title: String, note: String, chart: some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeaderStyle()
            chart
                .frame(height: 170)
                .padding(14)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Line plus area: the shape of the trend, with each session marked so
    /// you can see how many points it's built from.
    private var trendChart: some View {
        Chart(points) { point in
            AreaMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Color.valid.opacity(0.28), Theme.Color.valid.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

            LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                .foregroundStyle(Theme.Color.valid)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)

            PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                .foregroundStyle(Theme.Color.valid)
                .symbolSize(26)

            RuleMark(y: .value("Average", average))
                .foregroundStyle(Theme.Color.secondaryText.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("avg")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.Color.divider.opacity(0.4))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(format(raw))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                }
            }
        }
    }

    private struct Band: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let isBest: Bool
    }

    /// Five bands between your worst and best, so you can see whether the
    /// record is typical or an outlier.
    private var bands: [Band] {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max(), high > low else { return [] }

        let width = (high - low) / 5
        return (0..<5).map { index in
            let lower = low + width * Double(index)
            let upper = index == 4 ? high : lower + width
            let count = values.filter { $0 >= lower && ($0 < upper || index == 4) }.count
            return Band(label: format(lower), count: count, isBest: index == 4)
        }
    }

    private var distributionChart: some View {
        Chart(bands) { band in
            BarMark(
                x: .value("Band", band.label),
                y: .value("Sessions", band.count)
            )
            .foregroundStyle(band.isBest ? Theme.Color.valid : Theme.Color.valid.opacity(0.35))
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.Color.divider.opacity(0.4))
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
    }

    private var notEnoughYet: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not enough sessions to chart")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Color.primaryText)
            Text("Two sessions with this measured and the graphs appear. Inventing a trend from one point would be worse than waiting.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 20)
    }

    private var meaning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT THIS MEANS").sectionHeaderStyle()
            Text(metric.explanation)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    // MARK: - Formatting

    private func format(_ value: Double) -> String {
        if metric.isDuration { return SessionResult.durationLabel(value) }
        if metric.isPercentage { return "\(Int(value.rounded()))%" }
        return "\(Int(value.rounded()))"
    }
}

#Preview {
    RecordDetailView(
        metric: .bestHold,
        movement: .handstand,
        sessions: SampleSessions.make()
    )
}
