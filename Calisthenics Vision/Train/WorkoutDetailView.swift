//
//  WorkoutDetailView.swift
//  Calisthenics Vision
//
//  One workout, in full.
//
//  A card in a list can only say what happened. This says how it went: per
//  movement rather than per set, because "how many push-ups did I do" is the
//  question people actually ask, and a flat list of sets makes you add them
//  up yourself.
//
//  Every set stays reachable underneath — tapping one opens the recording,
//  which is still the primary artefact.
//

import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout

    @Environment(\.modelContext) private var modelContext
    @Query private var allSessions: [WorkoutSession]

    @State private var posting = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    private var sets: [WorkoutSession] { workout.sessions(from: allSessions) }
    private var breakdown: [(movement: Movement, sets: [WorkoutSession])] {
        workout.breakdown(from: allSessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                totals
                movements
                sessionList
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Color.background)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { posting = true } label: {
                        Label("Post this workout", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $posting) {
            PostComposerView(sessionIDs: workout.sessionIDs, workoutID: workout.id)
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(workout)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Worth saying plainly: the recordings are the real thing, and a
            // grouping is only a view over them.
            Text("The sets themselves are kept — only the grouping is removed.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(workout.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .cardLabelStyle()
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: workout.visibility.symbol)
                        .font(.system(size: 10, weight: .semibold))
                    Text(workout.visibility.title.uppercased())
                        .font(Theme.Font.cardLabel())
                        .tracking(Theme.Metric.labelTracking)
                }
                .foregroundStyle(Theme.Color.secondaryText)
            }

            if !workout.notes.isEmpty {
                Text(workout.notes)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }

    private var totals: some View {
        HStack(spacing: 8) {
            StatCard(value: "\(sets.count)", label: "SETS")
            StatCard(value: "\(breakdown.count)", label: "MOVEMENTS")
            StatCard(
                value: SessionResult.durationLabel(workout.elapsed(from: allSessions)),
                label: "ELAPSED"
            )
        }
    }

    // MARK: - Per movement

    private var movements: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BY MOVEMENT").sectionHeaderStyle()

            VStack(spacing: 10) {
                ForEach(Array(breakdown.enumerated()), id: \.offset) { _, entry in
                    movementCard(entry.movement, entry.sets)
                }
            }
        }
    }

    private func movementCard(_ movement: Movement, _ sets: [WorkoutSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DifficultyPill(level: movement.difficulty)
                Text(movement.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer(minLength: 8)
                Text("\(sets.count) SET\(sets.count == 1 ? "" : "S")")
                    .cardLabelStyle()
            }

            HStack(spacing: 8) {
                ForEach(stats(for: movement, sets), id: \.0) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.1)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Color.primaryText)
                        Text(line.0).cardLabelStyle()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Per set, so a fade across the workout is visible rather than
            // averaged away.
            HStack(spacing: 4) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, session in
                    VStack(spacing: 3) {
                        Text(setValue(movement, session))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.Color.elevated.opacity(0.6), in: .rect(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }

    private func stats(for movement: Movement, _ sets: [WorkoutSession]) -> [(String, String)] {
        if movement.isTimedHold {
            let holds = sets.flatMap(\.holdSegments)
            let best = sets.map(\.bestHold).max() ?? 0
            let total = sets.reduce(0) { $0 + $1.duration }
            let line = sets.compactMap(\.formQuality)
            return [
                ("BEST HOLD", SessionResult.durationLabel(best)),
                ("TOTAL HELD", SessionResult.durationLabel(total)),
                ("HOLDS", "\(holds.count)"),
                ("LINE", line.isEmpty
                    ? "—"
                    : "\(Int((line.reduce(0, +) / Double(line.count) * 100).rounded()))%"),
            ]
        }
        let reps = sets.reduce(0) { $0 + $1.repCount }
        let best = sets.map(\.repCount).max() ?? 0
        let breaks = sets.reduce(0) { $0 + $1.formBreaks }
        return [
            ("TOTAL REPS", "\(reps)"),
            ("BEST SET", "\(best)"),
            ("AVERAGE", sets.isEmpty ? "0" : "\(reps / sets.count)"),
            ("FORM BREAKS", "\(breaks)"),
        ]
    }

    private func setValue(_ movement: Movement, _ session: WorkoutSession) -> String {
        movement.isTimedHold
            ? SessionResult.durationLabel(session.bestHold)
            : "\(session.repCount)"
    }

    // MARK: - Sets

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVERY SET").sectionHeaderStyle()

            VStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, session in
                    NavigationLink(value: session) {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.Color.tertiaryText)
                                .frame(width: 18, alignment: .leading)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.movement.displayName)
                                    .font(Theme.Font.body())
                                    .foregroundStyle(Theme.Color.primaryText)
                                Text(session.timeLabel)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Color.tertiaryText)
                            }

                            Spacer(minLength: 8)

                            Text(session.result.displayValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Color.secondaryText)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                        .frame(height: 52)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    if index < sets.count - 1 {
                        Rectangle()
                            .fill(Theme.Color.rowSeparator)
                            .frame(height: 1)
                            .padding(.leading, 30)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        }
    }
}
