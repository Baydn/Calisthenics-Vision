//
//  WorkoutBuilderView.swift
//  Calisthenics Vision
//
//  Tick the sets that belong together.
//
//  Grouping after the fact rather than declaring a workout up front: you prop
//  the phone up and do things, and deciding in advance that the next twenty
//  minutes is "a workout" is admin you'd have to get right before you knew
//  how the session would go.
//
//  Defaults to today's sets pre-selected, because that's the common case —
//  you finish training and group what you just did.
//

import SwiftData
import SwiftUI

struct WorkoutBuilderView: View {
    /// Sets ticked when the sheet opens. Empty means "today's".
    var preselected: Set<UUID> = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var chosen: Set<UUID> = []
    @State private var name = ""
    @State private var didPrefill = false

    private var chosenSets: [WorkoutSession] {
        sessions.filter { chosen.contains($0.id) }.sorted { $0.startedAt < $1.startedAt }
    }

    /// Two weeks back is plenty — grouping something from last month isn't a
    /// thing anyone does.
    private var candidates: [WorkoutSession] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) else {
            return sessions
        }
        return sessions.filter { $0.startedAt >= cutoff }
    }

    private var grouped: [(day: Date, sets: [WorkoutSession])] {
        let cal = Calendar.current
        return Dictionary(grouping: candidates) { cal.startOfDay(for: $0.startedAt) }
            .map { (day: $0.key, sets: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameField

                    if candidates.isEmpty {
                        Text("Nothing recorded in the last two weeks.")
                            .font(Theme.Font.body())
                            .foregroundStyle(Theme.Color.secondaryText)
                    } else {
                        ForEach(grouped, id: \.day) { group in
                            daySection(group.day, group.sets)
                        }
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("New workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(chosen.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: prefill)
    }

    // MARK: - Pieces

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME").sectionHeaderStyle()
            TextField(
                chosenSets.isEmpty ? "Workout" : Workout.suggestedName(for: chosenSets),
                text: $name
            )
            .font(Theme.Font.body())
            .foregroundStyle(Theme.Color.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.Color.card, in: .rect(cornerRadius: 10))

            if !chosenSets.isEmpty {
                Text("\(chosen.count) set\(chosen.count == 1 ? "" : "s") selected")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.valid)
            }
        }
    }

    private func daySection(_ day: Date, _ sets: [WorkoutSession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(HistoryListView.sectionTitle(for: day))
                    .sectionHeaderStyle()
                Spacer()
                Button(allChosen(in: sets) ? "None" : "All") {
                    withAnimation(Theme.Motion.content) { toggleAll(sets) }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.valid)
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, session in
                    selectRow(session)
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

    private func selectRow(_ session: WorkoutSession) -> some View {
        let isOn = chosen.contains(session.id)
        return Button {
            withAnimation(Theme.Motion.content) {
                if isOn { chosen.remove(session.id) } else { chosen.insert(session.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isOn ? Theme.Color.valid : Theme.Color.tertiaryText)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.movement.displayName)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.primaryText)
                    Text(session.timeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.tertiaryText)
                }

                Spacer(minLength: 8)

                Text(session.result.displayValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true

        if !preselected.isEmpty {
            chosen = preselected
            return
        }
        // Today's sets, because grouping what you just did is the common case.
        let today = Calendar.current.startOfDay(for: .now)
        chosen = Set(sessions.filter { $0.startedAt >= today }.map(\.id))
    }

    private func allChosen(in sets: [WorkoutSession]) -> Bool {
        !sets.isEmpty && sets.allSatisfy { chosen.contains($0.id) }
    }

    private func toggleAll(_ sets: [WorkoutSession]) {
        if allChosen(in: sets) {
            sets.forEach { chosen.remove($0.id) }
        } else {
            sets.forEach { chosen.insert($0.id) }
        }
    }

    private func save() {
        let sets = chosenSets
        guard !sets.isEmpty else { return }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let workout = Workout(
            name: trimmed.isEmpty ? Workout.suggestedName(for: sets) : trimmed,
            createdAt: sets.first?.startedAt ?? .now,
            sessionIDs: sets.map(\.id)
        )
        modelContext.insert(workout)
        try? modelContext.save()
        Haptics.sessionComplete()
        dismiss()
    }
}

#Preview {
    WorkoutBuilderView()
        .modelContainer(SampleSessions.previewContainer)
}
