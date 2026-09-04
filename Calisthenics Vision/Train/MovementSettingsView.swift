//
//  MovementSettingsView.swift
//  Calisthenics Vision
//
//  Per-set tuning, opened from the Train screen.
//
//  This is the home for settings that belong to *training* rather than to the
//  app — the things you change on the way into a set, not while poking
//  through Settings. Coaching detail and push-up depth today; as more
//  movements get trackers, their tunables belong here beside them.
//
//  Anything added here must change real behaviour. A switch that does nothing
//  implies control the app doesn't offer.
//

import SwiftUI

struct MovementSettingsView: View {
    let movement: Movement

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                coachingSection
                if movement.tunesRepDepth { pushUpSection }
                if movement.isTimedHold { holdSection }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle(movement.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var coachingSection: some View {
        Section {
            Toggle("Spoken coaching", isOn: $settings.audioCoaching)

            if settings.audioCoaching {
                Toggle("Count reps aloud", isOn: $settings.speaksReps)
                Toggle("Call out hold time", isOn: $settings.speaksHoldTime)
                Toggle("Form cues", isOn: $settings.speaksFormCues)
                Toggle("Countdown", isOn: $settings.speaksCountdown)

                Picker("Hold time every", selection: $settings.holdAnnounceInterval) {
                    Text("1s").tag(1)
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Coaching")
        } footer: {
            Text(settings.audioCoaching
                 ? "Ducks your music rather than stopping it."
                 : "The screen is hard to read from across the room, and impossible upside down. Speech carries the number.")
        }
    }

    private var pushUpSection: some View {
        Section {
            Picker("Rep depth", selection: $settings.repDepth) {
                ForEach(AppSettings.RepDepth.allCases) { depth in
                    Text(depth.title).tag(depth)
                }
            }
            .pickerStyle(.segmented)

            Text(settings.repDepth.detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.secondaryText)
        } header: {
            Text("Rep counting")
        } footer: {
            // Says out loud what POSE.md Law 3 requires, so nobody reads the
            // strict option as "the real one".
            Text("Depth is measured against your own range, not a fixed angle — so this stays fair whatever your proportions. Takes effect on your next set.")
        }
    }

    private var holdSection: some View {
        Section {
            LabeledContent("Counts as a hold", value: "1s")
            LabeledContent("Counts as a landed kick-up", value: "2s")
        } header: {
            Text("Holds")
        } footer: {
            Text("Shorter attempts are still watched — they count toward your kick-up success rate, they just aren't listed as holds.")
        }
    }
}

#Preview {
    MovementSettingsView(movement: .pushUps)
}
