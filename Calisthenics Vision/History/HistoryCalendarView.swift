//
//  HistoryCalendarView.swift
//  Calisthenics Vision
//
//  Month grid with a dot under each day that has a logged session, and the
//  selected day's sessions listed beneath.
//

import SwiftUI

struct HistoryCalendarView: View {
    let sessions: [WorkoutSession]

    @State private var visibleMonth: Date = Date()
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    /// Days in the visible month that have at least one session.
    private var activeDays: Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
    }

    private var sessionsOnSelectedDay: [WorkoutSession] {
        sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: selectedDay) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                monthHeader
                    .padding(.bottom, 20)

                weekdayHeader
                    .padding(.bottom, 8)

                monthGrid

                if !sessionsOnSelectedDay.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedDay.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                            .sectionHeaderStyle()

                        VStack(spacing: 0) {
                            ForEach(Array(sessionsOnSelectedDay.enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session)

                                if index < sessionsOnSelectedDay.count - 1 {
                                    Rectangle()
                                        .fill(Theme.Color.rowSeparator)
                                        .frame(height: 1)
                                        .padding(.leading, Theme.Metric.rowIconSize + 12)
                                }
                            }
                        }
                    }
                    .padding(.top, 28)
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Pieces

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            Spacer()

            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Color.primaryText)

            Spacer()

            Button { shiftMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(calendar.veryShortStandaloneWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(Theme.Font.sectionHeader())
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let hasSession = activeDays.contains(calendar.startOfDay(for: day))

        return VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Theme.Color.background : Theme.Color.primaryText)
                .frame(width: 32, height: 32)
                .background {
                    if isSelected { Circle().fill(Theme.Color.primaryText) }
                }

            Circle()
                .fill(hasSession ? Theme.Color.valid : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { selectedDay = calendar.startOfDay(for: day) }
    }

    // MARK: - Date math

    /// Day cells for the visible month, padded with `nil` so the 1st lands on
    /// the correct weekday column.
    private var monthCells: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count
        else { return [] }

        let leadingBlanks = calendar.component(.weekday, from: interval.start) - calendar.firstWeekday
        let padding = (leadingBlanks + 7) % 7

        let days: [Date?] = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Array(repeating: nil, count: padding) + days
    }

    private func shiftMonth(by value: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        withAnimation(.snappy(duration: 0.2)) { visibleMonth = shifted }
    }
}

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        HistoryCalendarView(sessions: SampleSessions.make())
    }
    .preferredColorScheme(.dark)
}
