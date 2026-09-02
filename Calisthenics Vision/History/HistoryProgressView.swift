//
//  HistoryProgressView.swift
//  Calisthenics Vision
//
//  Personal records stay free; the long-term progression chart is gated
//  behind Pro (SPEC.md §4 — "long-term progression graphs").
//

import SwiftUI

struct HistoryProgressView: View {
    let sessions: [Session]

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

                Text("PROGRESSION TREND")
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
                value: "\(SampleData.bestPushUpSet)",
                label: "BEST PUSH-UP SET"
            )
            RecordCard(
                value: SessionResult.hold(SampleData.longestHandstand)
                    .displayValue
                    .replacingOccurrences(of: " hold", with: ""),
                label: "LONGEST HANDSTAND"
            )
        }
    }

    private var progressionTrend: some View {
        ZStack {
            TrendChart(values: trendValues, isDimmed: !entitlements.isProUnlocked)

            if !entitlements.isProUnlocked {
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

    /// Placeholder series until the telemetry store can supply real history.
    private var trendValues: [Double] {
        [28, 34, 30, 46, 52, 48, 64, 70, 60, 90]
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
    let values: [Double]
    let isDimmed: Bool

    var body: some View {
        GeometryReader { proxy in
            let maxValue = values.max() ?? 1
            let barWidth: CGFloat = 14
            let spacing = (proxy.size.width - 40 - barWidth * CGFloat(values.count))
                / CGFloat(max(values.count - 1, 1))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Color.primaryText.opacity(isDimmed ? 0.12 : 0.85))
                        .frame(
                            width: barWidth,
                            height: (value / maxValue) * (proxy.size.height - 40)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }
}

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        HistoryProgressView(sessions: SampleData.sessions)
    }
    .environment(Entitlements())
    .preferredColorScheme(.dark)
}
