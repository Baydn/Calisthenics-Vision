//
//  PoseAnnotationView.swift
//  Calisthenics Vision
//
//  The other ways of looking at a frame: the line you're trying to hold, and
//  the angle the movement is judged at.
//
//  A skeleton shows where your joints are. It doesn't show what's *wrong* —
//  for that you need the shape you were aiming for drawn next to the shape
//  you made. That's all these two modes are:
//
//  · Alignment — the straight line between the ends of the chain, dashed,
//    with the real path through the middle drawn solid over it. The gap
//    between them is the pike or the sag, and it needs no number to read.
//  · Angle — the two limbs meeting at the judged joint, with the arc between
//    them and the measurement.
//
//  One caveat is written into the drawing rather than hidden: the arc is the
//  angle's *projection* into the picture, while the number beside it is
//  measured in 3D (POSE.md Law 1). Filmed end-on those two disagree, and the
//  number is the one that's right — which is exactly why the app measures in
//  world space and why no tracker reads angles off the image.
//

import SwiftUI

struct PoseAnnotationView: View {
    let pose: Pose?
    let movement: Movement
    let mode: ReviewOverlayMode
    var sourceAspect: CGFloat = 9.0 / 16.0
    var contentMode: ContentMode = .fit

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            let project = PoseOverlayView.transform(
                sourceAspect: sourceAspect, into: size, mode: contentMode
            )
            switch mode {
            case .line:  drawAlignment(pose, &context, project)
            case .angle: drawAngle(pose, &context, project)
            default:     break
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Alignment

    private func drawAlignment(
        _ pose: Pose,
        _ context: inout GraphicsContext,
        _ project: (CGPoint) -> CGPoint
    ) {
        guard let chain = movement.alignmentChain,
              let joints = visibleSide(pose, chain)
        else { return }

        let points = joints.compactMap { pose.point($0) }.map(project)
        guard points.count == joints.count, let first = points.first, let last = points.last
        else { return }

        let worst = worstBend(pose, joints)
        let tint = worst.map { bendColor($0.degrees) } ?? Theme.Color.primaryText

        // The line you were aiming for.
        //
        // For anything held against gravity that's a plumb line through the
        // base of support — your hands in a handstand, the bar in a hang.
        // Straight but leaning is still a fault, and only a vertical
        // reference shows it. For a push-up, whose line is horizontal, a
        // vertical reference would mean nothing, so it runs end to end.
        var ideal = Path()
        switch movement.idealLine {
        case .vertical:
            // Spans the body rather than stopping at the joints, so it reads
            // as a reference line and not as another limb.
            let ys = points.map(\.y)
            let top = ys.min() ?? first.y
            let bottom = ys.max() ?? first.y
            let margin = (bottom - top) * 0.06
            ideal.move(to: CGPoint(x: first.x, y: top - margin))
            ideal.addLine(to: CGPoint(x: first.x, y: bottom + margin))
        case .horizontal:
            // The same idea laid flat: level through the shoulders, so a
            // planche whose hips ride high shows the body climbing off it.
            let xs = points.map(\.x)
            let leading = xs.min() ?? first.x
            let trailing = xs.max() ?? first.x
            let margin = (trailing - leading) * 0.06
            ideal.move(to: CGPoint(x: leading - margin, y: first.y))
            ideal.addLine(to: CGPoint(x: trailing + margin, y: first.y))
        case .endToEnd:
            ideal.move(to: first)
            ideal.addLine(to: last)
        }
        context.stroke(
            ideal,
            with: .color(.black.opacity(0.45)),
            style: StrokeStyle(lineWidth: 5, lineCap: .round)
        )
        context.stroke(
            ideal,
            with: .color(Theme.Color.primaryText.opacity(0.85)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 7])
        )

        // The line you actually made.
        var actual = Path()
        actual.addLines(points)
        context.stroke(
            actual,
            with: .color(.black.opacity(0.45)),
            style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            actual,
            with: .color(tint),
            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        )

        for (index, point) in points.enumerated() {
            let isEnd = index == 0 || index == points.count - 1
            let radius: CGFloat = isEnd ? 5 : 6
            context.fill(dot(point, radius + 1.5), with: .color(.black.opacity(0.5)))
            context.fill(
                dot(point, radius),
                with: .color(isEnd ? Theme.Color.primaryText : tint)
            )
        }

        // Name the worst bend rather than scoring the whole line: "your hip is
        // at 156°" is something you can go and fix, while a percentage isn't.
        if let worst {
            let index = joints.firstIndex(of: worst.joint) ?? 1
            label(
                "\(worst.joint.shortName) \(Int(worst.degrees.rounded()))°",
                at: points[min(index, points.count - 1)],
                tint: tint,
                in: &context
            )
        }
    }

    /// The interior angle at each middle joint of the chain, worst first.
    /// 180° is straight; the further below, the bigger the pike or sag.
    private func worstBend(
        _ pose: Pose, _ joints: [PoseJoint]
    ) -> (joint: PoseJoint, degrees: Double)? {
        guard joints.count >= 3 else { return nil }
        var worst: (PoseJoint, Double)?
        for index in 1..<(joints.count - 1) {
            guard let degrees = pose.angle(
                at: joints[index], from: joints[index - 1], to: joints[index + 1]
            ) else { continue }
            if worst == nil || degrees < worst!.1 { worst = (joints[index], degrees) }
        }
        return worst.map { (joint: $0.0, degrees: $0.1) }
    }

    /// Same three-step scale the angle charts band with, so a line that reads
    /// amber here is in the amber band there.
    private func bendColor(_ degrees: Double) -> SwiftUI.Color {
        switch 180 - degrees {
        case ..<12:  Theme.Color.valid
        case ..<30:  Theme.Color.caution
        default:     Theme.Color.warning
        }
    }

    // MARK: - Angle

    private func drawAngle(
        _ pose: Pose,
        _ context: inout GraphicsContext,
        _ project: (CGPoint) -> CGPoint
    ) {
        guard let focus = movement.focusAngle,
              let near = visibleSide(pose, [focus.vertex, focus.from, focus.to])
        else { return }

        // **Both sides, not one.** On a bilateral movement the difference
        // between them is itself the thing worth looking at — one elbow
        // flaring, or giving out before the other, is invisible if only the
        // near arm is ever drawn (Baydon, 2026-09-09). The far side is drawn
        // lighter: it projects inside the body, so at equal weight it fights
        // the near one for attention rather than adding to it.
        let far = near.map(\.mirrored)
        let nearReading = drawArc(pose, near, emphasised: true, &context, project)
        let farReading = drawArc(pose, far, emphasised: false, &context, project)

        guard let nearReading else { return }

        // One label carrying both numbers. Filmed side-on the two arcs land
        // almost on top of each other, and two labels there would overlap
        // into nonsense.
        let text: String
        if let farReading, abs(farReading.degrees - nearReading.degrees) >= 1 {
            let nearIsLeft = near[0] == focus.vertex
            let left = nearIsLeft ? nearReading.degrees : farReading.degrees
            let right = nearIsLeft ? farReading.degrees : nearReading.degrees
            text = "\(focus.label) L \(Int(left.rounded()))° · R \(Int(right.rounded()))°"
        } else {
            text = "\(focus.label) \(Int(nearReading.degrees.rounded()))°"
        }
        label(text, at: nearReading.anchor, tint: tint(pose), in: &context)
    }

    /// Draws one side's limbs and arc, and reports where its label would go
    /// and what it measured. Nil when that side isn't in the frame.
    private func drawArc(
        _ pose: Pose,
        _ joints: [PoseJoint],
        emphasised: Bool,
        _ context: inout GraphicsContext,
        _ project: (CGPoint) -> CGPoint
    ) -> (anchor: CGPoint, degrees: Double)? {
        guard let rawVertex = pose.point(joints[0]),
              let rawFrom = pose.point(joints[1]),
              let rawTo = pose.point(joints[2])
        else { return nil }

        let vertex = project(rawVertex)
        let from = project(rawFrom)
        let to = project(rawTo)
        let weight: CGFloat = emphasised ? 1 : 0.55
        let fade: Double = emphasised ? 1 : 0.5

        // The two limbs that make the angle, drawn heavy so the rest of the
        // body reads as context.
        var limbs = Path()
        limbs.move(to: from)
        limbs.addLine(to: vertex)
        limbs.addLine(to: to)
        context.stroke(
            limbs,
            with: .color(.black.opacity(0.5 * fade)),
            style: StrokeStyle(lineWidth: 8 * weight, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            limbs,
            with: .color(tint(pose).opacity(fade)),
            style: StrokeStyle(lineWidth: 4.5 * weight, lineCap: .round, lineJoin: .round)
        )

        for point in [from, to] {
            context.fill(dot(point, 6.5 * weight), with: .color(.black.opacity(0.5 * fade)))
            context.fill(dot(point, 5 * weight), with: .color(Theme.Color.primaryText.opacity(fade)))
        }
        context.fill(dot(vertex, 7.5 * weight), with: .color(.black.opacity(0.5 * fade)))
        context.fill(dot(vertex, 6 * weight), with: .color(Theme.Color.primaryText.opacity(fade)))

        // The arc, swept between the two limbs. Built by sampling rather than
        // with addArc so there's no ambiguity about which way round it goes —
        // it always takes the short way, which is the interior angle.
        let startAngle = atan2(from.y - vertex.y, from.x - vertex.x)
        var sweep = atan2(to.y - vertex.y, to.x - vertex.x) - startAngle
        while sweep > .pi { sweep -= 2 * .pi }
        while sweep < -.pi { sweep += 2 * .pi }

        let reach = min(distance(vertex, from), distance(vertex, to))
        let radius = max(18, reach * 0.34)

        var arc = Path()
        let steps = 24
        for step in 0...steps {
            let angle = startAngle + sweep * Double(step) / Double(steps)
            let point = CGPoint(
                x: vertex.x + cos(angle) * radius,
                y: vertex.y + sin(angle) * radius
            )
            step == 0 ? arc.move(to: point) : arc.addLine(to: point)
        }
        context.stroke(
            arc,
            with: .color(.black.opacity(0.45 * fade)),
            style: StrokeStyle(lineWidth: 5 * weight)
        )
        context.stroke(
            arc,
            with: .color(tint(pose).opacity(fade)),
            style: StrokeStyle(lineWidth: 2.5 * weight)
        )

        // The measurement is the 3D one, even though the arc is a projection.
        guard let degrees = pose.angle(at: joints[0], from: joints[1], to: joints[2]) else {
            return nil
        }
        let midAngle = startAngle + sweep / 2
        let anchor = CGPoint(
            x: vertex.x + cos(midAngle) * (radius + 26),
            y: vertex.y + sin(midAngle) * (radius + 26)
        )
        return (anchor, degrees)
    }

    /// Green / amber / red where the movement has bands worth grading against,
    /// white where the angle is a phase rather than a fault.
    private func tint(_ pose: Pose) -> SwiftUI.Color {
        guard let focus = movement.focusAngle,
              let zones = AngleBands.focusZones(for: movement),
              let joints = visibleSide(pose, [focus.vertex, focus.from, focus.to]),
              let degrees = pose.angle(at: joints[0], from: joints[1], to: joints[2]),
              let zone = zones.first(where: { $0.contains(degrees) })
        else { return Theme.Color.primaryText }

        switch zone.tone {
        case .good:    return Theme.Color.valid
        case .fair:    return Theme.Color.caution
        case .poor:    return Theme.Color.warning
        case .neutral: return Theme.Color.primaryText
        }
    }

    // MARK: - Shared

    /// The side of the body worth drawing.
    ///
    /// Review telemetry carries no confidence — every landmark reads as
    /// certain — so the usable signal is geometry: the side facing the camera
    /// projects to longer limbs, while the far side foreshortens. Drawing the
    /// far one puts the annotation inside the body.
    private func visibleSide(_ pose: Pose, _ joints: [PoseJoint]) -> [PoseJoint]? {
        let mirror = joints.map(\.mirrored)

        func spread(_ side: [PoseJoint]) -> CGFloat? {
            let points = side.compactMap { pose.point($0) }
            guard points.count == side.count else { return nil }
            return zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
        }

        switch (spread(joints), spread(mirror)) {
        case let (near?, far?): return near >= far ? joints : mirror
        case (_?, nil):         return joints
        case (nil, _?):         return mirror
        case (nil, nil):        return nil
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    private func dot(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
        ))
    }

    /// A reading in a dark pill, so it stays legible over a bright gym floor.
    private func label(
        _ text: String, at point: CGPoint, tint: SwiftUI.Color, in context: inout GraphicsContext
    ) {
        let resolved = context.resolve(
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        )
        let size = resolved.measure(in: CGSize(width: 200, height: 40))
        let box = CGRect(
            x: point.x - size.width / 2 - 8,
            y: point.y - size.height / 2 - 5,
            width: size.width + 16,
            height: size.height + 10
        )
        context.fill(Path(roundedRect: box, cornerRadius: box.height / 2),
                     with: .color(.black.opacity(0.62)))
        context.draw(resolved, at: point, anchor: .center)
    }
}
