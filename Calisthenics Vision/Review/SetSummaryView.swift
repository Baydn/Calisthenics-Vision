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
//  The count, the context and the biometrics below are all real — the last of
//  those from SessionAnalyzer, reading the telemetry already written to disk
//  every session. Nothing here is illustrative; a set with too little
//  telemetry to say anything about shows nothing rather than a guess.
//

import SwiftData
import SwiftUI

struct SetSummaryView: View {
    let session: WorkoutSession

    @Environment(\.dismiss) private var dismiss
    @Query private var allSessions: [WorkoutSession]
    @State private var showComposer = false
    @State private var openReviewAt: SeekTarget?
    /// A pass over the telemetry, so it's built once on appear rather than
    /// on every redraw.
    @State private var timelines: [AngleTimeline] = []
    /// Set once the pass has run, so "nothing to show" is only said after
    /// looking rather than during the first frame.
    @State private var didAnalyze = false

    private var analysis: SessionAnalysis? { SessionAnalyzer.analyze(session) }

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

                if let analysis, !analysis.metrics.isEmpty {
                    Text("HOW IT WENT")
                        .sectionHeaderStyle()
                        .padding(.bottom, 10)

                    metrics(analysis.metrics)
                        .padding(.bottom, 26)
                }

                // Charts stand on their own: a single-rep set has nothing to
                // compare across reps, so `analysis` is nil, but the angle it
                // moved through is still there and still worth seeing.
                if !timelines.isEmpty {
                    VStack(spacing: 14) {
                        ForEach(timelines) { timeline in
                            AngleChartCard(timeline: timeline)
                        }
                    }
                    .padding(.bottom, 26)
                }

                if let analysis, !analysis.takeaways.isEmpty {
                    Text("TAKEAWAYS")
                        .sectionHeaderStyle()
                        .padding(.bottom, 10)

                    takeaways(analysis.takeaways)
                }

                if didAnalyze, analysis == nil, timelines.isEmpty {
                    Text("Not enough recorded telemetry to say anything about this set — turn on \"Record video\" in Settings to get this next time.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .task {
            timelines = AngleTimelineBuilder.timelines(for: session)
            didAnalyze = true
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button { showComposer = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Post")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Color.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.Color.card, in: .capsule)
                }
                .buttonStyle(.plain)

                PrimaryButton(title: "Done") { dismiss() }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 22)
            .background(Theme.Color.background)
        }
        .sheet(isPresented: $showComposer) {
            PostComposerView(sessionIDs: [session.id])
        }
        // A sheet rather than a push: this screen has no NavigationStack of
        // its own (it's already presented as a sheet from Train), and
        // review is a full screen in its own right, not a drill-down.
        .sheet(item: $openReviewAt) { target in
            NavigationStack {
                SessionReviewView(session: session, initialSeekMs: target.ms)
            }
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

    private func metrics(_ items: [(label: String, value: String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.label)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.secondaryText)
                    Spacer(minLength: 8)
                    Text(item.value)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Color.primaryText)
                }
                .frame(height: 42)
                if index < items.count - 1 {
                    Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private func takeaways(_ items: [Takeaway]) -> some View {
        VStack(spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.text)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Theme.Color.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let ms = item.timestampMs {
                        Button("See that moment") { openReviewAt = SeekTarget(ms: ms) }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Color.valid)
                            .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(item.timestampMs != nil ? Theme.Color.warning : Theme.Color.valid)
                        .frame(width: 2)
                        .clipShape(.rect(cornerRadius: 1))
                }
            }
        }
    }
}

/// `Int` isn't Identifiable, and `.sheet(item:)` needs that.
private struct SeekTarget: Identifiable {
    let id = UUID()
    let ms: Int
}

#Preview {
    SetSummaryView(session: SampleSessions.make()[0])
        .modelContainer(SampleSessions.previewContainer)
}
