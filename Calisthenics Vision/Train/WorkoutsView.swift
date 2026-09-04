//
//  WorkoutsView.swift
//  Calisthenics Vision
//
//  Saved routines — design preview.
//
//  Nothing here runs. Structured sessions are a real piece of work: a single
//  recording spanning several movements means the tracker swaps mid-take, and
//  Session Review would need per-step segmentation it doesn't have. This
//  screen exists to settle what a routine should look like before any of that
//  gets written.
//

import SwiftData
import SwiftUI

struct WorkoutsView: View {

    @Query(sort: \Workout.createdAt, order: .reverse) private var workouts: [Workout]
    @Query private var sessions: [WorkoutSession]

    @State private var showBuilder = false
    @State private var posting: Workout?

    private struct Routine {
        let name: String
        let steps: [String]
        let minutes: Int
    }

    private let routines: [Routine] = [
        Routine(
            name: "Push day",
            steps: ["Push-Up × 12", "Dip × 10", "Pike Push-Up × 8", "Plank 0:45"],
            minutes: 18
        ),
        Routine(
            name: "Pull day",
            steps: ["Pull-Up × 8", "Australian Row × 12", "Hanging Leg Raise × 10"],
            minutes: 15
        ),
        Routine(
            name: "Handstand practice",
            steps: ["Wall Sit 1:00", "Crow Stand 0:30", "Handstand × 6 attempts"],
            minutes: 22
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { showBuilder = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Group sets into a workout")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.Color.background)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Theme.Color.primaryText, in: .rect(cornerRadius: Theme.Metric.cardRadius))
                }
                .buttonStyle(.plain)

                if workouts.isEmpty {
                    Text("Nothing grouped yet. Record a few sets, then tick the ones that belong together.")
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.secondaryText)
                        .padding(.bottom, 6)
                } else {
                    ForEach(workouts) { workout in
                        NavigationLink(value: workout) { savedCard(workout) }
                            .buttonStyle(.plain)
                    }
                }

                Text("EXAMPLE ROUTINES").sectionHeaderStyle().padding(.top, 8)

                PreviewNotice(
                    "Routines can't be run yet — a set spanning several movements needs review to segment per step first. These are the shape, not the feature."
                )

                ForEach(Array(routines.enumerated()), id: \.offset) { _, routine in
                    card(routine)
                }

            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showBuilder) { WorkoutBuilderView() }
        .sheet(item: $posting) { workout in
            PostComposerView(sessionIDs: workout.sessionIDs, workoutID: workout.id)
        }
    }

    /// A workout you actually did, as opposed to the examples below it.
    private func savedCard(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer(minLength: 8)
                Text(workout.createdAt.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                    .cardLabelStyle()
            }

            Text(workout.summary(from: sessions))
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.secondaryText)

            VStack(spacing: 0) {
                ForEach(workout.sessions(from: sessions)) { session in
                    HStack(spacing: 10) {
                        DifficultyPill(level: session.movement.difficulty)
                        Text(session.movement.displayName)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Color.primaryText)
                        Spacer(minLength: 8)
                        Text(session.result.displayValue)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    .frame(height: 38)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: workout.visibility.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(workout.visibility.title.uppercased())
                    .font(Theme.Font.cardLabel())
                    .tracking(Theme.Metric.labelTracking)
                Spacer(minLength: 0)
                Text("VIEW")
                    .font(Theme.Font.cardLabel())
                    .tracking(Theme.Metric.labelTracking)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding(16)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private func card(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(routine.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer(minLength: 8)
                Text("\(routine.steps.count) STEPS · \(routine.minutes) MIN")
                    .cardLabelStyle()
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(routine.steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Color.tertiaryText)
                            .frame(width: 14, alignment: .leading)
                        Text(step)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }
}

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        WorkoutsView()
    }
    .preferredColorScheme(.dark)
}
