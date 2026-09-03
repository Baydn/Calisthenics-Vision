//
//  SkillTreeView.swift
//  Calisthenics Vision
//
//  Every movement on one map that grows outward from where you started.
//
//  Two earlier attempts were wrong. A ladder per category implied an order
//  when people arrive from wrestling, gymnastics and climbing already able to
//  do things halfway up. A difficulty grid fixed the order problem and
//  replaced it with a wall of evenly spaced dots that read as a spreadsheet.
//
//  This is radial: the root is you, the foundations sit closest, and each ring
//  outward is a step harder — so the thing you can already do is at the centre
//  and the map genuinely expands as you get further out. Pinch to zoom, drag
//  to pan.
//
//  Nodes change as you advance rather than only filling a ring: a movement you
//  haven't touched is a small dim dot, one you're working on grows and gains
//  an arc, one you've earned grows again and takes the accent, and a mastered
//  one gets a halo. Size carries progress at a glance, which a ring alone
//  can't do when the map is zoomed out.
//
//  Nothing is locked. `Movement.prerequisites` draws where things lead, not
//  what you're allowed to attempt.
//

import SwiftData
import SwiftUI

struct SkillTreeView: View {
    let sessions: [WorkoutSession]

    @State private var selected: Movement?
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    @State private var appeared = false

    // MARK: - Layout

    /// Radius per difficulty step, and the canvas built from it.
    private static let ringGap: CGFloat = 92
    private static let canvasRadius: CGFloat = ringGap * 10 + 90
    private static var canvasSize: CGFloat { canvasRadius * 2 }

    /// Polar layout: angle groups a movement with its category, radius is its
    /// difficulty. Categories get a sector each so branches stay together.
    private static let layout: [Movement: CGPoint] = buildLayout()

    /// Split out of a stored property: as one expression the type-checker
    /// gives up on it.
    private static func buildLayout() -> [Movement: CGPoint] {
        var result: [Movement: CGPoint] = [:]
        let categories = MovementCategory.allCases
        let sector: Double = (2.0 * Double.pi) / Double(categories.count)
        let origin: Double = Double(canvasRadius)
        let gap: Double = Double(ringGap)

        for (index, category) in categories.enumerated() {
            let members = Movement.allCases
                .filter { $0.category == category }
                .sorted { ($0.difficulty, $0.displayName) < ($1.difficulty, $1.displayName) }

            // Same-difficulty siblings are nudged apart so they don't stack.
            var perRing: [Int: Int] = [:]

            for movement in members {
                let ring: Int = movement.difficulty
                let slot: Int = perRing[ring, default: 0]
                perRing[ring] = slot + 1

                let base: Double = Double(index) * sector - (Double.pi / 2.0)
                let jitter: Double = sector * 0.78 * (Double(slot) - 1.0) * 0.30
                let angle: Double = base + jitter

                let radius: Double = Double(ring) * gap
                let x: Double = origin + cos(angle) * radius
                let y: Double = origin + sin(angle) * radius
                result[movement] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    private static func position(_ movement: Movement) -> CGPoint {
        layout[movement] ?? CGPoint(x: canvasRadius, y: canvasRadius)
    }

    private static var centre: CGPoint {
        CGPoint(x: canvasRadius, y: canvasRadius)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            map
            detail
        }
        .onAppear {
            withAnimation(Theme.Motion.expand.delay(0.05)) { appeared = true }
        }
    }

    private var map: some View {
        GeometryReader { proxy in
            ZStack {
                rings
                edges
                root
                nodes
            }
            .frame(width: Self.canvasSize, height: Self.canvasSize)
            .scaleEffect(zoom)
            .offset(pan)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(.rect)
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            pan = CGSize(
                                width: committedPan.width + value.translation.width,
                                height: committedPan.height + value.translation.height
                            )
                        }
                        .onEnded { _ in committedPan = pan },
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(2.2, max(0.32, committedZoom * value.magnification))
                        }
                        .onEnded { _ in committedZoom = zoom }
                )
            )
            .onAppear {
                // Open centred on the root, zoomed out enough to see the
                // foundations and the first branches.
                committedZoom = 0.5
                zoom = 0.5
                let centred = CGSize(
                    width: proxy.size.width / 2 - Self.canvasRadius * 0.5,
                    height: proxy.size.height / 2 - Self.canvasRadius * 0.5
                )
                pan = centred
                committedPan = centred
            }
        }
        .frame(height: 440)
        .background(Theme.Color.card.opacity(0.35), in: .rect(cornerRadius: Theme.Metric.cardRadius))
        .overlay(alignment: .topTrailing) { zoomControls }
    }

    private var zoomControls: some View {
        VStack(spacing: 6) {
            zoomButton("plus") { setZoom(zoom * 1.35) }
            zoomButton("minus") { setZoom(zoom / 1.35) }
        }
        .padding(10)
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
                .frame(width: 30, height: 30)
                .background(Theme.Color.elevated.opacity(0.9), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func setZoom(_ next: CGFloat) {
        withAnimation(Theme.Motion.selection) {
            zoom = min(2.2, max(0.32, next))
            committedZoom = zoom
        }
    }

    // MARK: - Canvas layers

    /// Faint rings mark the difficulty steps, so distance from the centre
    /// reads as difficulty without counting nodes.
    private var rings: some View {
        ZStack {
            ForEach(1..<11, id: \.self) { ring in
                Circle()
                    .strokeBorder(
                        Theme.Color.primaryText.opacity(ring.isMultiple(of: 2) ? 0.05 : 0.025),
                        lineWidth: 1
                    )
                    .frame(
                        width: Self.ringGap * CGFloat(ring) * 2,
                        height: Self.ringGap * CGFloat(ring) * 2
                    )
            }
        }
    }

    private var edges: some View {
        Canvas { context, _ in
            for movement in Movement.allCases {
                let to = Self.position(movement)
                let parents = movement.prerequisites

                if parents.isEmpty {
                    // Roots hang off the centre, so the map is one connected
                    // thing rather than five floating clusters.
                    var path = Path()
                    path.move(to: Self.centre)
                    path.addLine(to: to)
                    context.stroke(
                        path,
                        with: .color(Theme.Color.divider.opacity(0.5)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                    )
                    continue
                }

                for parent in parents {
                    let from = Self.position(parent)
                    let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    // Bow the line away from the centre so branches fan out
                    // instead of overlapping the rings.
                    let outward = CGPoint(
                        x: mid.x + (mid.x - Self.centre.x) * 0.12,
                        y: mid.y + (mid.y - Self.centre.y) * 0.12
                    )
                    var path = Path()
                    path.move(to: from)
                    path.addQuadCurve(to: to, control: outward)

                    let lit = isEarned(parent)
                    context.stroke(
                        path,
                        with: .color(lit
                                     ? Theme.Color.valid.opacity(0.5)
                                     : Theme.Color.divider.opacity(0.7)),
                        style: StrokeStyle(lineWidth: lit ? 2 : 1.3, lineCap: .round)
                    )
                }
            }
        }
        .frame(width: Self.canvasSize, height: Self.canvasSize)
    }

    private var root: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(Theme.Color.primaryText)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.background)
                }
            Text("YOU")
                .font(.system(size: 9, weight: .bold))
                .tracking(Theme.Metric.labelTracking)
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .position(Self.centre)
    }

    private var nodes: some View {
        ForEach(Movement.allCases) { movement in
            let point = Self.position(movement)
            SkillNode(
                movement: movement,
                progress: progress(for: movement),
                isSelected: selected == movement,
                showsLabel: zoom > 0.62
            )
            .position(point)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.7)
            .animation(
                Theme.Motion.expand.delay(Double(movement.difficulty) * 0.035),
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
                        Text("\(rank(for: movement)) · \(movement.category.displayName.uppercased())")
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
            Text("Pinch to zoom, drag to move. Tap a node for its numbers — nothing is locked, so start wherever you already are.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rank(for movement: Movement) -> String {
        switch progress(for: movement) {
        case 0:         "UNTOUCHED"
        case ..<0.5:    "LEARNING"
        case ..<1:      "CLOSE"
        case ..<2:      "EARNED"
        default:        "MASTERED"
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

    /// Runs past 1: reaching the target earns the node, doubling it masters
    /// it. Provisional targets — ten seconds for a hold, ten reps otherwise.
    private func progress(for movement: Movement) -> Double {
        let mine = sessions.filter { $0.movement == movement }
        guard !mine.isEmpty else { return 0 }

        if movement.isTimedHold {
            return (mine.map(\.bestHold).max() ?? 0) / 10
        }
        return Double(mine.map(\.repCount).max() ?? 0) / 10
    }

    private func isEarned(_ movement: Movement) -> Bool { progress(for: movement) >= 1 }
}

// MARK: - Node

/// Grows with how far you've taken the movement, so the map reads at a glance
/// even zoomed out where labels are hidden.
private struct SkillNode: View {
    let movement: Movement
    let progress: Double
    let isSelected: Bool
    let showsLabel: Bool

    private var isEarned: Bool { progress >= 1 }
    private var isMastered: Bool { progress >= 2 }
    private var isStarted: Bool { progress > 0 }

    private var diameter: CGFloat {
        if isMastered { return 56 }
        if isEarned { return 48 }
        if isStarted { return 40 }
        return 26
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if isMastered {
                    Circle()
                        .fill(Theme.Color.valid.opacity(0.16))
                        .frame(width: diameter + 16, height: diameter + 16)
                }

                Circle()
                    .fill(isEarned ? Theme.Color.valid.opacity(0.18) : Theme.Color.card)
                    .frame(width: diameter, height: diameter)

                Circle()
                    .stroke(
                        isStarted ? Theme.Color.valid.opacity(0.35) : Theme.Color.divider.opacity(0.6),
                        lineWidth: 2
                    )
                    .frame(width: diameter, height: diameter)

                if isStarted && !isEarned {
                    Circle()
                        .trim(from: 0, to: min(1, progress))
                        .stroke(
                            Theme.Color.valid,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: diameter, height: diameter)
                }

                if isMastered {
                    Image(systemName: "star.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.valid)
                } else if isEarned {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.valid)
                } else if isStarted {
                    Text("\(movement.difficulty)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Color.primaryText)
                }
            }
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(Theme.Color.primaryText, lineWidth: 2)
                        .frame(width: diameter + 12, height: diameter + 12)
                }
            }

            if showsLabel {
                Text(movement.displayName)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isStarted ? Theme.Color.primaryText : Theme.Color.tertiaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 92)
            }
        }
        .contentShape(.rect)
        .animation(Theme.Motion.selection, value: showsLabel)
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
