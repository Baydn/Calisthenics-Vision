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
//  This screen has one job: choose which movements appear as chips on Train,
//  and in what order. Tapping a card pins it; the green outline and the bar at
//  the top are the same set seen two ways. There is no second screen behind a
//  card — a tap that could mean either "pin this" or "tell me about this" has
//  to be disambiguated by the user every time, and pinning is what people come
//  here to do.
//
//  Laid out as cards rather than rows. Thirty-nine names in a list is a wall
//  of text you have to read; a grid of figures is something you can scan, and
//  it's the one screen where a drawing of the movement beats its label. Rows
//  are still right where the name is the point — history, workouts — and the
//  glyph stays small there.
//

import SwiftUI

struct MovementLibraryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared
    @State private var search = ""
    @State private var equipment: Equipment?
    /// The chip currently being dragged in the Train bar.
    @State private var dragging: Movement?
    /// Which gap in the Train bar a drop would land in.
    @State private var dropIndex: Int?

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

    /// Three columns. The grid exists to be scanned, and two columns only fit
    /// six movements on screen — barely better than the list it replaced. The
    /// figure stays legible at this size because it's drawn rather than
    /// resampled from an image.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 3
    )

    /// Tighter than `screenPadding`, which is set for reading a column of text
    /// rather than for a grid.
    private let gridPadding: CGFloat = 20

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed above the grid rather than scrolling with it: you star
                // things from the list below and watch them land here, which
                // is the whole point of the bar.
                if !settings.pinnedMovements.isEmpty {
                    quickPicksBar
                    Divider().overlay(Theme.Color.divider)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        searchField
                            .padding(.horizontal, Theme.Metric.screenPadding)
                            .padding(.top, 10)
                            .padding(.bottom, 12)

                        equipmentRow
                            .padding(.bottom, 22)

                        if matches.isEmpty {
                            emptyState
                        } else {
                            ForEach(MovementCategory.allCases) { category in
                                let items = movements(in: category)
                                if !items.isEmpty {
                                    section(category.displayName.uppercased(), items,
                                            trailing: "\(items.count)")
                                }
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.Color.background)
            .navigationTitle("Movements")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Quick picks

    /// The movements that appear as chips on Train, in the order they appear
    /// there. Drag to reorder; the star in the grid below adds and removes.
    private var quickPicksBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("ON TRAIN").sectionHeaderStyle()
                Spacer()
                Text(dragging == nil ? "DRAG TO REORDER" : "DROP TO PLACE")
                    .cardLabelStyle()
            }
            .padding(.horizontal, gridPadding)

            ScrollView(.horizontal) {
                // Drops land in the gaps *between* chips, not on top of them.
                // Targeting a chip can only ever mean "take that one's place",
                // which is a swap; targeting a gap means "go here", which is
                // what dragging something into a list should do.
                HStack(spacing: 0) {
                    dropGap(0)
                    ForEach(Array(settings.pinnedMovements.enumerated()), id: \.element) { index, movement in
                        pickChip(movement)
                            .opacity(dragging == movement ? 0.35 : 1)
                            .draggable(movement.rawValue) {
                                pickChip(movement).opacity(0.9)
                            }
                        dropGap(index + 1)
                    }
                }
                .padding(.horizontal, gridPadding - 8)
                .animation(Theme.Motion.content, value: settings.pinnedMovements)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 10)
    }

    /// A landing slot between two chips. It widens while a chip is over it, so
    /// the gap you are about to drop into is the one you can see.
    private func dropGap(_ index: Int) -> some View {
        let active = dropIndex == index
        return RoundedRectangle(cornerRadius: 2)
            .fill(active ? Theme.Color.valid : .clear)
            .frame(width: active ? 3 : 2, height: 24)
            .padding(.horizontal, active ? 6 : 3.5)
            .contentShape(.rect.inset(by: -7))
            .dropDestination(for: String.self) { items, _ in
                insert(items.first, at: index)
            } isTargeted: { over in
                withAnimation(Theme.Motion.selection) {
                    dropIndex = over ? index : (dropIndex == index ? nil : dropIndex)
                }
            }
    }

    private func pickChip(_ movement: Movement) -> some View {
        HStack(spacing: 6) {
            MovementGlyphView(
                movement: movement,
                tint: Theme.Color.primaryText,
                background: Theme.Color.card,
                weight: 5.4,
                showsProp: false,
                padding: 2
            )
            .frame(width: 26, height: 26)

            Text(movement.displayName)
                .font(Theme.Font.control())
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(1)

            Button {
                withAnimation(Theme.Motion.content) { togglePin(movement) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .frame(height: 38)
        .background(Theme.Color.card, in: .capsule)
    }

    /// Inserts the dragged movement at `index`, which is a position between
    /// chips rather than another chip's slot.
    private func insert(_ raw: String?, at index: Int) -> Bool {
        defer { dragging = nil; dropIndex = nil }
        guard let raw, let moved = Movement(rawValue: raw),
              let from = settings.pinnedMovements.firstIndex(of: moved)
        else { return false }

        // Removing first shifts every later slot down by one.
        let to = index > from ? index - 1 : index
        guard to != from else { return false }

        withAnimation(Theme.Motion.content) {
            var order = settings.pinnedMovements
            order.remove(at: from)
            order.insert(moved, at: min(to, order.count))
            settings.pinnedMovements = order
        }
        return true
    }

    // MARK: - Pinning

    // MARK: - Pinning

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

    private func section(_ title: String, _ items: [Movement], trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).sectionHeaderStyle()
                Spacer()
                Text(trailing).cardLabelStyle()
            }
            .padding(.horizontal, Theme.Metric.screenPadding)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { card($0) }
            }
            .padding(.horizontal, gridPadding)
        }
        .padding(.bottom, 26)
    }

    private func card(_ movement: Movement) -> some View {
        Button {
            withAnimation(Theme.Motion.content) { togglePin(movement) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // The figure is fitted to the *smaller* side of its well, so a
                // short wide well left a square pose scaled to the height and
                // floating in empty space. A well close to the figure's own
                // proportions, with almost no padding, is what makes it fill
                // the card.
                MovementGlyphView(
                    movement: movement,
                    tint: movement.isTrackingSupported
                        ? Theme.Color.primaryText : Theme.Color.secondaryText,
                    background: Theme.Color.elevated,
                    weight: 4.6,
                    padding: 3
                )
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(Theme.Color.elevated)
                .overlay(alignment: .topLeading) {
                    DifficultyPill(level: movement.difficulty)
                        .scaleEffect(0.82)
                        .padding(.leading, 2)
                        .padding(.top, 2)
                }

                // No reserved second line: a row of cards already matches its
                // tallest card, so reserving space only bought dead air under
                // every short name.
                Text(movement.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.top, 5)
                    .padding(.bottom, 6)
            }
            .background(Theme.Color.card)
            .clipShape(.rect(cornerRadius: Theme.Metric.cardRadius))
            // The outline *is* the pinned state — the same set the bar at the
            // top lists, so there's nothing extra to read.
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                    .strokeBorder(isPinned(movement) ? Theme.Color.valid : .clear,
                                  lineWidth: 1.5)
            }
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

#Preview {
    MovementLibraryView()
}
