//
//  HistoryView.swift
//  Calisthenics Vision
//
//  History container: shared header + stat cards + segmented control, with
//  the List / Calendar / Progress tabs swapping below it.
//

import SwiftData
import SwiftUI

enum HistoryTab: String, CaseIterable, Hashable {
    case list = "List"
    case calendar = "Calendar"
    case progress = "Progress"
}

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var tab: HistoryTab = .list

    private var stats: SessionStats { SessionStore.stats(for: sessions) }

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                ScreenHeader(title: "History")

                HStack(spacing: 8) {
                    StatCard(value: "\(stats.dayStreak)", label: "DAY STREAK")
                    StatCard(value: "\(stats.repsThisWeek)", label: "REPS THIS WK")
                    StatCard(value: "\(stats.totalSessions)", label: "SESSIONS")
                }

                SegmentedControl(
                    segments: HistoryTab.allCases,
                    title: \.rawValue,
                    selection: $tab
                )
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)

            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    switch tab {
                    case .list:     HistoryListView(sessions: sessions)
                    case .calendar: HistoryCalendarView(sessions: sessions)
                    case .progress: HistoryProgressView(sessions: sessions, stats: stats)
                    }
                }
            }
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .padding(.bottom, Theme.Metric.tabBarHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Color.background)
        .navigationDestination(for: WorkoutSession.self) { session in
            SessionReviewView(session: session)
        }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No sessions yet")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Color.primaryText)
            Text("Finish a workout on the Train tab and it'll show up here.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
    }
}

#Preview {
    HistoryView()
        .modelContainer(SampleSessions.previewContainer)
        .environment(Entitlements())
        .preferredColorScheme(.dark)
}
