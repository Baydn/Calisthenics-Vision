//
//  SkillTreeView.swift
//  Calisthenics Vision
//
//  Your skills as a branching tree, one branch per category.
//
//  Every rival has one of these and every one of them is self-reported: you
//  tap a node to say you can do it. Ours fills from measured sessions, which
//  is why the progress ring matters — it isn't decoration, it's how close
//  your best recorded effort is to the node's criterion.
//
//  The ring idea is Calistree's, and it's the right one: a node that's part
//  done reads very differently from one that's locked, and "part done" is the
//  state you're in most of the time.
//
//  Thresholds below are provisional and marked as such on screen. They're the
//  one thing here that isn't derived from anything — picking them properly
//  needs a coach, not a developer.
//

import SwiftData
import SwiftUI

struct SkillTreeView: View {
    let sessions: [WorkoutSession]

    @State private var category: MovementCategory = .push
    @State private var appeared = false

    /// The branch for the chosen category, easiest first — which is also the
    /// order you'd learn them in.
    private var branch: [Movement] {
        Movement.allCases
            .filter { $0.category == category }
            .sorted { ($0.difficulty, $0.displayName) < ($1.difficulty, $1.displayName) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MovementCategory.allCases) { option in
                        FilterChip(
                            title: option.displayName,
                            isActive: option == category
                        ) {
                            withAnimation(Theme.Motion.selection) {
                                category = option
                                appeared = false
                            }
                            // Re-run the stagger so switching branch feels
                            // like the tree growing, not a list swapping.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(Theme.Motion.expand) { appeared = true }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            tree
        }
        .onAppear {
            withAnimation(Theme.Motion.expand.delay(0.05)) { appeared = true }
        }
    }

    // MARK: - Tree

    private var tree: some View {
        let nodes = branch.enumerated().map { index, movement in
            Node(movement: movement, progress: progress(for: movement), row: index)
        }

        return ZStack(alignment: .top) {
            Connectors(count: nodes.count, unlockedThrough: unlockedCount(nodes))
            VStack(spacing: 0) {
                ForEach(nodes, id: \.movement.id) { node in
                    NodeRow(node: node, isUnlocked: isUnlocked(node, in: nodes))
                        .frame(height: Self.rowHeight)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(
                            Theme.Motion.expand.delay(Double(node.row) * 0.045),
                            value: appeared
                        )
                }
            }
        }
        .padding(.vertical, 6)
    }

    static let rowHeight: CGFloat = 78

    // MARK: - Progress

    struct Node {
        let movement: Movement
        /// 0…1 toward this node's criterion, from your best recorded effort.
        let progress: Double
        let row: Int

        var isEarned: Bool { progress >= 1 }
    }

    /// Best effort against a provisional target: ten seconds for a hold, ten
    /// reps for a rep movement.
    private func progress(for movement: Movement) -> Double {
        let mine = sessions.filter { $0.movement == movement }
        guard !mine.isEmpty else { return 0 }

        if movement.isTimedHold {
            let best = mine.map(\.bestHold).max() ?? 0
            return min(1, best / 10)
        }
        let best = mine.map(\.repCount).max() ?? 0
        return min(1, Double(best) / 10)
    }

    /// A node opens once the one before it is done — the first is always open.
    private func isUnlocked(_ node: Node, in nodes: [Node]) -> Bool {
        guard node.row > 0 else { return true }
        return nodes[node.row - 1].isEarned || node.progress > 0
    }

    private func unlockedCount(_ nodes: [Node]) -> Int {
        nodes.filter(\.isEarned).count
    }
}

// MARK: - Row

private struct NodeRow: View {
    let node: SkillTreeView.Node
    let isUnlocked: Bool

    /// Alternating sides give the branch a shape rather than a straight
    /// column, which is what makes it read as a tree.
    private var isLeft: Bool { node.row.isMultiple(of: 2) }

    var body: some View {
        HStack(spacing: 14) {
            if !isLeft { Spacer(minLength: 0) }

            if isLeft { badge }

            VStack(alignment: isLeft ? .leading : .trailing, spacing: 2) {
                Text(node.movement.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isUnlocked ? Theme.Color.primaryText : Theme.Color.tertiaryText)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(node.isEarned ? Theme.Color.valid : Theme.Color.tertiaryText)
            }
            .frame(maxWidth: 130, alignment: isLeft ? .leading : .trailing)

            if !isLeft { badge }

            if isLeft { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 20)
    }

    private var caption: String {
        if node.isEarned { return "EARNED" }
        if !isUnlocked { return "LOCKED" }
        if node.progress == 0 { return "NOT STARTED" }
        return "\(Int(node.progress * 100))% THERE"
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(Theme.Color.card)
                .frame(width: 52, height: 52)

            // The growing arc: how close your best effort is to the criterion.
            Circle()
                .trim(from: 0, to: max(0.001, node.progress))
                .stroke(
                    node.isEarned ? Theme.Color.valid : Theme.Color.valid.opacity(0.55),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 52, height: 52)

            if node.isEarned {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.Color.valid)
            } else if isUnlocked {
                Text("\(node.movement.difficulty)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.Color.primaryText)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
        .opacity(isUnlocked ? 1 : 0.5)
    }
}

// MARK: - Connectors

/// The lines between nodes, drawn behind them. Solid where the branch is
/// complete, dashed where it isn't — so the shape of the tree tells you how
/// far you've got before you read a single label.
private struct Connectors: View {
    let count: Int
    let unlockedThrough: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let h = SkillTreeView.rowHeight
            let inset: CGFloat = 46          // centre of a 52pt badge at 20pt padding

            ZStack {
                ForEach(0..<max(0, count - 1), id: \.self) { row in
                    let fromLeft = row.isMultiple(of: 2)
                    let start = CGPoint(
                        x: fromLeft ? inset : width - inset,
                        y: h * (CGFloat(row) + 0.5) + 6
                    )
                    let end = CGPoint(
                        x: fromLeft ? width - inset : inset,
                        y: h * (CGFloat(row) + 1.5) + 6
                    )

                    Path { path in
                        path.move(to: start)
                        // A gentle curve rather than a straight diagonal:
                        // branches bend.
                        path.addCurve(
                            to: end,
                            control1: CGPoint(x: start.x, y: start.y + h * 0.55),
                            control2: CGPoint(x: end.x, y: end.y - h * 0.55)
                        )
                    }
                    .stroke(
                        row < unlockedThrough
                            ? Theme.Color.valid.opacity(0.5)
                            : Theme.Color.divider,
                        style: StrokeStyle(
                            lineWidth: 2,
                            lineCap: .round,
                            dash: row < unlockedThrough ? [] : [3, 5]
                        )
                    )
                }
            }
        }
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
