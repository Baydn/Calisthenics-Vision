//
//  SkillTreeView.swift
//  Calisthenics Vision
//
//  The movements you've reached, and the ones directly in front of you.
//
//  Three attempts to get here. A ladder per category implied an order that
//  doesn't exist. A difficulty grid replaced that with a spreadsheet. A radial
//  map of all forty-three was unreadable for the obvious reason: it drew forty
//  movements you've never touched and spaced them far enough apart to fit
//  labels nobody needed yet.
//
//  So it only draws what's relevant: what you've started, and one step beyond.
//  A new account sees six foundations around a centre — small, legible,
//  obviously a beginning. Every movement you attempt lights up and reveals
//  what it leads to, so the tree genuinely grows instead of being a finished
//  wall you're standing outside.
//
//  Layout is by *hops from the centre*, not raw difficulty, which keeps the
//  visible graph tight whatever you've unlocked.
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

    // MARK: - What's on the map

    /// Movements with any recorded work.
    private var started: Set<Movement> {
        Set(sessions.map(\.movement))
    }

    /// What's drawn: everything you've touched, everything those lead to, and
    /// the foundations — so an empty account still has a tree.
    private var visible: [Movement] {
        var result = Set(Movement.allCases.filter { $0.prerequisites.isEmpty })
        result.formUnion(started)

        // One step beyond anything you've started, so there's always a next.
        for movement in Movement.allCases
        where !movement.prerequisites.isEmpty
            && movement.prerequisites.allSatisfy({ started.contains($0) }) {
            result.insert(movement)
        }
        return result.sorted { ($0.difficulty, $0.displayName) < ($1.difficulty, $1.displayName) }
    }

    /// Hops from the centre, computed over the visible set only — a node
    /// whose parents aren't drawn hangs off the root instead.
    private var depths: [Movement: Int] {
        let shown = Set(visible)
        var result: [Movement: Int] = [:]

        for movement in visible {
            let parents = movement.prerequisites.filter { shown.contains($0) }
            result[movement] = parents.isEmpty ? 1 : 0
        }
        // Two passes settle everything at this size; the graph is shallow.
        for _ in 0..<4 {
            for movement in visible where result[movement] == 0 {
                let parents = movement.prerequisites.filter { shown.contains($0) }
                let known = parents.compactMap { result[$0] }.filter { $0 > 0 }
                if known.count == parents.count, let deepest = known.max() {
                    result[movement] = deepest + 1
                }
            }
        }
        // Anything still unresolved sits one ring out from its deepest parent.
        for movement in visible where result[movement] == 0 { result[movement] = 2 }
        return result
    }

    // MARK: - Layout

    private static let ringGap: CGFloat = 96
    private static let nodeSpread: CGFloat = 0.86

    private var maxDepth: Int { depths.values.max() ?? 1 }

    private var canvasRadius: CGFloat {
        CGFloat(maxDepth) * Self.ringGap + 70
    }

    private var canvasSize: CGFloat { canvasRadius * 2 }
    private var centre: CGPoint { CGPoint(x: canvasRadius, y: canvasRadius) }

    /// Even angular spacing within each ring, with each ring rotated slightly
    /// so nodes don't line up radially and collide with the edges.
    private var positions: [Movement: CGPoint] {
        var result: [Movement: CGPoint] = [:]
        let byRing = Dictionary(grouping: visible) { depths[$0] ?? 1 }

        for (ring, members) in byRing {
            let ordered = members.sorted {
                ($0.category.rawValue, $0.difficulty) < ($1.category.rawValue, $1.difficulty)
            }
            let count = max(1, ordered.count)
            let step = (2 * Double.pi) / Double(count)
            let rotation = Double(ring) * 0.42 - Double.pi / 2
            let radius = Double(ring) * Double(Self.ringGap) * Double(Self.nodeSpread)

            for (index, movement) in ordered.enumerated() {
                let angle = rotation + step * Double(index)
                result[movement] = CGPoint(
                    x: canvasRadius + CGFloat(cos(angle) * radius),
                    y: canvasRadius + CGFloat(sin(angle) * radius)
                )
            }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            map
            legend
            detail
        }
        .onAppear {
            withAnimation(Theme.Motion.expand.delay(0.05)) { appeared = true }
        }
    }

    private var map: some View {
        let places = positions

        return GeometryReader { proxy in
            ZStack {
                edges(places)
                root
                nodes(places)
            }
            .frame(width: canvasSize, height: canvasSize)
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
                            zoom = min(2.0, max(0.4, committedZoom * value.magnification))
                        }
                        .onEnded { _ in committedZoom = zoom }
                )
            )
            .onAppear { fit(in: proxy.size) }
        }
        .frame(height: 340)
        .background(Theme.Color.card.opacity(0.35), in: .rect(cornerRadius: Theme.Metric.cardRadius))
        .overlay(alignment: .topTrailing) { zoomControls }
    }

    /// Opens showing the whole tree rather than a corner of it — with only a
    /// handful of nodes there's no reason to make anyone hunt.
    private func fit(in size: CGSize) {
        let needed = canvasSize
        let scale = min(1.05, min(size.width, size.height) / max(needed, 1))
        zoom = scale
        committedZoom = scale
        let centred = CGSize(
            width: size.width / 2 - canvasRadius * scale,
            height: size.height / 2 - canvasRadius * scale
        )
        pan = centred
        committedPan = centred
    }

    private var zoomControls: some View {
        VStack(spacing: 6) {
            zoomButton("plus") { setZoom(zoom * 1.3) }
            zoomButton("minus") { setZoom(zoom / 1.3) }
        }
        .padding(10)
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
                .frame(width: 28, height: 28)
                .background(Theme.Color.elevated.opacity(0.9), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func setZoom(_ next: CGFloat) {
        withAnimation(Theme.Motion.selection) {
            zoom = min(2.0, max(0.4, next))
            committedZoom = zoom
        }
    }

    // MARK: - Canvas

    private func edges(_ places: [Movement: CGPoint]) -> some View {
        Canvas { context, _ in
            for movement in visible {
                guard let to = places[movement] else { continue }
                let parents = movement.prerequisites.filter { places[$0] != nil }

                if parents.isEmpty {
                    var path = Path()
                    path.move(to: centre)
                    path.addLine(to: to)
                    context.stroke(
                        path,
                        with: .color(Theme.Color.divider.opacity(0.6)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    continue
                }

                for parent in parents {
                    guard let from = places[parent] else { continue }
                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    let lit = started.contains(parent)
                    context.stroke(
                        path,
                        with: .color(lit
                                     ? Theme.Color.valid.opacity(0.55)
                                     : Theme.Color.divider.opacity(0.75)),
                        style: StrokeStyle(lineWidth: lit ? 2 : 1.4, lineCap: .round)
                    )
                }
            }
        }
        .frame(width: canvasSize, height: canvasSize)
    }

    private var root: some View {
        Circle()
            .fill(Theme.Color.primaryText)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: "figure.stand")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Color.background)
            }
            .position(centre)
    }

    private func nodes(_ places: [Movement: CGPoint]) -> some View {
        ForEach(visible) { movement in
            if let point = places[movement] {
                SkillNode(
                    movement: movement,
                    progress: progress(for: movement),
                    isNext: !started.contains(movement),
                    isSelected: selected == movement
                )
                .position(point)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.7)
                .animation(
                    Theme.Motion.expand.delay(Double(depths[movement] ?? 1) * 0.06),
                    value: appeared
                )
                .onTapGesture {
                    withAnimation(Theme.Motion.selection) {
                        selected = (selected == movement) ? nil : movement
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            key(Theme.Color.valid, "Started")
            key(Theme.Color.divider, "Next up")
            Spacer(minLength: 0)
            Text("\(visible.count) of \(Movement.allCases.count)")
                .cardLabelStyle()
        }
    }

    private func key(_ colour: SwiftUI.Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.tertiaryText)
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
                    Text("Not attempted yet. Nothing stops you starting here — record one and it joins the tree.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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

                if !leadsTo(movement).isEmpty {
                    Text("Leads to: " + leadsTo(movement).map(\.displayName).joined(separator: ", "))
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
            Text("Your tree grows as you train — record a movement and what it leads to appears. Tap a node for its numbers.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func leadsTo(_ movement: Movement) -> [Movement] {
        Movement.allCases.filter { $0.prerequisites.contains(movement) }
    }

    private func rank(for movement: Movement) -> String {
        switch progress(for: movement) {
        case 0:      "NEXT UP"
        case ..<0.5: "LEARNING"
        case ..<1:   "CLOSE"
        case ..<2:   "EARNED"
        default:     "MASTERED"
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
}

// MARK: - Node

private struct SkillNode: View {
    let movement: Movement
    let progress: Double
    /// Reachable but not yet attempted — drawn quieter, so what you've done
    /// reads first.
    let isNext: Bool
    let isSelected: Bool

    private var isEarned: Bool { progress >= 1 }
    private var isMastered: Bool { progress >= 2 }
    private var isStarted: Bool { progress > 0 }

    private var diameter: CGFloat {
        if isMastered { return 50 }
        if isEarned { return 44 }
        if isStarted { return 40 }
        return 32
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if isMastered {
                    Circle()
                        .fill(Theme.Color.valid.opacity(0.16))
                        .frame(width: diameter + 14, height: diameter + 14)
                }

                Circle()
                    .fill(isEarned ? Theme.Color.valid.opacity(0.18) : Theme.Color.card)
                    .frame(width: diameter, height: diameter)

                Circle()
                    .strokeBorder(
                        isStarted ? Theme.Color.valid.opacity(0.4) : Theme.Color.divider,
                        style: StrokeStyle(lineWidth: 2, dash: isNext ? [3, 3] : [])
                    )
                    .frame(width: diameter, height: diameter)

                if isStarted && !isEarned {
                    Circle()
                        .trim(from: 0, to: min(1, progress))
                        .stroke(Theme.Color.valid, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: diameter, height: diameter)
                }

                if isMastered {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.valid)
                } else if isEarned {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.valid)
                } else {
                    Text("\(movement.difficulty)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(isNext ? Theme.Color.tertiaryText : Theme.Color.primaryText)
                }
            }
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(Theme.Color.primaryText, lineWidth: 2)
                        .frame(width: diameter + 10, height: diameter + 10)
                }
            }

            Text(movement.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isNext ? Theme.Color.tertiaryText : Theme.Color.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 78)
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
