//
//  PostComposerView.swift
//  Calisthenics Vision
//
//  Publishing a set or a workout.
//
//  Recording is private; posting is the deliberate act. A post is public the
//  moment you make it — decided here, at the moment you press Post, rather
//  than in a setting you configured once and forgot.
//

import SwiftData
import SwiftUI

struct PostComposerView: View {
    /// Sets to publish. One is a single-set post; several are a workout post.
    let sessionIDs: [UUID]
    var workoutID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allSessions: [WorkoutSession]
    @State private var caption = ""

    private var sets: [WorkoutSession] {
        let ids = Set(sessionIDs)
        return allSessions.filter { ids.contains($0.id) }.sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    captionField
                    summary

                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Public — anyone can see this once posted")
                            .font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.Color.secondaryText)

                    PreviewNotice(
                        "There's no account system yet, so posts stay on this phone and nobody else can see them. The composer is real; the audience isn't."
                    )
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Color.background)
            .navigationTitle(sets.count > 1 ? "Post workout" : "Post set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { post() }
                        .disabled(sets.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTION").sectionHeaderStyle()
            TextField("Say something about it", text: $caption, axis: .vertical)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(3...6)
                .padding(14)
                .background(Theme.Color.card, in: .rect(cornerRadius: 10))
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sets.count > 1 ? "SETS IN THIS POST" : "THE SET").sectionHeaderStyle()

            VStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, session in
                    HStack(spacing: 12) {
                        DifficultyPill(level: session.movement.difficulty)
                        Text(session.movement.displayName)
                            .font(Theme.Font.body())
                            .foregroundStyle(Theme.Color.primaryText)
                        Spacer(minLength: 8)
                        Text(session.result.displayValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    .frame(height: 48)

                    if index < sets.count - 1 {
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

    private func post() {
        let entry = Post(
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionIDs: sets.map(\.id),
            workoutID: workoutID
        )
        modelContext.insert(entry)
        try? modelContext.save()
        Haptics.sessionComplete()
        dismiss()
    }
}

#Preview {
    PostComposerView(sessionIDs: SampleSessions.make().prefix(2).map(\.id))
        .modelContainer(SampleSessions.previewContainer)
}
