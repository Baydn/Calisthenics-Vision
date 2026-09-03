//
//  HistoryProgressView.swift
//  Calisthenics Vision
//
//  Progress for one movement over a chosen window. Personal records stay
//  free; the long-term progression chart is gated behind Pro (SPEC.md §4 —
//  "long-term progression graphs").
//
//  Holds and reps are different questions, so the metrics change with the
//  movement rather than showing a column of dashes: a handstand's progress is
//  its longest hold, how straight it was, its average attempt, and how often
//  the kick-up stuck.
//

import SwiftUI

/// One bar in the trend chart.
struct TrendPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let isToday: Bool
}

/// How far back Progress looks.
enum ProgressRange: String, CaseIterable, Hashable {
    case month = "M"
    case halfYear = "6M"
    case year = "Y"
    case all = "All"

    /// Days of history, or nil for everything.
    var days: Int? {
        switch self {
        case .month:    30
        case .halfYear: 182
        case .year:     365
        case .all:      nil
        }
    }

    /// How the trend groups: daily for a month, weekly up to a year, monthly
    /// beyond. Ten daily bars over a year would say nothing.
    var bucket: Calendar.Component {
        switch self {
        case .month:              .day
        case .halfYear, .year:    .weekOfYear
        case .all:                .month
        }
    }

    var bucketLabel: String {
        switch self {
        case .month:            "DAILY"
        case .halfYear, .year:  "WEEKLY"
        case .all:              "MONTHLY"
        }
    }
}

struct HistoryProgressView: View {
    let sessions: [WorkoutSession]
    let stats: SessionStats

    @Environment(Entitlements.self) private var entitlements
    @State private var filter: Movement = .pushUps
    @State private var range: ProgressRange = .month
    @State private var showPaywall = false

    private let filterOptions: [Movement] = [.pushUps, .handstand]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                filterRow
                    .padding(.bottom, 12)

                SegmentedControl(
                    segments: ProgressRange.allCases,
                    title: \.rawValue,
                    selection: $range
                )
                .padding(.bottom, 26)

                if relevant.isEmpty {
                    emptyState
                } else {
                    Text("PERSONAL RECORDS")
                        .sectionHeaderStyle()
                        .padding(.bottom, 10)

                    records
                        .padding(.bottom, 26)

                    Text(trendTitle)
                        .sectionHeaderStyle()
                        .padding(.bottom, 10)

                    progressionTrend
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Data

    private var measuresHold: Bool { filter.isTimedHold }

    /// Sessions for the selected movement inside the selected window.
    private var relevant: [WorkoutSession] {
        let cutoff = range.days.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: .now)
        }
        return sessions.filter { session in
            session.movement == filter
                && (cutoff.map { session.startedAt >= $0 } ?? true)
        }
    }

    /// Every individual hold in the window — the unit holds are judged in.
    private var holds: [HoldSegment] { relevant.flatMap(\.holdSegments) }

    private var longestHold: TimeInterval { relevant.map(\.bestHold).max() ?? 0 }

    /// Mean of every attempt, which is a fairer read of where you are than
    /// the best one — the best hold is a ceiling, the average is the floor
    /// you can rely on.
    private var averageHold: TimeInterval? {
        guard !holds.isEmpty else { return nil }
        return holds.reduce(0) { $0 + $1.duration } / Double(holds.count)
    }

    /// Straightness across the window, time-weighted so a long scrappy hold
    /// counts more than a two-second clean one.
    private var averageLine: Double? {
        let scored = holds.filter { $0.quality != nil }
        guard !scored.isEmpty else {
            return relevant.compactMap(\.formQuality).averageOrNil
        }
        let weight = scored.reduce(0) { $0 + $1.duration }
        guard weight > 0 else { return nil }
        return scored.reduce(0) { $0 + ($1.quality ?? 0) * $1.duration } / weight
    }

    private var kickUpAttempts: Int { relevant.reduce(0) { $0 + $1.kickUpAttempts } }
    private var kickUpsLanded: Int { relevant.reduce(0) { $0 + $1.landedKickUps } }

    /// Share of kick-ups that turned into a hold. Nil where no session has
    /// recorded attempts — sessions from before this was tracked would
    /// otherwise read as 0%, which is worse than saying nothing.
    private var kickUpRate: Double? {
        guard kickUpAttempts > 0 else { return nil }
        return Double(kickUpsLanded) / Double(kickUpAttempts)
    }

    /// Trend buckets, most recent last.
    ///
    /// Reps sum within a bucket; holds take the best, since two short
    /// handstands aren't the same achievement as one long one.
    private var trend: [TrendPoint] {
        let calendar = Calendar.current
        guard !relevant.isEmpty else { return [] }

        let grouped = Dictionary(grouping: relevant) { session -> Date in
            calendar.dateInterval(of: range.bucket, for: session.startedAt)?.start
                ?? calendar.startOfDay(for: session.startedAt)
        }

        return grouped.keys.sorted().suffix(10).map { start in
            let items = grouped[start] ?? []
            let value = measuresHold
                ? (items.map(\.bestHold).max() ?? 0)
                : Double(items.reduce(0) { $0 + $1.repCount })
            return TrendPoint(
                label: label(for: start, calendar: calendar),
                value: value,
                isToday: calendar.isDateInToday(start)
            )
        }
    }

    private func label(for date: Date, calendar: Calendar) -> String {
        switch range.bucket {
        case .month:      date.formatted(.dateTime.month(.narrow))
        case .weekOfYear: date.formatted(.dateTime.day())
        default:          date.formatted(.dateTime.day())
        }
    }

    // MARK: - Controls

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(filterOptions, id: \.self) { option in
                FilterChip(title: option.displayName, isActive: option == filter) {
                    withAnimation(.snappy(duration: 0.2)) { filter = option }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var trendTitle: String {
        measuresHold
            ? "PROGRESSION TREND · \(range.bucketLabel) BEST HOLD"
            : "PROGRESSION TREND · \(range.bucketLabel) REPS"
    }

    // MARK: - Records

    @ViewBuilder
    private var records: some View {
        if measuresHold {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    RecordCard(
                        value: longestHold > 0
                            ? SessionResult.durationLabel(longestHold) : "—",
                        label: "LONGEST HOLD"
                    )
                    RecordCard(
                        value: averageHold.map { SessionResult.durationLabel($0) } ?? "—",
                        label: "AVERAGE HOLD"
                    )
                }
                HStack(spacing: 12) {
                    RecordCard(
                        value: averageLine.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                        label: "STRAIGHTNESS"
                    )
                    RecordCard(
                        value: kickUpRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                        label: kickUpAttempts > 0
                            ? "KICK-UP · \(kickUpsLanded)/\(kickUpAttempts)"
                            : "KICK-UP SUCCESS"
                    )
                }
            }
        } else {
            HStack(spacing: 12) {
                RecordCard(
                    value: bestSet > 0 ? "\(bestSet)" : "—",
                    label: "BEST SET"
                )
                RecordCard(
                    value: totalReps > 0 ? "\(totalReps)" : "—",
                    label: "TOTAL REPS"
                )
            }
        }
    }

    private var bestSet: Int { relevant.map(\.repCount).max() ?? 0 }
    private var totalReps: Int { relevant.reduce(0) { $0 + $1.repCount } }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing logged in this window")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Color.primaryText)
            Text("Record a \(filter.displayName.lowercased()) session, or widen the range.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 40)
    }

    private var progressionTrend: some View {
        ZStack {
            TrendChart(
                points: trend,
                isDimmed: !entitlements.isProUnlocked,
                formatter: measuresHold
                    ? { SessionResult.durationLabel($0) }
                    : { "\(Int($0))" }
            )

            if !entitlements.isProUnlocked {
                // Scrim so the upsell copy stays legible over the bars
                // regardless of how tall the underlying data runs.
                RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                    .fill(Theme.Color.background.opacity(0.55))

                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.Color.primaryText)
                    Text("Long-term progression is a Pro feature")
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Upgrade to Pro") { showPaywall = true }
                        .font(Theme.Font.controlActive())
                        .foregroundStyle(Theme.Color.background)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(Theme.Color.primaryText, in: .capsule)
                        .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
    }
}

private extension Array where Element == Double {
    var averageOrNil: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }
}

private struct TrendChart: View {
    let points: [TrendPoint]
    let isDimmed: Bool
    let formatter: (Double) -> String

    var body: some View {
        GeometryReader { proxy in
            if points.isEmpty {
                // An empty chart is better than an invented one: fabricated
                // bars read as real training history.
                VStack(spacing: 6) {
                    Text("Not enough history yet")
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.secondaryText)
                    Text("Record a few sessions and your trend appears here.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart(in: proxy.size)
            }
        }
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private func chart(in size: CGSize) -> some View {
        let maxValue = max(points.map(\.value).max() ?? 1, 1)
        let available = size.width - 40
        let spacing: CGFloat = 8
        let barWidth = max(
            6,
            (available - spacing * CGFloat(points.count - 1)) / CGFloat(points.count)
        )
        let plotHeight = size.height - 58

        return VStack(spacing: 6) {
            // Peak value, so the bars carry a scale rather than being
            // decorative shapes.
            Text(formatter(maxValue))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Color.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(points) { point in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.Color.primaryText.opacity(
                                isDimmed ? 0.12 : (point.isToday ? 1.0 : 0.75)
                            ))
                            .frame(
                                width: barWidth,
                                height: max(2, (point.value / maxValue) * plotHeight)
                            )
                        Text(point.label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct RecordCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.Font.cardNumber())
                .foregroundStyle(Theme.Color.primaryText)
            Spacer(minLength: 0)
            Text(label)
                .cardLabelStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(height: 90)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }
}

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        HistoryProgressView(
            sessions: SampleSessions.make(),
            stats: SessionStore.stats(for: SampleSessions.make())
        )
        .environment(Entitlements())
    }
    .preferredColorScheme(.dark)
}
