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
///
/// Identified by the bucket it covers rather than by a fresh UUID. A UUID
/// makes every recomputation a different view as far as SwiftUI is concerned,
/// so the bars could only ever pop in and out — with the date as the identity
/// the same week's bar is the same bar across a filter change, and its height
/// animates to the new value.
struct TrendPoint: Identifiable {
    let id: Date
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

    /// The same grouping said as a rate, for a label sitting next to a
    /// number: "AVG PER WEEK" rather than "AVG WEEKLY".
    var perBucketLabel: String {
        switch self {
        case .month:            "PER DAY"
        case .halfYear, .year:  "PER WEEK"
        case .all:              "PER MONTH"
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
    @State private var detail: RecordDetailView.Metric?

    private let filterOptions: [Movement] = [.pushUps, .pullUps, .squat, .dip, .handstand]

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
                        .animation(Theme.Motion.content, value: filter)
                        .animation(Theme.Motion.content, value: range)

                    Text(trendTitle)
                        .sectionHeaderStyle()
                        .padding(.bottom, 10)

                    progressionTrend
                        .animation(Theme.Motion.content, value: filter)
                        .animation(Theme.Motion.content, value: range)
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $detail) { metric in
            RecordDetailView(metric: metric, movement: filter, sessions: relevant)
        }
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
                id: start,
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

    /// Scrolls rather than wrapping or shrinking to fit — with five movements
    /// now (and more to come), an unscrollable row either overflows the
    /// screen width or has to squeeze each chip down to nothing. Five chips
    /// was the point this broke: a plain HStack has no ceiling, so it
    /// stretched the whole screen out with it.
    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filterOptions, id: \.self) { option in
                    FilterChip(title: option.displayName, isActive: option == filter) {
                        withAnimation(Theme.Motion.selection) { filter = option }
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Theme.Metric.screenPadding)
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
                    tappable(.bestHold, longestHold > 0
                             ? SessionResult.durationLabel(longestHold) : "—", "LONGEST HOLD")
                    tappable(.averageHold,
                             averageHold.map { SessionResult.durationLabel($0) } ?? "—",
                             "AVERAGE HOLD")
                }
                HStack(spacing: 12) {
                    tappable(.straightness,
                             averageLine.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                             "STRAIGHTNESS")
                    tappable(.kickUp,
                             kickUpRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                             kickUpAttempts > 0
                                ? "KICK-UP · \(kickUpsLanded)/\(kickUpAttempts)"
                                : "KICK-UP SUCCESS")
                }
            }
        } else {
            HStack(spacing: 12) {
                tappable(.bestSet, bestSet > 0 ? "\(bestSet)" : "—", "BEST SET")
                tappable(.totalReps, totalReps > 0 ? "\(totalReps)" : "—", "TOTAL REPS")
            }
        }
    }

    /// Every record opens its own screen — a number with no context can't
    /// tell you whether it's recent, climbing, or a fluke.
    private func tappable(
        _ metric: RecordDetailView.Metric, _ value: String, _ label: String
    ) -> some View {
        Button { detail = metric } label: {
            RecordCard(value: value, label: label, isTappable: true)
        }
        .buttonStyle(.plain)
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
                perBucketLabel: range.perBucketLabel,
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

/// The trend bars, with enough reference to answer "is that bar good?".
///
/// A row of bars on its own can only be read against itself: the tallest one
/// is full height whether it's four reps or four hundred, and every other bar
/// is a fraction of something unlabelled. Three things fix that without
/// adding chrome — a faint track behind each bar so an empty period still
/// occupies space and reads as a period you didn't train, a dashed line at
/// your own average so every bar is immediately above or below it, and the
/// two numbers that set the scale printed underneath.
private struct TrendChart: View {
    let points: [TrendPoint]
    let isDimmed: Bool
    /// "PER DAY" / "PER WEEK" / "PER MONTH", following the selected range.
    let perBucketLabel: String
    let formatter: (Double) -> String

    private let plotHeight: CGFloat = 150

    private var maxValue: Double { max(points.map(\.value).max() ?? 1, 1) }

    private var average: Double {
        guard !points.isEmpty else { return 0 }
        return points.reduce(0) { $0 + $1.value } / Double(points.count)
    }

    var body: some View {
        VStack(spacing: 0) {
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                bars
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                footer
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    // MARK: - Bars

    private var bars: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(points) { point in
                        ZStack(alignment: .bottom) {
                            // The track is the whole plot, so a period with
                            // nothing in it is still a column rather than a
                            // gap the eye skips over.
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.Color.primaryText.opacity(0.05))
                                .frame(height: plotHeight)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.Color.primaryText.opacity(
                                    isDimmed ? 0.12 : (point.isToday ? 1.0 : 0.75)
                                ))
                                .frame(height: max(2, (point.value / maxValue) * plotHeight))
                        }
                        .frame(maxWidth: 36)
                    }
                }
                .frame(height: plotHeight, alignment: .bottom)

                averageLine
            }
            .frame(height: plotHeight)

            HStack(alignment: .top, spacing: 8) {
                ForEach(points) { point in
                    Text(point.label)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Color.tertiaryText)
                        .frame(maxWidth: 36)
                }
            }
        }
    }

    /// Drawn at your own average rather than at a goal: this app has never
    /// asked anyone to set a target, and inventing one here would be the
    /// first place it did.
    private var averageLine: some View {
        let height = min(plotHeight, (average / maxValue) * plotHeight)

        // Pinned by padding from the bottom rather than by an offset, so the
        // rule lands exactly `height` above the baseline the bars grow from.
        // A ZStack sized to its tallest child would float the line by half a
        // label's height, which is a few percent of the scale.
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.Color.primaryText.opacity(isDimmed ? 0.1 : 0.32))
                    .frame(height: 1)
                    .overlay {
                        // Dashed in the card colour over the fill, so it
                        // reads as a reference rather than as a bar's edge.
                        Line()
                            .stroke(
                                Theme.Color.card,
                                style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                            )
                            .opacity(isDimmed ? 0 : 0.9)
                    }

                Text("AVG")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(Theme.Metric.labelTracking)
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .padding(.horizontal, 3)
                    .background(Theme.Color.card)
                    .offset(y: -8)
                    .opacity(isDimmed ? 0 : 1)
            }
            .frame(height: 1)
            .padding(.bottom, height)
        }
        .frame(height: plotHeight)
        .allowsHitTesting(false)
    }

    // MARK: - Footer

    /// The two numbers that give the bars a scale. Inside the card, and so
    /// inside the Pro scrim above it — these describe the locked chart and
    /// shouldn't leak out from under the lock.
    private var footer: some View {
        HStack(spacing: 14) {
            stat("BEST", formatter(maxValue))
            Rectangle()
                .fill(Theme.Color.primaryText.opacity(0.08))
                .frame(width: 1, height: 26)
            stat("AVG \(perBucketLabel)", formatter(average))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .cardLabelStyle()
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Color.primaryText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A horizontal rule, for dashing over a filled line.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct RecordCard: View {
    let value: String
    let label: String
    var isTappable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.Font.cardNumber())
                .foregroundStyle(Theme.Color.primaryText)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(label)
                    .cardLabelStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isTappable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.Color.tertiaryText)
                }
            }
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
