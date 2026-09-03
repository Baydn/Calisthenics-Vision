//
//  SetSummaryView.swift
//  Calisthenics Vision
//
//  What you see the moment a set ends.
//
//  The point is that *no* set goes unremarked. Only a handful of sets are
//  records, and an app that only celebrates those is silent almost every
//  time — so this ranks the set against your own history and says where it
//  landed: second best ever, best in six weeks, best this week.
//
//  The count and the context are real, computed from sessions already on the
//  phone with no account involved. The biometrics below them are a design
//  preview and are marked as one: the telemetry to derive them is already
//  written to disk every session, but nothing analyses it yet.
//

import SwiftData
import SwiftUI

struct SetSummaryView: View {
    let session: WorkoutSession

    @Environment(\.dismiss) private var dismiss
    @Query private var allSessions: [WorkoutSession]

    private var context: PerformanceContext {
        SessionStore.context(for: session, among: allSessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headline
                    .padding(.bottom, 14)

                contextChips
                    .padding(.bottom, 30)

                if session.movement.isTimedHold, session.holdSegments.count > 1 {
                    holds
                        .padding(.bottom, 28)
                }

                Text("HOW IT WENT")
                    .sectionHeaderStyle()
                    .padding(.bottom, 10)

                PreviewNotice(
                    "These come from telemetry that's already recorded — the analysis to derive them isn't written yet, so the figures below are illustrative."
                )
                .padding(.bottom, 12)

                metrics
                    .padding(.bottom, 26)

                Text("TAKEAWAY")
                    .sectionHeaderStyle()
                    .padding(.bottom, 10)

                takeaway
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Done") { dismiss() }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, 22)
                .background(Theme.Color.background)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SET COMPLETE")
                .sectionHeaderStyle()

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(headlineValue)
                    .font(.system(size: 56, weight: .bold, design: session.movement.isTimedHold ? .monospaced : .default))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(headlineUnit)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
    }

    private var headlineValue: String {
        session.movement.isTimedHold
            ? SessionResult.durationLabel(session.bestHold)
            : "\(session.repCount)"
    }

    private var headlineUnit: String {
        session.movement.isTimedHold
            ? "best hold · \(session.movement.displayName.lowercased())"
            : session.movement.displayName.lowercased()
    }

    @ViewBuilder
    private var contextChips: some View {
        let c = context
        if c.hasContext {
            HStack(spacing: 8) {
                if let rank = c.rankLabel {
                    chip(rank, tint: c.isPersonalBest ? Theme.Color.valid : Theme.Color.primaryText,
                         filled: c.isPersonalBest)
                }
                if let recency = c.recencyLabel {
                    chip(recency, tint: Theme.Color.valid, filled: false)
                }
                Spacer(minLength: 0)
            }
        } else {
            // A first-ever set has nothing to be ranked against, and inventing
            // a rank for it would be worse than saying so.
            Text("First one logged — this is the record to beat.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    private func chip(_ text: String, tint: SwiftUI.Color, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(filled ? Theme.Color.background : tint)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.Color.card), in: .capsule)
    }

    private var holds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOLDS")
                .sectionHeaderStyle()
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(session.holdSegments.enumerated()), id: \.offset) { index, hold in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("HOLD \(index + 1)")
                                .cardLabelStyle()
                            Text(SessionResult.preciseDurationLabel(hold.duration))
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.Color.primaryText)
                            Text(hold.quality.map { "\(Int(($0 * 100).rounded()))% line" } ?? "line —")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle((hold.quality ?? 0) > 0.75
                                                 ? Theme.Color.valid : Theme.Color.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var metrics: some View {
        VStack(spacing: 0) {
            ForEach(Array(illustrativeMetrics.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.0)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.secondaryText)
                    Spacer(minLength: 8)
                    Text(item.1)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Color.primaryText)
                }
                .frame(height: 42)
                if index < illustrativeMetrics.count - 1 {
                    Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private var illustrativeMetrics: [(String, String)] {
        session.movement.isTimedHold
            ? [("Time to stabilise", "1.2 s"),
               ("Sway", "4.1 cm"),
               ("Line decay", "−18% over the hold")]
            : [("Tempo", "1.4s ↓ / 0.9s ↑"),
               ("Depth consistency", "92%"),
               ("Left / right", "51 / 49")]
    }

    private var takeaway: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(takeawayText)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Jump to that moment")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.valid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.Color.warning)
                .frame(width: 2)
                .clipShape(.rect(cornerRadius: 1))
        }
    }

    private var takeawayText: String {
        session.movement.isTimedHold
            ? "Your line held at 84% for the first eight seconds and 61% after. The hip opened; the shoulder held."
            : "Depth held steady for 18 reps then dropped 18%. Rep 19 is where fatigue started."
    }
}

#Preview {
    SetSummaryView(session: SampleSessions.make()[0])
        .modelContainer(SampleSessions.previewContainer)
}
