//
//  ProfileView.swift
//  Calisthenics Vision
//
//  Your profile — what a follower would see, and the page a social layer
//  needs before any of it can exist.
//
//  Structured after Strava's, which carries photo and bio, follower counts,
//  this week's totals, a four-week calendar widget, recent achievements and a
//  trophy case. The parts that map onto training you can measure are here;
//  the parts that don't (gear, segments, routes) aren't.
//
//  Everything numeric is real, computed from your own sessions. The social
//  counts are the exception and are marked as such — there is nobody to
//  follow yet.
//

import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query private var workouts: [Workout]

    @State private var showAllAchievements = false
    @State private var destination: Destination?

    enum Destination: String, Identifiable, Hashable {
        case workouts, statistics, bestEfforts
        var id: String { rawValue }
    }

    private var stats: SessionStats { SessionStore.stats(for: sessions) }
    private var context: AchievementContext {
        AchievementContext(sessions: sessions, stats: stats)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                identity
                socialCounts
                thisWeek
                calendar
                explore
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAllAchievements) {
            AchievementsView(context: context)
        }
        .navigationDestination(item: $destination) { place in
            switch place {
            case .workouts:    WorkoutListView()
            case .statistics:  StatisticsView(sessions: sessions)
            case .bestEfforts: BestEffortsView(sessions: sessions)
            }
        }
    }

    // MARK: - Identity

    private var identity: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Theme.Color.card)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Color.secondaryText)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Baydon")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)

                Text(entitlements.isProUnlocked ? "PRO" : "FREE")
                    .cardLabelStyle()
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Theme.Color.card, in: .capsule)

                if let since = sessions.last?.startedAt {
                    Text("Training here since \(since.formatted(.dateTime.month(.wide).year()))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var socialCounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                countBlock("—", "FOLLOWING")
                divider
                countBlock("—", "FOLLOWERS")
                divider
                countBlock("\(stats.totalSessions)", "SESSIONS")
            }
            .padding(.vertical, 14)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))

            PreviewNotice("Following and followers need an account system, which doesn't exist yet. Sessions is real.")
        }
    }

    private func countBlock(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
            Text(label).cardLabelStyle()
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Color.rowSeparator)
            .frame(width: 1, height: 30)
    }

    // MARK: - This week

    private var thisWeek: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIS WEEK").sectionHeaderStyle()
            HStack(spacing: 8) {
                StatCard(value: "\(sessionsThisWeek)", label: "SESSIONS")
                StatCard(value: "\(stats.repsThisWeek)", label: "REPS")
                StatCard(
                    value: stats.holdTimeThisWeek > 0
                        ? SessionResult.durationLabel(stats.holdTimeThisWeek) : "—",
                    label: "HELD"
                )
            }
        }
    }

    private var sessionsThisWeek: Int {
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) else {
            return 0
        }
        return sessions.filter { $0.startedAt >= weekAgo }.count
    }

    // MARK: - Calendar

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST FOUR WEEKS").sectionHeaderStyle()
            TrainingCalendar(sessions: sessions)
        }
    }

    // MARK: - Where the detail lives

    /// Strava's profile is mostly doors: activities, statistics, best efforts,
    /// trophies. Each is a page, not a section — a profile that tries to show
    /// everything shows nothing well.
    private var explore: some View {
        VStack(spacing: 0) {
            navRow("Workouts", "\(workouts.count)", "list.bullet.rectangle") {
                destination = .workouts
            }
            separatorRow
            navRow("Statistics", "All time", "chart.bar.fill") {
                destination = .statistics
            }
            separatorRow
            navRow("Best efforts", "\(movementsTrained) movements", "trophy.fill") {
                destination = .bestEfforts
            }
            separatorRow
            navRow("Trophy case", "\(Achievements.earned(in: context).count) earned", "rosette") {
                showAllAchievements = true
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private var movementsTrained: Int {
        Set(sessions.map(\.movement)).count
    }

    private var separatorRow: some View {
        Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
    }

    private func navRow(
        _ title: String, _ value: String, _ symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer(minLength: 8)
                Text(value)
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .frame(height: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Four weeks as an actual calendar — weekday columns, real dates, a marker
/// on the days you trained.
///
/// This was a contribution-graph grid, which is a fine way to show a year and
/// a poor way to show a month: without weekday columns or dates you can't
/// tell a Tuesday from a Sunday, and "did I train on the weekend" is the
/// question people actually ask of four weeks.
struct TrainingCalendar: View {
    let sessions: [WorkoutSession]

    private struct Day: Identifiable {
        let id = UUID()
        let date: Date
        let count: Int
        let isToday: Bool
        let isFuture: Bool
    }

    private var weeks: [[Day]] {
        var cal = Calendar.current
        cal.firstWeekday = 2                       // Monday, as the labels say
        let today = cal.startOfDay(for: .now)

        let counts = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startedAt) }
            .mapValues(\.count)

        // Start on the Monday four weeks back, so rows are real weeks.
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let first = cal.date(byAdding: .weekOfYear, value: -3, to: thisWeek)
        else { return [] }

        return (0..<4).map { week in
            (0..<7).compactMap { day in
                guard let date = cal.date(byAdding: .day, value: week * 7 + day, to: first) else {
                    return nil
                }
                return Day(
                    date: date,
                    count: counts[date] ?? 0,
                    isToday: cal.isDate(date, inSameDayAs: today),
                    isFuture: date > today
                )
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(week) { day in
                        cell(day)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private func cell(_ day: Day) -> some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.system(size: 12, weight: day.isToday ? .bold : .regular, design: .rounded))
                .foregroundStyle(
                    day.isFuture ? Theme.Color.tertiaryText.opacity(0.4)
                    : (day.count > 0 ? Theme.Color.primaryText : Theme.Color.secondaryText)
                )

            // A dot per session, capped — three tells you it was a big day
            // without needing a legend to decode a shade of green.
            HStack(spacing: 2) {
                if day.count > 0 {
                    ForEach(0..<min(day.count, 3), id: \.self) { _ in
                        Circle()
                            .fill(Theme.Color.valid)
                            .frame(width: 4, height: 4)
                    }
                } else {
                    Circle().fill(.clear).frame(width: 4, height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background {
            if day.isToday {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.Color.primaryText.opacity(0.35), lineWidth: 1)
            } else if day.count > 0 {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.Color.valid.opacity(0.08))
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environment(Entitlements())
            .modelContainer(SampleSessions.previewContainer)
    }
    .preferredColorScheme(.dark)
}
