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
    @State private var notes = ""
    @State private var didPrefill = false
    @State private var rejected: String?
    @State private var visibility: WorkoutVisibility = .everyone

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
                VStack(alignment: .leading, spacing: 24) {
                    // Details, then what's in it, then who sees it. Three
                    // questions in the order you'd answer them, rather than
                    // one screen of mixed controls.
                    nameField
                    notesField

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("SETS").sectionHeaderStyle()
                            Spacer()
                            if !chosenSets.isEmpty {
                                Text("\(chosen.count) selected · \(spanLabel)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.Color.valid)
                            }
                        }

                        if let rejected {
                            Text(rejected)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Color.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

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

                    visibilityPicker
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

        }
    }

    /// Last, because it's the last decision you make and the one you want to
    /// see plainly before saving.
    private var visibilityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHO CAN SEE IT").sectionHeaderStyle()

            VStack(spacing: 0) {
                ForEach(Array(WorkoutVisibility.allCases.enumerated()), id: \.element.id) { index, option in
                    Button {
                        withAnimation(Theme.Motion.content) { visibility = option }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(visibility == option
                                                 ? Theme.Color.valid : Theme.Color.secondaryText)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                    .font(Theme.Font.body())
                                    .foregroundStyle(Theme.Color.primaryText)
                                Text(option.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Color.tertiaryText)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: visibility == option
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(visibility == option
                                                 ? Theme.Color.valid : Theme.Color.tertiaryText)
                        }
                        .frame(height: 56)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    if index < WorkoutVisibility.allCases.count - 1 {
                        Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES").sectionHeaderStyle()
            TextField("How it went, what you were working on", text: $notes, axis: .vertical)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(2...5)
                .padding(14)
                .background(Theme.Color.card, in: .rect(cornerRadius: 10))
        }
    }

    /// How long the workout ran, end to end.
    private var spanLabel: String {
        let sets = chosenSets
        guard let first = sets.first, let last = sets.last, sets.count > 1 else {
            return "one set"
        }
        let minutes = Int(last.startedAt.timeIntervalSince(first.startedAt) / 60)
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
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
        let blocked = !isOn && !canAdd(session)

        return Button {
            withAnimation(Theme.Motion.content) { toggle(session) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : (blocked ? "clock.badge.xmark" : "circle"))
                    .font(.system(size: 19))
                    .foregroundStyle(isOn ? Theme.Color.valid
                                     : (blocked ? Theme.Color.divider : Theme.Color.tertiaryText))

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
            .opacity(blocked ? 0.45 : 1)
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
        // The most recent bout: walk back from the latest set while the gap
        // stays inside the limit. Grouping what you just finished is the
        // common case, and "today" would have swept up this morning too.
        let ordered = sessions.sorted { $0.startedAt > $1.startedAt }
        guard let latest = ordered.first else { return }

        var bout = [latest]
        for session in ordered.dropFirst() {
            guard let previous = bout.last,
                  previous.startedAt.timeIntervalSince(session.startedAt) <= Workout.maxGapBetweenSets
            else { break }
            bout.append(session)
        }
        chosen = Set(bout.map(\.id))
    }

    private func allChosen(in sets: [WorkoutSession]) -> Bool {
        !sets.isEmpty && sets.allSatisfy { chosen.contains($0.id) }
    }

    private func toggleAll(_ sets: [WorkoutSession]) {
        if allChosen(in: sets) {
            sets.forEach { chosen.remove($0.id) }
            rejected = nil
        } else {
            // Oldest first, so each addition is checked against a set that's
            // already in rather than against one that may yet be rejected.
            for session in sets.sorted(by: { $0.startedAt < $1.startedAt }) {
                if canAdd(session) { chosen.insert(session.id) }
            }
        }
    }

    private func toggle(_ session: WorkoutSession) {
        if chosen.contains(session.id) {
            chosen.remove(session.id)
            rejected = nil
            return
        }
        guard canAdd(session) else {
            rejected = "That set is more than three hours from the others — group it as its own workout."
            Haptics.formBreak()
            return
        }
        rejected = nil
        chosen.insert(session.id)
    }

    /// A workout is one bout of training, so every set has to sit within
    /// `maxGapBetweenSets` of another one already chosen. Without this you
    /// could fold yesterday morning in with this afternoon and any duration
    /// computed across it would be meaningless.
    private func canAdd(_ session: WorkoutSession) -> Bool {
        let existing = chosenSets
        guard !existing.isEmpty else { return true }
        return existing.contains { other in
            abs(other.startedAt.timeIntervalSince(session.startedAt)) <= Workout.maxGapBetweenSets
        }
    }

    private func save() {
        let sets = chosenSets
        guard !sets.isEmpty else { return }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let workout = Workout(
            name: trimmed.isEmpty ? Workout.suggestedName(for: sets) : trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: sets.first?.startedAt ?? .now,
            visibility: visibility,
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
