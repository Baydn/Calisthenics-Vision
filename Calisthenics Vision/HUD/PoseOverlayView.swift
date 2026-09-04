//
//  PoseOverlayView.swift
//  Calisthenics Vision
//
//  Draws the pose skeleton over the camera preview (SPEC.md §1).
//
//  The skeleton says two things and no more: whether the movement is being
//  judged right now (solid vs faded) and whether form has broken (red).
//  PoseOverlayStyle.swift explains why it stopped being green by default.
//

import SwiftUI

struct PoseOverlayView: View {
    let pose: Pose?
    /// Red once a form break is live. Never means "not counting".
    var isFormValid = true
    /// Whether the body is in a position this movement is actually judged
    /// from — inverted for a handstand, horizontal for a push-up. The
    /// skeleton fades out while this is false, which is how you can tell
    /// across the room that the app has picked up the movement and not just
    /// picked up a person.
    var isEngaged = true
    var style: PoseOverlayStyle = .outline
    /// Width ÷ height of the source frames, used to undo the preview's
    /// aspect-fill crop so landmarks land on the body rather than beside it.
    var sourceAspect: CGFloat = 9.0 / 16.0

    /// Must match how the video underneath is laid out: the live preview fills
    /// (`.resizeAspectFill`), while review letterboxes (`.resizeAspect`). Get
    /// this wrong and the skeleton sits beside the body instead of on it.
    var contentMode: ContentMode = .fill

    /// Scales the whole drawing, so a thumbnail-sized swatch gets
    /// proportionate bones rather than a full-thickness scribble.
    var scale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            guard let pose, style.drawsSkeleton else { return }

            let color = isFormValid ? style.restingColor : Theme.Color.warning
            let transform = Self.transform(sourceAspect: sourceAspect, into: size, mode: contentMode)

            var path = Path()
            for (start, end) in Pose.connections {
                guard let a = pose.point(start), let b = pose.point(end) else { continue }
                path.move(to: transform(a))
                path.addLine(to: transform(b))
            }

            // The halo goes down first and wider, so the bones keep their
            // edge against a white wall or a sunlit floor.
            if style.drawsHalo {
                context.stroke(
                    path,
                    with: .color(.black.opacity(0.5)),
                    style: StrokeStyle(
                        lineWidth: (style.boneWidth + 2.4) * scale,
                        lineCap: .round, lineJoin: .round
                    )
                )
            }

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: style.boneWidth * scale,
                    lineCap: .round, lineJoin: .round
                )
            )

            guard style.drawsJoints else { return }
            let radius = style.jointRadius * scale
            for joint in PoseJoint.allCases {
                guard let point = pose.point(joint) else { continue }
                let center = transform(point)

                if style.drawsHalo {
                    context.fill(Self.dot(at: center, radius: radius + 1.2),
                                 with: .color(.black.opacity(0.5)))
                }
                context.fill(Self.dot(at: center, radius: radius), with: .color(color))
            }
        }
        // Faded until the movement is actually being judged. Animated rather
        // than switched, so the transition reads as the app locking on.
        .opacity(isEngaged ? 1 : style.idleOpacity)
        .animation(Theme.Motion.content, value: isEngaged)
        .animation(Theme.Motion.content, value: isFormValid)
        .allowsHitTesting(false)
    }

    private static func dot(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
    }

    /// Maps normalized (0…1) landmark coordinates into view space exactly the
    /// way the video underneath is laid out — cover and centre the overflow for
    /// `.fill`, contain and centre the letterbox for `.fit`. Without matching
    /// this the skeleton drifts off the body on any view whose aspect ratio
    /// differs from the source.
    static func transform(
        sourceAspect: CGFloat,
        into size: CGSize,
        mode: ContentMode = .fill
    ) -> (CGPoint) -> CGPoint {
        let viewAspect = size.width / max(size.height, 1)
        let sourceIsWider = sourceAspect > viewAspect

        var drawWidth = size.width
        var drawHeight = size.height

        // Fill matches the wider dimension; fit matches the narrower one.
        let matchHeight = mode == .fill ? sourceIsWider : !sourceIsWider
        if matchHeight {
            drawWidth = size.height * sourceAspect
        } else {
            drawHeight = size.width / max(sourceAspect, 0.0001)
        }

        let offsetX = (size.width - drawWidth) / 2
        let offsetY = (size.height - drawHeight) / 2

        return { point in
            CGPoint(
                x: offsetX + point.x * drawWidth,
                y: offsetY + point.y * drawHeight
            )
        }
    }
}

#Preview {
    HStack(spacing: 0) {
        ForEach(PoseOverlayStyle.allCases) { style in
            VStack {
                PoseOverlayView(
                    pose: .mannequin,
                    style: style,
                    sourceAspect: 0.7,
                    contentMode: .fit
                )
                .frame(width: 80, height: 114)
                Text(style.title).font(Theme.Font.control())
            }
        }
    }
    .foregroundStyle(Theme.Color.primaryText)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Color.card)
}
