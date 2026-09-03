//
//  ProfileDetailViews.swift
//  Calisthenics Vision
//
//  The pages behind the profile's rows: workouts, statistics, best efforts.
//
//  Strava's profile is mostly doors rather than content, and it's right to be:
//  a profile that tries to show everything shows nothing well. Each of these
//  answers one question properly instead of contributing a cramped section to
//  a scroll nobody reaches the bottom of.
//

import SwiftData
import SwiftUI

// MARK: - Workouts

struct WorkoutListView: View {
    @Query(sort: \Workout.createdAt, order: .reverse) private var workouts: [Workout]
    @Query private var sessions: [WorkoutSession]

    @State private var showBuilder = false
    @State private var posting: Workout?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if workouts.isEmpty {
                    empty
                } else {
                    ForEach(workouts) { workout in
                        card(workout)
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showBuilder = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showBuilder) { WorkoutBuilderView() }
        .sheet(item: $posting) { workout in
            PostComposerView(sessionIDs: workout.sessionIDs, workoutID: workout.id)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No workouts yet")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Color.primaryText)
            Text("Record a few sets, then group the ones that belong together.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding(.vertical, 40)
    }

    private func card(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer(minLength: 8)
                Text(workout.createdAt.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                    .cardLabelStyle()
            }

            Text(workout.summary(from: sessions))
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.secondaryText)

            if !workout.notes.isEmpty {
                Text(workout.notes)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(workout.sessions(from: sessions)) { session in
                    HStack(spacing: 10) {
                        DifficultyPill(level: session.movement.difficulty)
                        Text(session.movement.displayName)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Color.primaryText)
                        Spacer(minLength: 8)
                        Text(session.result.displayValue)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    .frame(height: 38)
                }
            }

            Button { posting = workout } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Post this workout")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.Color.valid)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
            }
        }
        .padding(16)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }
}

// MARK: - Statistics

struct StatisticsView: View {
    let sessions: [WorkoutSession]

    private var stats: SessionStats { SessionStore.stats(for: sessions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                block("LAST 4 WEEKS", rows: fourWeekRows)
                block("THIS YEAR", rows: yearRows)
                block("ALL TIME", rows: allTimeRows)

                Text("Hold figures use the best single attempt in each session, never the set total — six five-second handstands are not a thirty-second handstand.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.large)
    }

    private func within(_ days: Int) -> [WorkoutSession] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else {
            return sessions
        }
        return sessions.filter { $0.startedAt >= cutoff }
    }

    private var fourWeekRows: [(String, String)] {
        let window = within(28)
        let weeks = 4.0
        return [
            ("Sessions", "\(window.count)"),
            ("Per week", String(format: "%.1f", Double(window.count) / weeks)),
            ("Reps", "\(window.reduce(0) { $0 + $1.repCount })"),
            ("Time held", SessionResult.durationLabel(heldTime(in: window))),
        ]
    }

    private var yearRows: [(String, String)] {
        let year = Calendar.current.component(.year, from: .now)
        let window = sessions.filter {
            Calendar.current.component(.year, from: $0.startedAt) == year
        }
        return [
            ("Sessions", "\(window.count)"),
            ("Reps", "\(window.reduce(0) { $0 + $1.repCount })"),
            ("Time held", SessionResult.durationLabel(heldTime(in: window))),
            ("Movements", "\(Set(window.map(\.movement)).count)"),
        ]
    }

    private var allTimeRows: [(String, String)] {
        [
            ("Sessions", "\(sessions.count)"),
            ("Reps", "\(stats.totalReps)"),
            ("Time held", SessionResult.durationLabel(heldTime(in: sessions))),
            ("Longest hold", stats.longestHold > 0
                ? SessionResult.durationLabel(stats.longestHold) : "—"),
            ("Best day streak", "\(stats.dayStreak)"),
            ("Movements tried", "\(Set(sessions.map(\.movement)).count) of \(Movement.allCases.count)"),
        ]
    }

    private func heldTime(in window: [WorkoutSession]) -> TimeInterval {
        window.filter { $0.movement.isTimedHold }.reduce(0) { $0 + $1.duration }
    }

    private func block(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeaderStyle()
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(row.0)
                            .font(Theme.Font.body())
                            .foregroundStyle(Theme.Color.secondaryText)
                        Spacer(minLength: 8)
                        Text(row.1)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Color.primaryText)
                    }
                    .frame(height: 46)

                    if index < rows.count - 1 {
                        Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        }
    }
}

// MARK: - Best efforts

struct BestEffortsView: View {
    let sessions: [WorkoutSession]

    private var trained: [Movement] {
        Movement.allCases
            .filter { movement in sessions.contains { $0.movement == movement } }
            .sorted { ($0.difficulty, $0.displayName) > ($1.difficulty, $1.displayName) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if trained.isEmpty {
                    Text("Record a set and your records show up here.")
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.secondaryText)
                        .padding(.vertical, 40)
                } else {
                    ForEach(MovementCategory.allCases) { category in
                        let items = trained.filter { $0.category == category }
                        if !items.isEmpty { section(category, items) }
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .navigationTitle("Best efforts")
        .navigationBarTitleDisplayMode(.large)
    }

    private func section(_ category: MovementCategory, _ items: [Movement]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.displayName.uppercased()).sectionHeaderStyle()

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, movement in
                    let mine = sessions.filter { $0.movement == movement }
                    HStack(spacing: 12) {
                        DifficultyPill(level: movement.difficulty)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(movement.displayName)
                                .font(Theme.Font.body())
                                .foregroundStyle(Theme.Color.primaryText)
                            Text("\(mine.count) session\(mine.count == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Color.tertiaryText)
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(best(movement, mine))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.Color.primaryText)
                            if let when = mine.max(by: { $0.startedAt < $1.startedAt })?.startedAt {
                                Text(when.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Color.tertiaryText)
                            }
                        }
                    }
                    .frame(height: 56)

                    if index < items.count - 1 {
                        Rectangle()
                            .fill(Theme.Color.rowSeparator)
                            .frame(height: 1)
                            .padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        }
    }

    private func best(_ movement: Movement, _ mine: [WorkoutSession]) -> String {
        movement.isTimedHold
            ? SessionResult.durationLabel(mine.map(\.bestHold).max() ?? 0)
            : "\(mine.map(\.repCount).max() ?? 0)"
    }
}

// MARK: - Who liked it

/// People you follow first, then everyone else with a Follow button — the
/// order that makes the list worth opening, since recognising a name is the
/// whole reason you tapped.
struct LikesView: View {
    let count: Int

    @Environment(\.dismiss) private var dismiss
    @State private var followed: Set<String> = []

    private var following: [(String, String)] {
        [("mila.calis", "Front lever · straddle"), ("jonas_b", "19 pull-ups")]
    }

    private var others: [(String, String)] {
        [
            ("rina.hs", "2:41 handstand"),
            ("dmitri_v", "Planche progression"),
            ("ana.flags", "Human flag · 0:11"),
            ("sam.calis", "Muscle-up × 6"),
        ]
    }

    var body: some View {
        SheetScaffold(title: "\(count) likes") {
            VStack(alignment: .leading, spacing: 22) {
                PreviewNotice("Accounts don't exist yet, so these people are invented and Follow does nothing.")

                group("PEOPLE YOU FOLLOW", following, showsFollow: false)
                group("EVERYONE ELSE", others, showsFollow: true)
            }
        }
    }

    private func group(
        _ title: String, _ people: [(String, String)], showsFollow: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionHeaderStyle()

            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.offset) { index, person in
                    HStack(spacing: 12) {
                        Text(String(person.0.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Color.primaryText)
                            .frame(width: 34, height: 34)
                            .background(Theme.Color.elevated, in: .circle)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.0)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.Color.primaryText)
                            Text(person.1)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Color.secondaryText)
                        }

                        Spacer(minLength: 8)

                        if showsFollow {
                            let isFollowed = followed.contains(person.0)
                            Button {
                                withAnimation(Theme.Motion.content) {
                                    if isFollowed { followed.remove(person.0) }
                                    else { followed.insert(person.0) }
                                }
                            } label: {
                                Text(isFollowed ? "Following" : "Follow")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isFollowed
                                                     ? Theme.Color.primaryText : Theme.Color.background)
                                    .padding(.horizontal, 14)
                                    .frame(height: 30)
                                    .background(
                                        isFollowed
                                            ? AnyShapeStyle(Theme.Color.elevated)
                                            : AnyShapeStyle(Theme.Color.primaryText),
                                        in: .capsule
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: 58)

                    if index < people.count - 1 {
                        Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        }
    }
}

#Preview {
    NavigationStack {
        StatisticsView(sessions: SampleSessions.make())
    }
    .preferredColorScheme(.dark)
}
