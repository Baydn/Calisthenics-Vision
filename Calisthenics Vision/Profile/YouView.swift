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
        case activity = "Activity"
        case calendar = "Calendar"
        case progress = "Progress"
    }

    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    @Environment(Entitlements.self) private var entitlements
    /// `.compact` is landscape on iPhone, where the header would leave the
    /// list a couple of rows tall.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var section: Section = .activity
    @State private var showPaywall = false
    @State private var settingsSection: SettingsView.Section?
    @State private var showAllAchievements = false
    #if DEBUG
    @State private var showDeveloper = false
    #endif

    private var stats: SessionStats { SessionStore.stats(for: sessions) }
    private var context: AchievementContext {
        AchievementContext(sessions: sessions, stats: stats)
    }
    private var isCompact: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.top, 8)

                Group {
                    if sessions.isEmpty {
                        emptyState
                    } else {
                        switch section {
                        case .activity: HistoryListView(sessions: sessions)
                        case .calendar: HistoryCalendarView(sessions: sessions)
                        case .progress: HistoryProgressView(sessions: sessions, stats: stats)
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
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $settingsSection) { SettingsView(section: $0) }
        .sheet(isPresented: $showAllAchievements) {
            AchievementsView(context: context)
        }
        #if DEBUG
        .sheet(isPresented: $showDeveloper) { DeveloperSettingsView() }
        #endif
    }

    // MARK: - Header

    /// Kept deliberately short. Everything here competes with the session list
    /// for the top of the screen, and the list is what the tab is for — so
    /// identity is one line, the numbers are one row, and achievements are a
    /// count you tap rather than a shelf you scroll.
    private var header: some View {
        VStack(spacing: isCompact ? 12 : 16) {
            identity

            if !isCompact { summaryRow }

            SegmentedControl(segments: Section.allCases, title: \.rawValue, selection: $section)
        }
    }

    private var identity: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.Color.card)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.Color.secondaryText)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Baydon")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)

                HStack(spacing: 6) {
                    Text(entitlements.isProUnlocked ? "PRO" : "FREE")
                        .cardLabelStyle()
                    if stats.dayStreak > 0 {
                        Text("·").cardLabelStyle()
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
            }

            Spacer(minLength: 0)

            Menu {
                Button("Feedback") { settingsSection = .feedback }
                Button("Storage") { settingsSection = .storage }
                if !entitlements.isProUnlocked {
                    Button("Upgrade to Pro") { showPaywall = true }
                }
                #if DEBUG
                Divider()
                Button("Developer") { showDeveloper = true }
                #endif
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(Theme.Color.card, in: .circle)
            }
        }
    }

    /// Three numbers, one of which is a door. Folding achievements in here
    /// removed a whole scrolling shelf from the top of the screen.
    private var summaryRow: some View {
        HStack(spacing: 8) {
            StatCard(value: "\(stats.totalSessions)", label: "SESSIONS")

            if stats.repsThisWeek == 0 && stats.holdTimeThisWeek > 0 {
                StatCard(
                    value: SessionResult.durationLabel(stats.holdTimeThisWeek),
                    label: "HELD THIS WK"
                )
            } else {
                StatCard(value: "\(stats.repsThisWeek)", label: "REPS THIS WK")
            }

            Button { showAllAchievements = true } label: {
                StatCard(
                    value: "\(Achievements.earned(in: context).count)",
                    label: "ACHIEVEMENTS ›"
                )
            }
            .buttonStyle(.plain)
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
