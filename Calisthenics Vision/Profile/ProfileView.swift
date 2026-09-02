//
//  ProfileView.swift
//  Calisthenics Vision
//
//  Frame 06 — Profile.
//

import SwiftUI

struct ProfileView: View {
    @Environment(Entitlements.self) private var entitlements
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Profile")
                    .padding(.bottom, 24)

                identityRow
                    .padding(.bottom, 28)

                if !entitlements.isProUnlocked {
                    upgradeCard
                        .padding(.bottom, 40)
                }

                settingsRows

                Button {
                    // Wired once auth lands (SPEC.md §Future Roadmap).
                } label: {
                    Text("Sign Out")
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.warning)
                }
                .buttonStyle(.plain)
                .padding(.top, 28)
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, Theme.Metric.tabBarHeight + 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .sheet(isPresented: $showPaywall) { PaywallView() }
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
                        .font(.system(size: 14, weight: .regular))
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
            settingRow("Camera Setup")
            separator
            settingRow("Units")
            separator
            settingRow("Audio Coaching", locked: !entitlements.isProUnlocked)
            separator
            settingRow("Notifications")
        }
    }

    private func settingRow(_ title: String, locked: Bool = false) -> some View {
        Button {
            if locked { showPaywall = true }
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
