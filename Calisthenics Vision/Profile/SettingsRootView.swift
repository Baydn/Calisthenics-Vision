//
//  SettingsRootView.swift
//  Calisthenics Vision
//
//  The settings destination behind the gear.
//
//  Settings used to be a menu hanging off the You header, which worked while
//  there were two of them and stopped working the moment there were more. A
//  menu also can't show state — you couldn't tell whether video recording was
//  on without opening a submenu — so each row carries its current value.
//

import SwiftData
import SwiftUI

struct SettingsRootView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    @State private var settings = AppSettings.shared
    @State private var section: SettingsView.Section?
    @State private var showPaywall = false
    #if DEBUG
    @State private var showDeveloper = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !entitlements.isProUnlocked {
                        upgradeCard
                    }

                    group("TRAINING") {
                        row("Feedback", value: settings.hapticsEnabled ? "Haptics on" : "Haptics off") {
                            section = .feedback
                        }
                        separator
                        row("Storage", value: settings.recordsVideo ? "Recording video" : "Telemetry only") {
                            section = .storage
                        }
                    }

                    group("ACCOUNT") {
                        row("Plan", value: entitlements.isProUnlocked ? "Pro" : "Free") {
                            showPaywall = true
                        }
                        separator
                        // Named for what it is rather than promising a sign-in
                        // screen that doesn't exist.
                        row("Sign in", value: "Not available yet", isEnabled: false) {}
                    }

                    #if DEBUG
                    group("DEBUG") {
                        row("Developer", value: entitlements.tier.displayName, tint: Theme.Color.warning) {
                            showDeveloper = true
                        }
                    }
                    #endif

                    Text("Camera, lens and countdown are set on the Train screen — they depend on where you've put the phone, not on a preference.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $section) { SettingsView(section: $0) }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        #if DEBUG
        .sheet(isPresented: $showDeveloper) { DeveloperSettingsView() }
        #endif
    }

    // MARK: - Pieces

    private func group<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionHeaderStyle()
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        }
    }

    private var separator: some View {
        Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
    }

    private func row(
        _ title: String,
        value: String,
        tint: SwiftUI.Color = Theme.Color.primaryText,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                Text(value)
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.secondaryText)
                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .frame(height: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private var upgradeCard: some View {
        Button { showPaywall = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Upgrade to Pro")
                        .font(.system(size: 20, weight: .bold))
                    Text("Every movement, tempo analytics and long-term trends")
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Theme.Color.background.opacity(0.6))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.Color.background)
            .padding(20)
            .background(Theme.Color.primaryText, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsRootView()
        .environment(Entitlements())
        .modelContainer(SampleSessions.previewContainer)
}
