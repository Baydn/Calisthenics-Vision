//
//  TrainingWeekStrip.swift
//  Calisthenics Vision
//
//  The last seven days as seven marks: trained or not, today on the right.
//
//  Why this exists at all: a streak counter says "4" and stops there. It
//  can't show that the four days sit either side of a gap, and it says
//  nothing at all the moment the streak is zero — which is exactly the
//  moment somebody needs a reason to come back. Seven marks show the shape
//  of the week instead of a single number, and the run of empty days *is*
//  the prompt.
//
//  It's deliberately not a month grid. HistoryCalendarView already draws the
//  month, and a month is a thing you go and look at; a week is a thing you
//  glance at, which is why this is small enough to live in a header and at
//  the top of a set summary.
//
//  The week is computed as a pure function of the session dates, so it's the
//  same data the Calendar dots and the streak come from and cannot disagree
//  with either.
//

import SwiftUI

/// Seven days ending today, oldest first.
struct TrainingWeek {

    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let didTrain: Bool
        let isToday: Bool
        /// Single-letter weekday, in the user's own calendar and locale.
        let initial: String
    }

    let days: [Day]

    var trainedCount: Int { days.filter(\.didTrain).count }
    var trainedToday: Bool { days.last?.didTrain ?? false }

    /// Builds the week from whatever sessions exist. Only the *dates* matter
    /// here — a day with six sets and a day with one are both "trained",
    /// because this answers "did you show up", not "how hard".
    static func make(
        from sessions: [WorkoutSession],
        calendar: Calendar = .current,
        today: Date = .now
    ) -> TrainingWeek {
        let active = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        let start = calendar.startOfDay(for: today)

        let days: [Day] = (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else {
                return nil
            }
            let weekday = calendar.component(.weekday, from: date)
            return Day(
                date: date,
                didTrain: active.contains(date),
                isToday: offset == 0,
                // Both are Sunday-based regardless of locale: the weekday
                // component numbers Sunday as 1, and the symbols array is
                // indexed from Sunday at 0. firstWeekday doesn't enter into
                // it, and shifting by it would relabel every column.
                initial: calendar.veryShortWeekdaySymbols[weekday - 1]
            )
        }
        return TrainingWeek(days: days)
    }
}

/// Seven dots with a line of plain English under them.
///
/// Green marks a day that was trained, the same green the Calendar uses for
/// the same fact — this is the one accent in the app that means "you were
/// here", and it should mean it everywhere.
struct TrainingWeekStrip: View {
    let week: TrainingWeek
    /// The streak, when the caller already knows it. Shown alongside the
    /// count because the two say different things: the count is how much of
    /// the week you used, the streak is whether it's unbroken.
    var dayStreak: Int = 0
    /// Compact drops the caption, for places that already say it in words.
    var showsCaption = true

    private var dotSize: CGFloat { 26 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(week.days) { day in
                    VStack(spacing: 6) {
                        Text(day.initial.uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(day.isToday
                                             ? Theme.Color.secondaryText
                                             : Theme.Color.tertiaryText)
                        mark(for: day)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if showsCaption { caption }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Three states, and no more: trained, today-and-not-yet, and neither.
    /// Today gets a ring rather than a fill so the empty slot reads as
    /// *waiting* instead of as missed — the day isn't over.
    @ViewBuilder
    private func mark(for day: TrainingWeek.Day) -> some View {
        if day.didTrain {
            Circle()
                .fill(Theme.Color.valid)
                .frame(width: dotSize, height: dotSize)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Color.background)
                }
        } else if day.isToday {
            Circle()
                .strokeBorder(Theme.Color.secondaryText, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: dotSize, height: dotSize)
        } else {
            Circle()
                .fill(Theme.Color.card)
                .frame(width: dotSize, height: dotSize)
        }
    }

    private var caption: some View {
        HStack(spacing: 6) {
            if dayStreak > 0 {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Color.valid)
                Text("\(dayStreak) day streak")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.valid)
                Text("·")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            Text(countText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private var countText: String {
        switch week.trainedCount {
        case 0: "Nothing in the last 7 days"
        case 7: "Every day this week"
        default: "\(week.trainedCount) of the last 7 days"
        }
    }

    private var accessibilityText: String {
        let streak = dayStreak > 0 ? "\(dayStreak) day streak. " : ""
        return "\(streak)Trained \(week.trainedCount) of the last 7 days."
    }
}

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        TrainingWeekStrip(
            week: TrainingWeek.make(from: SampleSessions.make()),
            dayStreak: 3
        )
        .padding(Theme.Metric.screenPadding)
    }
    .preferredColorScheme(.dark)
}
