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

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        HistoryListView(sessions: SampleSessions.make())
    }
    .preferredColorScheme(.dark)
}
