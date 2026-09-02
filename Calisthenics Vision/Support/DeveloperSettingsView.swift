//
//  DeveloperSettingsView.swift
//  Calisthenics Vision
//
//  Debug-only panel for exercising states that are otherwise hard to reach:
//  the paid tier, and a first-launch install.
//
//  Compiled out of release builds entirely — this is a testing shim, not a
//  hidden feature, and it must never be reachable by a real user.
//

#if DEBUG

import SwiftData
import SwiftUI

struct DeveloperSettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.modelContext) private var modelContext

    @Query private var sessions: [WorkoutSession]

    @State private var confirmReset = false
    @State private var lastAction: String?

    var body: some View {
        @Bindable var entitlements = entitlements

        ZStack {
            Theme.Color.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    section("SUBSCRIPTION TIER")
                    Picker("Tier", selection: $entitlements.tier) {
                        ForEach(Entitlements.Tier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 8)

                    caption(entitlements.isProUnlocked
                            ? "All movements unlocked, unlimited history, progression chart visible."
                            : "Push-ups and handstands only, 7-day history, progression chart locked.")
                    caption("Persists across launches in debug builds, so you don't have to re-unlock every relaunch.")

                    section("STATE")
                    infoRow("Saved sessions", "\(sessions.count)")
                    infoRow("Media on disk", MediaLibrary.formattedTotalSize())

                    section("ACTIONS")

                    actionButton("Simulate New User", role: .destructive) {
                        confirmReset = true
                    }
                    caption("Deletes every session and its media, and returns you to the Free tier — the same state as a fresh install.")

                    actionButton("Load Sample Sessions") {
                        SampleSessions.seedIfEmpty(modelContext)
                        lastAction = "Sample sessions loaded (only if the store was empty)."
                    }
                    caption("Populates History with the mock set, for checking layout without recording anything.")

                    actionButton("Prune Expired Sessions") {
                        let removed = SessionStore.pruneExpired(
                            windowDays: entitlements.historyWindowDays,
                            context: modelContext
                        )
                        lastAction = "Pruned \(removed) session\(removed == 1 ? "" : "s") outside the tier window."
                    }
                    caption("Runs the retention rule on demand — normally this only happens at launch.")

                    if let lastAction {
                        Text(lastAction)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Color.valid)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Simulate a new user?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                let removed = SessionStore.deleteAll(context: modelContext)
                entitlements.resetToNewUser()
                lastAction = "Deleted \(removed) session\(removed == 1 ? "" : "s"). Now on the Free tier."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every recorded session, video, and telemetry file will be deleted. This can't be undone.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer")
                    .font(Theme.Font.header())
                    .foregroundStyle(Theme.Color.primaryText)
                Text("Debug builds only")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.warning)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .sectionHeaderStyle()
            .padding(.top, 28)
            .padding(.bottom, 10)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Theme.Color.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .frame(height: 40)
    }

    private func actionButton(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(role == .destructive
                                 ? Theme.Color.warning : Theme.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DeveloperSettingsView()
        .environment(Entitlements())
        .modelContainer(SampleSessions.previewContainer)
}

#endif
