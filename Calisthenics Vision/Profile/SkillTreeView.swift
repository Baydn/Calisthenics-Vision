//
//  SkillTreeView.swift
//  Calisthenics Vision
//
//  Every movement on one map you pan around.
//
//  The first version was a ladder per category, which was wrong in two ways.
//  It implied an order — do this, then that — when people arrive from
//  wrestling, gymnastics and climbing and can already do things halfway up.
//  And it hid the shape: the interesting part of calisthenics progression is
//  that it *branches and rejoins*, which a column can't draw. An L-sit
//  pull-up needs a pull-up and an L-sit; a planche needs a pseudo-planche
//  push-up and an elbow lever.
//
//  So: one canvas, difficulty running down, categories across, edges wherever
//  one movement genuinely leads to another. Nothing is locked. You can start
//  anywhere and the map just shows you where you are.
//
//  Nodes fill from measured sessions — the ring is how close your best effort
//  is to the target. Every rival's tree is a box you tick.
//

import SwiftData
import SwiftUI

struct SkillTreeView: View {
    let sessions: [WorkoutSession]

    @State private var selected: Movement?
    @State private var appeared = false

    // MARK: - Layout

    private static let nodeSize: CGFloat = 54
    private static let columnWidth: CGFloat = 108
    private static let rowHeight: CGFloat = 104
    private static let topInset: CGFloat = 36
    private static let sideInset: CGFloat = 26

    /// Grid position for every movement: y from difficulty, x packed within
    /// its category so branches sit near their siblings.
    private static let layout: [Movement: CGPoint] = {
        var result: [Movement: CGPoint] = [:]
        var columnCursor = 0

        for category in MovementCategory.allCases {
            let members = Movement.allCases
                .filter { $0.category == category }
                .sorted { ($0.difficulty, $0.displayName) < ($1.difficulty, $1.displayName) }

            // Movements sharing a difficulty sit side by side rather than on
            // top of each other.
            var usedByRow: [Int: Int] = [:]
            var widest = 1

            for movement in members {
                let row = movement.difficulty - 1
                let offset = usedByRow[row, default: 0]
                usedByRow[row] = offset + 1
                widest = max(widest, offset + 1)
                result[movement] = CGPoint(x: CGFloat(columnCursor + offset), y: CGFloat(row))
            }
            columnCursor += widest
        }
        return result
    }()

    private static let gridWidth: CGFloat = {
        (layout.values.map(\.x).max() ?? 0) + 1
    }()

    private static var canvasSize: CGSize {
        CGSize(
            width: gridWidth * columnWidth + sideInset * 2,
            height: 10 * rowHeight + topInset * 2
        )
    }

    private static func position(_ movement: Movement) -> CGPoint {
        let grid = layout[movement] ?? .zero
        return CGPoint(
            x: sideInset + grid.x * columnWidth + columnWidth / 2,
            y: topInset + grid.y * rowHeight + rowHeight / 2
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    tiers
                    edges
                    nodes
                }
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
            }
            .scrollIndicators(.hidden)
            .frame(height: 420)
            .background(Theme.Color.card.opacity(0.35), in: .rect(cornerRadius: Theme.Metric.cardRadius))

            detail
        }
        .onAppear {
            withAnimation(Theme.Motion.expand.delay(0.05)) { appeared = true }
        }
    }

    /// Faint bands behind the graph so depth is readable without counting.
    private var tiers: some View {
        ForEach(0..<10, id: \.self) { row in
            let isBanded = (row / 2).isMultiple(of: 2)
            Rectangle()
                .fill(isBanded ? Theme.Color.primaryText.opacity(0.022) : .clear)
                .frame(width: Self.canvasSize.width, height: Self.rowHeight)
                .position(
                    x: Self.canvasSize.width / 2,
                    y: Self.topInset + CGFloat(row) * Self.rowHeight + Self.rowHeight / 2
                )
                .overlay(alignment: .topLeading) {
                    Text("\(row + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Color.tertiaryText.opacity(0.7))
                        .position(
                            x: 12,
                            y: Self.topInset + CGFloat(row) * Self.rowHeight + Self.rowHeight / 2
                        )
                }
        }
    }

    private var edges: some View {
        Canvas { context, _ in
            for movement in Movement.allCases {
                let to = Self.position(movement)
                for parent in movement.prerequisites {
                    let from = Self.position(parent)
                    var path = Path()
                    path.move(to: from)
                    // Curved so crossing branches stay tellable apart.
                    path.addCurve(
                        to: to,
                        control1: CGPoint(x: from.x, y: from.y + Self.rowHeight * 0.45),
                        control2: CGPoint(x: to.x, y: to.y - Self.rowHeight * 0.45)
                    )
                    let done = isEarned(parent) && isEarned(movement)
                    context.stroke(
                        path,
                        with: .color(done
                                     ? Theme.Color.valid.opacity(0.55)
                                     : Theme.Color.divider.opacity(0.75)),
                        style: StrokeStyle(lineWidth: done ? 2 : 1.5, lineCap: .round)
                    )
                }
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
    }

    private var nodes: some View {
        ForEach(Movement.allCases) { movement in
            let point = Self.position(movement)
            SkillNode(
                movement: movement,
                progress: progress(for: movement),
                isSelected: selected == movement
            )
            .position(x: point.x, y: point.y)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.85)
            .animation(
                Theme.Motion.expand.delay(Double(movement.difficulty) * 0.03),
                value: appeared
            )
            .onTapGesture {
                withAnimation(Theme.Motion.selection) {
                    selected = (selected == movement) ? nil : movement
                }
            }
        }
    }

    // MARK: - Detail

    /// Tapping a node opens its numbers here rather than pushing a screen —
    /// the point of a map is staying on it.
    @ViewBuilder
    private var detail: some View {
        if let movement = selected {
            let mine = sessions.filter { $0.movement == movement }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DifficultyPill(level: movement.difficulty)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(movement.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("\(movement.tier.uppercased()) · \(movement.category.displayName.uppercased())")
                            .cardLabelStyle()
                    }
                    Spacer(minLength: 0)
                    TrackingBadge(movement: movement)
                }

                if mine.isEmpty {
                    Text("Not attempted yet. Nothing stops you starting here.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.secondaryText)
                } else {
                    HStack(spacing: 8) {
                        ForEach(statLines(movement, mine), id: \.0) { line in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(line.1)
                                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.Color.primaryText)
                                Text(line.0).cardLabelStyle()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if !movement.prerequisites.isEmpty {
                    Text("Usually after: " + movement.prerequisites.map(\.displayName).joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Text("Tap any node for its numbers. Nothing is locked — start wherever you already are.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.tertiaryText)
        }
    }

    private func statLines(_ movement: Movement, _ mine: [WorkoutSession]) -> [(String, String)] {
        if movement.isTimedHold {
            let holds = mine.flatMap(\.holdSegments)
            let best = mine.map(\.bestHold).max() ?? 0
            let average = holds.isEmpty
                ? 0 : holds.reduce(0) { $0 + $1.duration } / Double(holds.count)
            return [
                ("BEST HOLD", SessionResult.durationLabel(best)),
                ("AVERAGE", average > 0 ? SessionResult.durationLabel(average) : "—"),
                ("SESSIONS", "\(mine.count)"),
            ]
        }
        return [
            ("BEST SET", "\(mine.map(\.repCount).max() ?? 0)"),
            ("TOTAL REPS", "\(mine.reduce(0) { $0 + $1.repCount })"),
            ("SESSIONS", "\(mine.count)"),
        ]
    }

    // MARK: - Progress

    /// Best effort against a provisional target: ten seconds for a hold, ten
    /// reps otherwise.
    private func progress(for movement: Movement) -> Double {
        let mine = sessions.filter { $0.movement == movement }
        guard !mine.isEmpty else { return 0 }

        if movement.isTimedHold {
            return min(1, (mine.map(\.bestHold).max() ?? 0) / 10)
        }
        return min(1, Double(mine.map(\.repCount).max() ?? 0) / 10)
    }

    private func isEarned(_ movement: Movement) -> Bool { progress(for: movement) >= 1 }
}

// MARK: - Node

private struct SkillNode: View {
    let movement: Movement
    let progress: Double
    let isSelected: Bool

    private var isEarned: Bool { progress >= 1 }
    private var isStarted: Bool { progress > 0 }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Theme.Color.card)
                    .frame(width: 54, height: 54)

                Circle()
                    .stroke(Theme.Color.divider.opacity(0.5), lineWidth: 2.5)
                    .frame(width: 54, height: 54)

                // The ring: how close your best effort is to the target.
                if isStarted {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Theme.Color.valid.opacity(isEarned ? 1 : 0.7),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 54, height: 54)
                }

                if isEarned {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.Color.valid)
                } else {
                    Text("\(movement.difficulty)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(isStarted ? Theme.Color.primaryText : Theme.Color.secondaryText)
                }
            }
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(Theme.Color.primaryText, lineWidth: 2)
                        .frame(width: 64, height: 64)
                }
            }

            Text(movement.displayName)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isStarted ? Theme.Color.primaryText : Theme.Color.tertiaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 96)
        }
        .contentShape(.rect)
    }
}

#Preview {
    ScrollView {
        SkillTreeView(sessions: SampleSessions.make())
            .padding(.horizontal, Theme.Metric.screenPadding)
    }
    .background(Theme.Color.background)
    .preferredColorScheme(.dark)
}
