//
//  MovementLibraryView.swift
//  Calisthenics Vision
//
//  Frame 02b — Movement Library.
//
//  Six movements in a flat list worked. Forty-three doesn't, so this groups
//  by category, carries a difficulty for each, and can be filtered by what's
//  actually in the room — which is a real barrier for someone starting out,
//  not a nicety.
//
//  Movements without a tracker are listed rather than hidden, with a plain
//  "not tracked yet". Hiding them would make the library lie about where the
//  app is going, and picking one still lets you record the set.
//
//  Which movements show as one-tap chips on Train is a choice made here, not
//  a fixed list — tap the star. Quick Picks sits pinned at the top so
//  choosing is a couple of taps rather than a hunt.
//

import SwiftUI

struct MovementLibraryView: View {
    @Binding var selected: Movement

    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    @State private var settings = AppSettings.shared
    @State private var search = ""
    @State private var equipment: Equipment?
    @State private var detail: Movement?
    @State private var showPaywall = false

    private var matches: [Movement] {
        Movement.allCases.filter { movement in
            let term = search.trimmingCharacters(in: .whitespaces)
            let matchesSearch = term.isEmpty
                || movement.displayName.localizedCaseInsensitiveContains(term)
                || movement.category.displayName.localizedCaseInsensitiveContains(term)
            let matchesKit = equipment == nil || movement.equipment == equipment
            return matchesSearch && matchesKit
        }
    }

    private func movements(in category: MovementCategory) -> [Movement] {
        // Easiest first, so a category reads as a path rather than a wall.
        matches.filter { $0.category == category }
            .sorted { ($0.difficulty, $0.displayName) < ($1.difficulty, $1.displayName) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    searchField
                        .padding(.horizontal, Theme.Metric.screenPadding)
                        .padding(.bottom, 12)

                    equipmentRow
                        .padding(.bottom, 26)

                    if !settings.pinnedMovements.isEmpty {
                        quickPicksSection
                            .padding(.bottom, 26)
                    }

                    if matches.isEmpty {
                        emptyState
                    } else {
                        ForEach(MovementCategory.allCases) { category in
                            let items = movements(in: category)
                            if !items.isEmpty {
                                section(category, items)
                            }
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Movements")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $detail) { movement in
                MovementDetailView(movement: movement) {
                    choose(movement)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Quick picks

    private var quickPicksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QUICK PICKS").sectionHeaderStyle()
                Spacer()
                Text("SHOWN ON TRAIN").cardLabelStyle()
            }
            .padding(.horizontal, Theme.Metric.screenPadding)

            VStack(spacing: 0) {
                ForEach(Array(settings.pinnedMovements.enumerated()), id: \.element.id) { index, movement in
                    row(movement)
                    if index < settings.pinnedMovements.count - 1 {
                        Rectangle()
                            .fill(Theme.Color.rowSeparator)
                            .frame(height: 1)
                            .padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
            .padding(.horizontal, Theme.Metric.screenPadding)
        }
    }

    private func isPinned(_ movement: Movement) -> Bool {
        settings.pinnedMovements.contains(movement)
    }

    private func togglePin(_ movement: Movement) {
        withAnimation(Theme.Motion.content) {
            if let index = settings.pinnedMovements.firstIndex(of: movement) {
                settings.pinnedMovements.remove(at: index)
            } else {
                settings.pinnedMovements.append(movement)
            }
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.tertiaryText)
            TextField("Search \(Movement.allCases.count) movements", text: $search)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.primaryText)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    withAnimation(Theme.Motion.content) { search = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Color.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Theme.Color.card, in: .rect(cornerRadius: 10))
    }

    private var equipmentRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isActive: equipment == nil) {
                    withAnimation(Theme.Motion.selection) { equipment = nil }
                }
                ForEach(Equipment.allCases) { kit in
                    FilterChip(title: kit.displayName, isActive: equipment == kit) {
                        withAnimation(Theme.Motion.selection) {
                            equipment = (equipment == kit) ? nil : kit
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
        }
        .scrollIndicators(.hidden)
    }

    private func section(_ category: MovementCategory, _ items: [Movement]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.displayName.uppercased())
                    .sectionHeaderStyle()
                Spacer()
                Text("\(items.count)")
                    .cardLabelStyle()
            }
            .padding(.horizontal, Theme.Metric.screenPadding)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, movement in
                    row(movement)
                    if index < items.count - 1 {
                        Rectangle()
                            .fill(Theme.Color.rowSeparator)
                            .frame(height: 1)
                            .padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
            .padding(.horizontal, Theme.Metric.screenPadding)
        }
        .padding(.bottom, 22)
    }

    private func row(_ movement: Movement) -> some View {
        Button { detail = movement } label: {
            HStack(spacing: 12) {
                DifficultyPill(level: movement.difficulty)

                VStack(alignment: .leading, spacing: 2) {
                    Text(movement.displayName)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.primaryText)
                        .lineLimit(1)
                    Text(movement.summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Color.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button { togglePin(movement) } label: {
                    Image(systemName: isPinned(movement) ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPinned(movement) ? Theme.Color.valid : Theme.Color.tertiaryText)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                TrackingBadge(movement: movement)

                if movement == selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Color.valid)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .frame(height: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing matches")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Color.primaryText)
            Text("Try a different search, or clear the equipment filter.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding(.horizontal, Theme.Metric.screenPadding)
        .padding(.vertical, 40)
    }

    private func choose(_ movement: Movement) {
        guard entitlements.canTrack(movement) else {
            showPaywall = true
            return
        }
        selected = movement
        dismiss()
    }
}

// MARK: - Shared bits

/// Difficulty 1–10, coloured by tier. Experienced people want to know what
/// they're looking at before they tap it.
struct DifficultyPill: View {
    let level: Int

    var body: some View {
        Text("\(level)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(tint.opacity(0.16), in: .rect(cornerRadius: 6))
    }

    private var tint: SwiftUI.Color {
        switch level {
        case ...2:  Theme.Color.valid
        case 3...4: SwiftUI.Color(red: 0.61, green: 0.87, blue: 0.37)
        case 5...6: SwiftUI.Color(red: 1.00, green: 0.78, blue: 0.24)
        case 7...8: SwiftUI.Color(red: 1.00, green: 0.55, blue: 0.20)
        default:    Theme.Color.warning
        }
    }
}

/// Says plainly whether the camera can score this movement yet. With
/// forty-three listed, that label is doing a lot of work.
struct TrackingBadge: View {
    let movement: Movement

    var body: some View {
        Text(movement.isTrackingSupported ? "TRACKED" : "SOON")
            .font(.system(size: 9, weight: .semibold))
            .tracking(Theme.Metric.labelTracking)
            .foregroundStyle(movement.isTrackingSupported
                             ? Theme.Color.valid : Theme.Color.tertiaryText)
    }
}

#Preview {
    MovementLibraryView(selected: .constant(.pushUps))
        .environment(Entitlements())
}
