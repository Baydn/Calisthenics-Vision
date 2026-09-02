//
//  HistoryView.swift
//  Calisthenics Vision
//
//  History container: shared header + stat cards + segmented control, with
//  the List / Calendar / Progress tabs swapping below it.
//

import SwiftUI

enum HistoryTab: String, CaseIterable, Hashable {
    case list = "List"
    case calendar = "Calendar"
    case progress = "Progress"
}

struct HistoryView: View {
    @State private var tab: HistoryTab = .list
    private let sessions = SampleData.sessions

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                ScreenHeader(title: "History")

                HStack(spacing: 8) {
                    StatCard(value: "\(SampleData.dayStreak)", label: "DAY STREAK")
                    StatCard(value: "\(SampleData.repsThisWeek)", label: "REPS THIS WK")
                    StatCard(value: "\(SampleData.totalSessions)", label: "SESSIONS")
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
                switch tab {
                case .list:     HistoryListView(sessions: sessions)
                case .calendar: HistoryCalendarView(sessions: sessions)
                case .progress: HistoryProgressView(sessions: sessions)
                }
            }
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .padding(.bottom, Theme.Metric.tabBarHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Color.background)
    }
}

#Preview {
    HistoryView()
        .preferredColorScheme(.dark)
}
