//
//  SettingsView.swift
//  Calisthenics Vision
//
//  Camera, feedback, and storage preferences reached from Profile.
//

import AVFoundation
import SwiftData
import SwiftUI

struct SettingsView: View {

    enum Section: String, Identifiable {
        // Camera setup lives on the Train screen, not here: which camera,
        // which lens and how long the countdown runs are decided by where
        // you've just propped the phone, not once in a settings screen.
        case feedback = "Feedback"
        case storage = "Storage"

        var id: String { rawValue }
    }

    let section: Section

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Entitlements.self) private var entitlements

    @State private var settings = AppSettings.shared
    @State private var storageSize = MediaLibrary.formattedTotalSize()
    @State private var confirmPurge = false

    @Query private var sessions: [WorkoutSession]

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    switch section {
                    case .feedback: feedbackSection
                    case .storage:  storageSection
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Delete all recordings?",
            isPresented: $confirmPurge,
            titleVisibility: .visible
        ) {
            Button("Delete Recordings", role: .destructive) { purgeVideos() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your sessions, rep counts and telemetry are kept — only the video files are removed.")
        }
    }

    private var header: some View {
        HStack {
            Text(section.rawValue)
                .font(Theme.Font.header())
                .foregroundStyle(Theme.Color.primaryText)
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)
        }
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackSection: some View {
        @Bindable var settings = settings

        toggleRow(
            "Haptics",
            note: "A tap per rep, a pulse per second of a hold, and a warning pattern on a form break.",
            isOn: $settings.hapticsEnabled
        )

        toggleRow(
            "Keep screen awake while training",
            note: "Stops the display dimming mid-set. Turning this off will let the screen sleep during a workout.",
            isOn: $settings.keepsScreenAwake
        )

        label("AUDIO COACHING")
        HStack {
            Text(settings.audioCoaching ? "On" : "Off")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.secondaryText)
            Spacer()
            Image(systemName: settings.audioCoaching
                  ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .frame(height: 44)
        caption("Spoken rep counts, hold time and form cues. Toggled on the Train screen, where you decide it — and where you can turn it off the moment someone walks in.")
    }

    // MARK: - Storage

    @ViewBuilder
    private var storageSection: some View {
        @Bindable var settings = settings

        toggleRow(
            "Record video",
            note: "Off saves telemetry only — a few hundred KB per set instead of roughly 150 MB per ten minutes. Session Review needs video to play anything back.",
            isOn: $settings.recordsVideo
        )

        infoRow("Sessions", "\(sessions.count)")
        infoRow("Recordings and telemetry", storageSize)
        caption("Video dominates this. A ten-minute set is roughly 150 MB, while its telemetry is under a megabyte.")

        label("RETENTION")
        infoRow(
            "History kept",
            entitlements.historyWindowDays.map { "\($0) days" } ?? "Unlimited"
        )
        caption(entitlements.isProUnlocked
                ? "Pro keeps every session."
                : "Free keeps a rolling 7-day window. Older sessions and their recordings are removed automatically at launch.")

        Button {
            confirmPurge = true
        } label: {
            Text("Delete All Recordings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        caption("Frees space while keeping your history. Reviewed sessions will show their stats but won't play back.")
    }

    /// Removes video files but keeps the sessions and their telemetry.
    private func purgeVideos() {
        for session in sessions {
            if let url = session.videoURL {
                try? FileManager.default.removeItem(at: url)
                session.videoFileName = nil
            }
        }
        try? modelContext.save()
        storageSize = MediaLibrary.formattedTotalSize()
    }

    // MARK: - Building blocks

    private func toggleRow(_ title: String, note: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.Color.primaryText)
            }
            .tint(Theme.Color.valid)
            .frame(minHeight: 44)

            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 22)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .sectionHeaderStyle()
            .padding(.top, 6)
            .padding(.bottom, 10)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.Color.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .padding(.bottom, 22)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .frame(height: 44)
    }
}

#Preview {
    SettingsView(section: .feedback)
        .environment(Entitlements())
        .modelContainer(SampleSessions.previewContainer)
}
