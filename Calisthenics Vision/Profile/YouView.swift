//
//  YouView.swift
//  Calisthenics Vision
//
//  The "You" tab: everything about your own training in one place.
//
//  History and Profile used to be separate tabs, which split one question —
//  "how am I doing?" — across two places and spent two of three tab slots on
//  it. Strava hit the same wall and merged its Profile and Training tabs for
//  the same reason. Identity, records, achievements and every session now sit
//  together, and settings move behind a gear because they're visited rarely.
//
//  The header is kept short on purpose. Everything in it competes with the
//  session list for the top of the screen, and the list is what the tab is
//  for — so identity is one line, the numbers are one row, and achievements
//  are a count you tap rather than a shelf you scroll past.
//

import SwiftData
import SwiftUI

struct YouView: View {

    enum Section: String, CaseIterable, Hashable {
        case activities = "Activities"
        case progress = "Progress"
        case workouts = "Workouts"
    }

    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    /// `.compact` is landscape on iPhone, where the header would leave the
    /// list a couple of rows tall.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var section: Section = .activities
    @State private var showSettings = false
    @State private var showProfile = false

    private var stats: SessionStats { SessionStore.stats(for: sessions) }
    private var isCompact: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.top, 8)

                Group {
                    if sessions.isEmpty && section != .workouts {
                        emptyState
                    } else {
                        switch section {
                        case .activities: HistoryListView(sessions: sessions)
                        case .progress:   HistoryProgressView(sessions: sessions, stats: stats)
                        case .workouts:   WorkoutsView()
                        }
                    }
                }
                .padding(.top, isCompact ? 12 : 20)

                Spacer(minLength: 0)
            }
            .padding(.bottom, Theme.Metric.tabBarClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.Color.background)
            .navigationDestination(for: WorkoutSession.self) { session in
                SessionReviewView(session: session)
            }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
            }
        }
        .sheet(isPresented: $showSettings) { SettingsRootView() }
    }

    // MARK: - Header

    /// A top bar rather than a profile block: avatar left into the profile,
    /// gear right into settings, and the sections immediately under it. The
    /// list is what this tab is for, and everything above it was pushing the
    /// first row toward the middle of the screen.
    private var header: some View {
        VStack(spacing: isCompact ? 10 : 14) {
            HStack(spacing: 12) {
                Button { showProfile = true } label: {
                    Circle()
                        .fill(Theme.Color.card)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")

                VStack(alignment: .leading, spacing: 1) {
                    Text("You")
                        .font(Theme.Font.header())
                        .foregroundStyle(Theme.Color.primaryText)
                    if stats.dayStreak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("\(stats.dayStreak) DAY STREAK")
                                .font(Theme.Font.cardLabel())
                                .tracking(Theme.Metric.labelTracking)
                        }
                        .foregroundStyle(Theme.Color.valid)
                    }
                }

                Spacer(minLength: 0)

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(Theme.Color.card, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            SegmentedControl(segments: Section.allCases, title: \.rawValue, selection: $section)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No sessions yet")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Color.primaryText)
            Text("Open Train and do a set — it'll show up here.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
    }
}

/// The full list, earned first so it reads as a path rather than a wall.
struct AchievementsView: View {
    let context: AchievementContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Earned by measurement, never by ticking a box — every one of these came from the same pipeline that draws the skeleton.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)

                    ForEach(Achievements.earned(in: context)) { row($0, isEarned: true) }
                    ForEach(Achievements.locked(in: context)) { row($0, isEarned: false) }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ item: Achievement, isEarned: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isEarned ? item.symbol : "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEarned ? Theme.Color.valid : Theme.Color.tertiaryText)
                .frame(width: Theme.Metric.rowIconSize, height: Theme.Metric.rowIconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(item.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        .opacity(isEarned ? 1 : 0.55)
    }
}

#Preview {
    YouView()
        .environment(Entitlements())
        .modelContainer(SampleSessions.previewContainer)
        .preferredColorScheme(.dark)
}
