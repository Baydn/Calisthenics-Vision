//
//  MovementGlyph.swift
//  Calisthenics Vision
//
//  Draws a movement as a stick figure, from joint angles rather than an asset.
//
//  Why not SF Symbols: Apple's `figure.*` family covers workout *types* —
//  running, HIIT, yoga — not gymnastic positions. There is no symbol for an
//  L-sit, a front lever or a pistol squat, so every movement in a category was
//  sharing one glyph and the picture said nothing. Why not an icon pack:
//  nothing off the shelf covers this catalogue, and a licensed set wouldn't
//  match a monochrome app that already draws skeletons over video.
//
//  So the figure is drawn from the same kind of description the trackers
//  measure — bones of fixed length at given angles. That buys three things an
//  image can't: it can never be drawn with a limb the wrong length, it is
//  sharp at any size from a 24pt row tile to a full-width header, and it takes
//  its colour from the surrounding UI like any other glyph.
//
//  Poses live in MovementGlyphData.swift.
//

import SwiftUI

struct MovementGlyph {

    /// A two-bone limb, as the absolute angle of each bone.
    struct Limb {
        let upper: Double
        let lower: Double
        init(_ upper: Double, _ lower: Double) { self.upper = upper; self.lower = lower }
    }

    /// Apparatus drawn behind the figure. A hanging body with no bar above it
    /// simply doesn't read as a pull-up, so the equipment is part of the glyph.
    enum Prop {
        case none
        case floor
        case bar(y: Double, x1: Double, x2: Double)
        case rig(y: Double, x1: Double, x2: Double)
        case dipBars(y: Double)
        case wall(x: Double)
        case pole(x: Double)
        case bench(x1: Double, y1: Double, x2: Double, y2: Double)
        case blocks(y: Double)
    }

    let hip: CGPoint
    let spine: Double
    let armNear: Limb
    let armFar: Limb
    let legNear: Limb
    let legFar: Limb
    /// Lifts the head off the spine line — a neck, and what keeps the head
    /// from merging into the torso in prone poses.
    let headOffset: CGSize
    /// How far the far side sits from the near side. A small offset reads as a
    /// body seen from the side; a wide one as a body seen face-on, which is
    /// how the pulls are drawn (their elbows flex in the frontal plane).
    let depth: CGSize
    let hipDepth: CGSize
    let prop: Prop

    /// Human proportions, in the glyph's own 100×100 space.
    enum Bone {
        static let upperArm = 14.0, forearm = 13.0
        static let spine = 24.0, headGap = 10.0, headRadius = 6.4
        static let thigh = 18.0, shin = 18.0
    }

    /// The figure's joints, resolved. One torso, two arms, two legs.
    struct Figure {
        var head: CGPoint
        var torso: [CGPoint]
        var armNear: [CGPoint], armFar: [CGPoint]
        var legNear: [CGPoint], legFar: [CGPoint]

        var all: [CGPoint] { torso + armNear + armFar + legNear + legFar }
    }

    var figure: Figure {
        let dir = Self.polar(spine)
        let shoulder = CGPoint(x: hip.x + dir.dx * Bone.spine, y: hip.y + dir.dy * Bone.spine)
        let head = CGPoint(
            x: shoulder.x + dir.dx * Bone.headGap + headOffset.width,
            y: shoulder.y + dir.dy * Bone.headGap + headOffset.height
        )
        func offset(_ p: CGPoint, _ d: CGSize, _ s: Double) -> CGPoint {
            CGPoint(x: p.x + d.width * s, y: p.y + d.height * s)
        }
        func chain(_ root: CGPoint, _ limb: Limb, _ l1: Double, _ l2: Double) -> [CGPoint] {
            let a = Self.polar(limb.upper), b = Self.polar(limb.lower)
            let joint = CGPoint(x: root.x + a.dx * l1, y: root.y + a.dy * l1)
            return [root, joint, CGPoint(x: joint.x + b.dx * l2, y: joint.y + b.dy * l2)]
        }
        return Figure(
            head: head,
            torso: [shoulder, hip],
            armNear: chain(offset(shoulder, depth, -0.5), armNear, Bone.upperArm, Bone.forearm),
            armFar:  chain(offset(shoulder, depth,  0.5), armFar,  Bone.upperArm, Bone.forearm),
            legNear: chain(offset(hip, hipDepth, -0.5), legNear, Bone.thigh, Bone.shin),
            legFar:  chain(offset(hip, hipDepth,  0.5), legFar,  Bone.thigh, Bone.shin)
        )
    }

    private static func polar(_ degrees: Double) -> CGVector {
        let r = degrees * .pi / 180
        return CGVector(dx: cos(r), dy: sin(r))
    }

    /// Maps the glyph's own space into a view, sized so the figure fills it.
    ///
    /// Poses occupy very different footprints — a hang is a narrow column, a
    /// planche a horizontal bar — so a single fixed scale would waste most of
    /// the frame for some and crop others.
    func transform(into size: CGSize, padding: CGFloat) -> (scale: CGFloat, offset: CGPoint) {
        let f = figure
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for p in f.all {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let r = Bone.headRadius + 1.5
        minX = min(minX, f.head.x - r); maxX = max(maxX, f.head.x + r)
        minY = min(minY, f.head.y - r); maxY = max(maxY, f.head.y + r)

        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let usableW = Double(size.width) - Double(padding) * 2
        let usableH = Double(size.height) - Double(padding) * 2
        let scale = min(usableW / w, usableH / h)
        return (CGFloat(scale), CGPoint(
            x: (Double(size.width) - w * scale) / 2 - minX * scale,
            y: (Double(size.height) - h * scale) / 2 - minY * scale
        ))
    }
}

// MARK: - View

/// A movement drawn as a figure, at any size.
struct MovementGlyphView: View {
    let movement: Movement
    var tint: Color = Theme.Color.primaryText
    /// The surface behind the glyph. Near limbs are stroked with it underneath
    /// so that where limbs cross they read as separate rather than merging.
    var background: Color = Theme.Color.card
    /// Stroke weight relative to the drawing. Small tiles need a relatively
    /// heavier line to survive.
    var weight: CGFloat = 3.6
    var showsProp = true
    var padding: CGFloat = 9

    var body: some View {
        if let glyph = MovementGlyph.poses[movement] {
            Canvas { context, size in
                let (scale, origin) = glyph.transform(into: size, padding: padding)
                func map(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
                }
                let line = weight * scale
                let figure = glyph.figure

                if showsProp {
                    var prop = Path()
                    Self.appendProp(glyph.prop, to: &prop)
                    context.stroke(
                        prop.applying(CGAffineTransform(translationX: origin.x, y: origin.y)
                            .scaledBy(x: scale, y: scale)),
                        with: .color(tint.opacity(0.28)),
                        style: StrokeStyle(lineWidth: max(line * 0.42, 0.7), lineCap: .round)
                    )
                }

                // Far side first, then the single torso, then the near side
                // over the top — painter's order is what gives the figure depth.
                context.opacity = 0.4
                stroke(&context, [figure.legFar, figure.armFar], map, line, tint, nil)
                context.opacity = 1

                stroke(&context, [figure.torso, figure.legNear], map, line, tint, background)

                let head = map(figure.head)
                let radius = (MovementGlyph.Bone.headRadius * 0.97) * scale
                let ring = radius + line * 0.62
                context.fill(Path(ellipseIn: CGRect(
                    x: head.x - ring, y: head.y - ring, width: ring * 2, height: ring * 2)),
                    with: .color(background))
                context.fill(Path(ellipseIn: CGRect(
                    x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(tint))

                stroke(&context, [figure.armNear], map, line, tint, background)
            }
            .accessibilityHidden(true)
        } else {
            // No pose drawn for this movement yet: show its category symbol
            // rather than an invented picture.
            Image(systemName: movement.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func stroke(
        _ context: inout GraphicsContext, _ chains: [[CGPoint]],
        _ map: (CGPoint) -> CGPoint, _ line: CGFloat,
        _ color: Color, _ casing: Color?
    ) {
        var path = Path()
        for chain in chains {
            guard let first = chain.first else { continue }
            path.move(to: map(first))
            for p in chain.dropFirst() { path.addLine(to: map(p)) }
        }
        if let casing {
            context.stroke(path, with: .color(casing),
                           style: StrokeStyle(lineWidth: line * 1.9, lineCap: .round, lineJoin: .round))
        }
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
    }

    private static func appendProp(_ prop: MovementGlyph.Prop, to path: inout Path) {
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
        }
        func floor() { line(-40, 88, 140, 88) }
        switch prop {
        case .none: break
        case .floor: floor()
        case let .bar(y, x1, x2):
            line(x1, y, x2, y); line(x1 + 2, y, x1 + 2, y - 9); line(x2 - 2, y, x2 - 2, y - 9)
        case let .rig(y, x1, x2):
            line(x1, y, x2, y); line(x1 + 3, y, x1 + 3, 88); line(x2 - 3, y, x2 - 3, 88); floor()
        case let .dipBars(y):
            line(26, y, 84, y); line(30, y - 3.5, 88, y - 3.5); line(80, y, 80, 88); floor()
        case let .wall(x): line(x, -40, x, 88); floor()
        case let .pole(x): line(x, -40, x, 140); floor()
        case let .bench(x1, y1, x2, y2):
            path.addRoundedRect(in: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1),
                                cornerSize: CGSize(width: 1.5, height: 1.5))
            floor()
        case let .blocks(y):
            path.addRoundedRect(in: CGRect(x: 38, y: y, width: 12, height: 4),
                                cornerSize: CGSize(width: 1.5, height: 1.5))
            path.addRoundedRect(in: CGRect(x: 30, y: y + 2, width: 12, height: 4),
                                cornerSize: CGSize(width: 1.5, height: 1.5))
            floor()
        }
    }
}
