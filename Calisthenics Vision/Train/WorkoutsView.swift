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

import SwiftUI

struct WorkoutsView: View {

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
                PreviewNotice(
                    "Routines can't be run yet — a set spanning several movements needs review to segment per step first. This is the shape, not the feature."
                )

                ForEach(Array(routines.enumerated()), id: \.offset) { _, routine in
                    card(routine)
                }

                Button {} label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Build a routine")
                            .font(Theme.Font.control())
                    }
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                            .strokeBorder(
                                Theme.Color.divider,
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
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
