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

    @State private var showAllAchievements = false

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
                bestEfforts
                calendar
                trophies
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

    // MARK: - Best efforts

    /// Strava's "best efforts", in the units this app measures. One line per
    /// movement you've actually done, so the list grows with you rather than
    /// showing dashes for forty movements you've never tried.
    private var bestEfforts: some View {
        let done = Movement.allCases.filter { movement in
            sessions.contains { $0.movement == movement }
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text("BEST EFFORTS").sectionHeaderStyle()

            if done.isEmpty {
                Text("Record a set and your records show up here.")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(done.enumerated()), id: \.element.id) { index, movement in
                        let mine = sessions.filter { $0.movement == movement }
                        HStack(spacing: 12) {
                            DifficultyPill(level: movement.difficulty)
                            Text(movement.displayName)
                                .font(Theme.Font.body())
                                .foregroundStyle(Theme.Color.primaryText)
                            Spacer(minLength: 8)
                            Text(bestLabel(for: movement, in: mine))
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Color.primaryText)
                        }
                        .frame(height: 48)

                        if index < done.count - 1 {
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
    }

    private func bestLabel(for movement: Movement, in mine: [WorkoutSession]) -> String {
        movement.isTimedHold
            ? SessionResult.durationLabel(mine.map(\.bestHold).max() ?? 0)
            : "\(mine.map(\.repCount).max() ?? 0) reps"
    }

    // MARK: - Calendar

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST FOUR WEEKS").sectionHeaderStyle()
            TrainingHeatmap(sessions: sessions)
        }
    }

    // MARK: - Trophies

    private var trophies: some View {
        let earned = Achievements.earned(in: context)

        return VStack(alignment: .leading, spacing: 10) {
            Button { showAllAchievements = true } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("TROPHY CASE").sectionHeaderStyle()
                    Spacer()
                    Text("\(earned.count) EARNED").cardLabelStyle()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if earned.isEmpty {
                Text("Nothing yet — the first one lands after your first set.")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.secondaryText)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(earned) { item in
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.Color.valid)
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.Color.primaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
                    }
                }
            }
        }
    }
}

/// Four weeks of training at a glance — one square per day, brighter the more
/// you did. Strava puts this on the profile for the same reason: consistency
/// is the thing you actually want to see about yourself.
struct TrainingHeatmap: View {
    let sessions: [WorkoutSession]

    private var days: [(date: Date, intensity: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let counts = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startedAt) }
            .mapValues(\.count)
        let busiest = max(counts.values.max() ?? 1, 1)

        return (0..<28).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = counts[date] ?? 0
            return (date, Double(count) / Double(busiest))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(days, id: \.date) { day in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(day.intensity > 0
                              ? Theme.Color.valid.opacity(0.25 + 0.75 * day.intensity)
                              : Theme.Color.card)
                        .aspectRatio(1, contentMode: .fit)
                }
            }

            HStack(spacing: 6) {
                Text("LESS").cardLabelStyle()
                ForEach([0.0, 0.35, 0.7, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(level > 0
                              ? Theme.Color.valid.opacity(0.25 + 0.75 * level)
                              : Theme.Color.card)
                        .frame(width: 12, height: 12)
                }
                Text("MORE").cardLabelStyle()
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(Theme.Color.card.opacity(0.45), in: .rect(cornerRadius: Theme.Metric.cardRadius))
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
