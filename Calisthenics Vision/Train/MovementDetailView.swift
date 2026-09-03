//
//  MovementDetailView.swift
//  Calisthenics Vision
//
//  One movement: what it is, how you're doing at it, and what's next.
//
//  The records are real — computed from your sessions. The progression ladder
//  is a design preview and says so: the levels are drawn from what the camera
//  *could* check, but nothing evaluates them yet, and a screen that looked
//  finished while doing nothing would be worse than no screen.
//

import SwiftData
import SwiftUI

struct MovementDetailView: View {
    let movement: Movement
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [WorkoutSession]

    private var mine: [WorkoutSession] {
        sessions.filter { $0.movement == movement }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 24)

                records
                    .padding(.bottom, 28)

                if !movement.isTrackingSupported {
                    notTrackedNotice
                        .padding(.bottom, 28)
                }

                Text("PROGRESSION")
                    .sectionHeaderStyle()
                    .padding(.bottom, 10)

                PreviewNotice(
                    "Levels are designed, not wired up. Nothing here is evaluated against your sessions yet."
                )
                .padding(.bottom, 12)

                ladder

                Text("Every level is checked against what the camera measured — nothing here is ever ticked by hand.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .padding(.top, 14)
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Train this") { onSelect() }
                    .disabled(!movement.isTrackingSupported)
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            DifficultyPill(level: movement.difficulty)
                .scaleEffect(1.45)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(movement.displayName)
                    .font(Theme.Font.header())
                    .foregroundStyle(Theme.Color.primaryText)
                Text("\(movement.category.displayName.uppercased()) · \(movement.tier.uppercased()) · \(movement.equipment.displayName.uppercased())")
                    .cardLabelStyle()
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var records: some View {
        if mine.isEmpty {
            HStack(spacing: 8) {
                StatCard(value: "—", label: "NO SESSIONS YET")
            }
        } else if movement.isTimedHold {
            HStack(spacing: 8) {
                StatCard(
                    value: SessionResult.durationLabel(mine.map(\.bestHold).max() ?? 0),
                    label: "LONGEST HOLD"
                )
                StatCard(value: "\(mine.flatMap(\.holdSegments).count)", label: "HOLDS LOGGED")
                StatCard(value: "\(mine.count)", label: "SESSIONS")
            }
        } else {
            HStack(spacing: 8) {
                StatCard(value: "\(mine.map(\.repCount).max() ?? 0)", label: "BEST SET")
                StatCard(
                    value: "\(mine.reduce(0) { $0 + $1.repCount })",
                    label: "TOTAL REPS"
                )
                StatCard(value: "\(mine.count)", label: "SESSIONS")
            }
        }
    }

    private var notTrackedNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not tracked yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)
            Text("You can still record a set — it just won't be counted or scored. \(movement.displayName) needs its own state machine before the camera can judge it.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private var ladder: some View {
        VStack(spacing: 8) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: level.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(level.tint)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(level.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Color.primaryText)
                        Text(level.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(level.tint)
                        .frame(width: 2)
                        .clipShape(.rect(cornerRadius: 1))
                }
                .opacity(level.isLocked ? 0.55 : 1)
            }
        }
    }

    private struct Level {
        let title: String
        let detail: String
        let symbol: String
        let tint: SwiftUI.Color
        var isLocked = false
    }

    /// Criteria are written the way they'd have to be checked: a number the
    /// camera already produces, not "good form".
    private var levels: [Level] {
        if movement.isTimedHold {
            return [
                Level(title: "Hold 5 seconds", detail: "Any line quality — getting up is the skill here",
                      symbol: "checkmark.circle.fill", tint: Theme.Color.valid),
                Level(title: "Hold 15 seconds", detail: "Line above 60% for the whole attempt",
                      symbol: "circle.dashed", tint: Theme.Color.warning),
                Level(title: "Hold 30 seconds", detail: "Line above 70%, three sessions running",
                      symbol: "lock.fill", tint: Theme.Color.tertiaryText, isLocked: true),
                Level(title: "Hold 60 seconds", detail: "Line above 80% — competition standard",
                      symbol: "lock.fill", tint: Theme.Color.tertiaryText, isLocked: true),
            ]
        }
        return [
            Level(title: "5 clean reps", detail: "Full range, no form breaks",
                  symbol: "checkmark.circle.fill", tint: Theme.Color.valid),
            Level(title: "12 in a set", detail: "Depth consistency above 85%",
                  symbol: "circle.dashed", tint: Theme.Color.warning),
            Level(title: "25 in a set", detail: "No form break in the last five reps",
                  symbol: "lock.fill", tint: Theme.Color.tertiaryText, isLocked: true),
            Level(title: "Move to the harder variation", detail: "Unlocks the next movement in this line",
                  symbol: "lock.fill", tint: Theme.Color.tertiaryText, isLocked: true),
        ]
    }
}

#Preview {
    NavigationStack {
        MovementDetailView(movement: .handstand) {}
            .modelContainer(SampleSessions.previewContainer)
    }
    .preferredColorScheme(.dark)
}
