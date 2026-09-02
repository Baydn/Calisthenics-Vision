//
//  PoseOverlayView.swift
//  Calisthenics Vision
//
//  Draws the pose skeleton over the camera preview (SPEC.md §1).
//

import SwiftUI

struct PoseOverlayView: View {
    let pose: Pose?
    /// Green for valid form, red once a form break is detected.
    var isFormValid = true
    /// Width ÷ height of the source frames, used to undo the preview's
    /// aspect-fill crop so landmarks land on the body rather than beside it.
    var sourceAspect: CGFloat = 9.0 / 16.0

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }

            let color = isFormValid ? Theme.Color.valid : Theme.Color.warning
            let transform = Self.aspectFillTransform(sourceAspect: sourceAspect, into: size)

            // Bones
            var path = Path()
            for (start, end) in Pose.connections {
                guard let a = pose.point(start), let b = pose.point(end) else { continue }
                path.move(to: transform(a))
                path.addLine(to: transform(b))
            }
            context.stroke(
                path,
                with: .color(color.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Joints
            for joint in PoseJoint.allCases {
                guard let point = pose.point(joint) else { continue }
                let center = transform(point)
                let dot = Path(ellipseIn: CGRect(
                    x: center.x - 3, y: center.y - 3, width: 6, height: 6
                ))
                context.fill(dot, with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }

    /// Maps normalized (0…1) landmark coordinates into view space the same way
    /// `.resizeAspectFill` scales the preview — scale to cover, then centre the
    /// overflow. Without this the skeleton drifts off the body on any view
    /// whose aspect ratio differs from the camera's.
    static func aspectFillTransform(
        sourceAspect: CGFloat,
        into size: CGSize
    ) -> (CGPoint) -> CGPoint {
        let viewAspect = size.width / max(size.height, 1)

        var drawWidth = size.width
        var drawHeight = size.height

        if sourceAspect > viewAspect {
            // Source is wider: fill height, overflow horizontally.
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
