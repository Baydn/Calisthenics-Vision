//
//  ProfileView.swift
//  Calisthenics Vision
//
//  Frame 06 — Profile.
//

import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(Entitlements.self) private var entitlements
    @Query private var sessions: [WorkoutSession]
    @State private var showPaywall = false
    @State private var settingsSection: SettingsView.Section?
    #if DEBUG
    @State private var showDeveloper = false
    #endif

    private var context: AchievementContext {
        AchievementContext(sessions: sessions, stats: SessionStore.stats(for: sessions))
    }

    /// Earned first, then what's next — a list of locked badges above the
    /// earned ones reads as a wall rather than a path.
    private var achievements: some View {
        let earned = Achievements.earned(in: context)
        let next = Achievements.locked(in: context).prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ACHIEVEMENTS")
                    .sectionHeaderStyle()
                Spacer()
                Text("\(earned.count) EARNED")
                    .cardLabelStyle()
            }

            if earned.isEmpty && next.isEmpty {
                Text("Record a set and these start filling in.")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.secondaryText)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(earned) { badge($0, isEarned: true) }
                        ForEach(Array(next)) { badge($0, isEarned: false) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// Every one of these was measured, never self-reported — that is what
    /// makes them worth showing at all.
    private func badge(_ item: Achievement, isEarned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: isEarned ? item.symbol : "lock.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEarned ? Theme.Color.valid : Theme.Color.tertiaryText)

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEarned ? Theme.Color.primaryText : Theme.Color.secondaryText)
                .lineLimit(1)

            Text(item.detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 132, alignment: .leading)
        .padding(14)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        .opacity(isEarned ? 1 : 0.55)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Profile")
                    .padding(.bottom, 24)

                identityRow
                    .padding(.bottom, 28)

                achievements
                    .padding(.bottom, 32)

                if !entitlements.isProUnlocked {
                    upgradeCard
                        .padding(.bottom, 40)
                }

                settingsRows

                #if DEBUG
                // Debug builds get a way into states that are otherwise hard
                // to reach — the paid tier, and a fresh install.
                Button { showDeveloper = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Developer")
                            .font(.system(size: 17, weight: .regular))
                        Spacer()
                        Text(entitlements.tier.displayName.uppercased())
                            .font(Theme.Font.cardLabel())
                            .tracking(Theme.Metric.labelTracking)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    .foregroundStyle(Theme.Color.warning)
                    .frame(height: 56)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                #endif

                // Sign Out returns with authentication (SPEC.md §Future
                // Roadmap). Until there's an account to sign out of, a button
                // that does nothing is worse than no button.
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, Theme.Metric.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $settingsSection) { SettingsView(section: $0) }
        #if DEBUG
        .sheet(isPresented: $showDeveloper) { DeveloperSettingsView() }
        #endif
    }

    // MARK: - Pieces

    private var identityRow: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Theme.Color.card)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.Color.secondaryText)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Alex")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)

                Text(entitlements.isProUnlocked ? "PRO PLAN" : "FREE PLAN")
                    .font(Theme.Font.cardLabel())
                    .tracking(Theme.Metric.labelTracking)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Theme.Color.card, in: .capsule)
            }
        }
    }

    private var upgradeCard: some View {
        Button { showPaywall = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Upgrade to Pro")
                        .font(.system(size: 20, weight: .bold))
                    Text("Planche, pull-ups, tempo analytics & more")
                        .font(.system(size: 13, weight: .regular))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Theme.Color.background.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.Color.background)
            .padding(24)
            .background(Theme.Color.primaryText, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var settingsRows: some View {
        VStack(spacing: 0) {
            settingRow("Camera Setup") { settingsSection = .camera }
            separator
            settingRow("Feedback") { settingsSection = .feedback }
            separator
            settingRow("Storage") { settingsSection = .storage }
        }
    }

    private func settingRow(
        _ title: String,
        locked: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button {
            if locked { showPaywall = true } else { action() }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(locked ? Theme.Color.tertiaryText : Theme.Color.primaryText)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Color.tertiaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .frame(height: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Color.rowSeparator)
            .frame(height: 1)
    }
}

#Preview {
    ProfileView()
        .environment(Entitlements())
        .preferredColorScheme(.dark)
}
