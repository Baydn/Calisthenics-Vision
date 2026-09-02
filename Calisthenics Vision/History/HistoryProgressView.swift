//
//  HistoryProgressView.swift
//  Calisthenics Vision
//
//  Personal records stay free; the long-term progression chart is gated
//  behind Pro (SPEC.md §4 — "long-term progression graphs").
//

import SwiftUI

/// One bar in the trend chart.
struct TrendPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let isToday: Bool
}

struct HistoryProgressView: View {
    let sessions: [WorkoutSession]
    let stats: SessionStats

    @Environment(Entitlements.self) private var entitlements
    @State private var filter: Movement?          // nil == "All"
    @State private var showPaywall = false

    private let filterOptions: [Movement?] = [nil, .pushUps, .handstand]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                filterRow
                    .padding(.bottom, 26)

                Text("PERSONAL RECORDS")
                    .sectionHeaderStyle()
                    .padding(.bottom, 10)

                personalRecords
                    .padding(.bottom, 26)

                Text(trendTitle)
                    .sectionHeaderStyle()
                    .padding(.bottom, 10)

                progressionTrend
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Data

    /// Daily totals for the selected movement, most recent last.
    ///
    /// Reps sum across a day; holds take the day's best, since two short
    /// handstands aren't the same achievement as one long one.
    private var trend: [TrendPoint] {
        let calendar = Calendar.current
        let relevant = sessions.filter { filter == nil || $0.movement == filter }
        guard !relevant.isEmpty else { return [] }

        let byDay = Dictionary(grouping: relevant) {
            calendar.startOfDay(for: $0.startedAt)
        }

        return byDay.keys.sorted().suffix(10).map { day in
            let items = byDay[day] ?? []
            let value = measuresHold
                ? (items.map(\.duration).max() ?? 0)
                : Double(items.reduce(0) { $0 + $1.repCount })

            return TrendPoint(
                label: day.formatted(.dateTime.day()),
                value: value,
                isToday: calendar.isDateInToday(day)
            )
        }
    }

    private var measuresHold: Bool { filter?.isTimedHold ?? false }

    private var trendTitle: String {
        switch filter {
        case .none:            "PROGRESSION TREND · DAILY REPS"
        case .some(let m) where m.isTimedHold: "PROGRESSION TREND · BEST HOLD"
        case .some:            "PROGRESSION TREND · DAILY REPS"
        }
    }

    // MARK: - Pieces

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(filterOptions, id: \.self) { option in
                FilterChip(
                    title: option?.displayName ?? "All",
                    isActive: option == filter
                ) {
                    withAnimation(.snappy(duration: 0.2)) { filter = option }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var personalRecords: some View {
        HStack(spacing: 12) {
            RecordCard(
                value: stats.bestPushUpSet > 0 ? "\(stats.bestPushUpSet)" : "—",
                label: "BEST PUSH-UP SET"
            )
            RecordCard(
                value: stats.longestHold > 0
                    ? SessionResult.durationLabel(stats.longestHold)
                    : "—",
                label: "LONGEST HANDSTAND"
            )
        }
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

                VStack(spacing: 14) {
                    Circle()
                        .fill(Theme.Color.elevated)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.Color.primaryText)
                        }

                    Text("See your full progress with Pro")
                        .font(Theme.Font.control())
                        .foregroundStyle(Theme.Color.secondaryText)

                    Button { showPaywall = true } label: {
                        Text("Upgrade to Pro")
                            .font(Theme.Font.controlActive())
                            .foregroundStyle(Theme.Color.background)
                            .padding(.horizontal, 22)
                            .frame(height: 34)
                            .background(Theme.Color.primaryText, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 190)
    }
}

// MARK: - Record card

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(height: 90)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }
}

// MARK: - Trend chart

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

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        HistoryProgressView(
            sessions: SampleSessions.make(),
            stats: SessionStore.stats(for: SampleSessions.make())
        )
    }
    .environment(Entitlements())
    .preferredColorScheme(.dark)
}
