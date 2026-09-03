//
//  HistoryListView.swift
//  Calisthenics Vision
//
//  Sessions grouped by day under relative section headers.
//

import SwiftUI

struct HistoryListView: View {
    let sessions: [WorkoutSession]

    /// Newest first, at both levels. Days descend, and so do the sessions
    /// inside each day — the set you just finished is the first thing you see
    /// rather than the last row of the "TODAY" group.
    private var grouped: [(day: Date, sessions: [WorkoutSession])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return buckets
            .map { (day: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                ForEach(grouped, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.sectionTitle(for: group.day))
                            .sectionHeaderStyle()

                        VStack(spacing: 0) {
                            ForEach(Array(group.sessions.enumerated()), id: \.element.id) { index, session in
                                NavigationLink(value: session) {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)

                                HoldBreakdown(session: session)

                                if index < group.sessions.count - 1 {
                                    Rectangle()
                                        .fill(Theme.Color.rowSeparator)
                                        .frame(height: 1)
                                        .padding(.leading, Theme.Metric.rowIconSize + 12)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    /// "TODAY" / "YESTERDAY" / "AUG 28" — matches the Figma frame.
    static func sectionTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }
}

/// The individual holds of a set, each with its own time and line score.
///
/// A hold session's headline ("3 holds · 0:24 best") says how the set went but
/// not how each attempt went, and the attempts are the interesting part — a
/// 24s hold at 55% and a 12s hold at 90% are different kinds of good. Shown
/// inline rather than behind a tap, since the whole point is comparing them
/// at a glance.
struct HoldBreakdown: View {
    let session: WorkoutSession

    var body: some View {
        let holds = session.holdSegments
        if holds.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(holds.enumerated()), id: \.offset) { index, hold in
                        HoldPill(number: index + 1, hold: hold)
                    }
                }
                .padding(.leading, Theme.Metric.rowIconSize + 12)
                .padding(.trailing, 4)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct HoldPill: View {
    let number: Int
    let hold: HoldSegment

    var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Color.tertiaryText)

            Text(SessionResult.preciseDurationLabel(hold.duration))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Color.primaryText)

            // Straightness sits alongside the time deliberately: the two are
            // only meaningful together, since holding longer by bending more
            // isn't progress.
            Text(hold.quality.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(lineColor)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Theme.Color.card, in: .capsule)
    }

    private var lineColor: SwiftUI.Color {
        guard let quality = hold.quality else { return Theme.Color.tertiaryText }
        return quality > 0.75 ? Theme.Color.valid : Theme.Color.secondaryText
    }
}

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        HistoryListView(sessions: SampleSessions.make())
    }
    .preferredColorScheme(.dark)
}
