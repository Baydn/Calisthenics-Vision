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
    /// `.compact` is landscape on iPhone: the stat cards are a nice-to-have,
    /// and keeping them there would leave the list a couple of rows tall.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var stats: SessionStats { SessionStore.stats(for: sessions) }

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            VStack(spacing: verticalSizeClass == .compact ? 12 : 18) {
                ScreenHeader(title: "History")

                if verticalSizeClass != .compact {
                    HStack(spacing: 8) {
                        StatCard(value: "\(stats.dayStreak)", label: "DAY STREAK")
                        // Falls back to hold time when the week has no reps
                        // in it: a week of nothing but handstands used to
                        // show a headline zero.
                        if stats.repsThisWeek == 0 && stats.holdTimeThisWeek > 0 {
                            StatCard(
                                value: SessionResult.durationLabel(stats.holdTimeThisWeek),
                                label: "HELD THIS WK"
                            )
                        } else {
                            StatCard(value: "\(stats.repsThisWeek)", label: "REPS THIS WK")
                        }
                        StatCard(value: "\(stats.totalSessions)", label: "SESSIONS")
                    }
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
            .padding(.top, verticalSizeClass == .compact ? 12 : 22)

            Spacer(minLength: 0)
        }
        .padding(.bottom, Theme.Metric.tabBarClearance)
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
