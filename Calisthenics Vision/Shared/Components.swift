//
//  Components.swift
//  Calisthenics Vision
//
//  Reusable pieces shared across screens, built to the Figma spec.
//

import SwiftUI

// MARK: - Stat card

/// The three-up row at the top of History: a bold number over an
/// uppercase label, on a dark rounded card.
struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(Theme.Font.cardNumber())
                .foregroundStyle(Theme.Color.primaryText)
            Text(label)
                .cardLabelStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(height: Theme.Metric.cardHeight)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }
}

// MARK: - Segmented control

/// Full-width pill track with a white pill marking the active segment.
struct SegmentedControl<Segment: Hashable>: View {
    let segments: [Segment]
    let title: (Segment) -> String
    @Binding var selection: Segment

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.self) { segment in
                let isActive = segment == selection

                Text(title(segment))
                    .font(isActive ? Theme.Font.controlActive() : Theme.Font.control())
                    .foregroundStyle(isActive ? Theme.Color.background : Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metric.segmentedHeight)
                    .background {
                        if isActive {
                            Capsule()
                                .fill(Theme.Color.primaryText)
                                .matchedGeometryEffect(id: "activeSegment", in: pill)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.25)) { selection = segment }
                    }
            }
        }
        .background(Theme.Color.card, in: .capsule)
    }
}

// MARK: - Filter chip

/// Pill used for the movement filter row on the Progress tab.
struct FilterChip: View {
    let title: String
    let isActive: Bool
    /// Tightened on screens that need to fit four chips across (Train).
    var horizontalPadding: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isActive ? Theme.Font.controlActive() : Theme.Font.control())
                .foregroundStyle(isActive ? Theme.Color.background : Theme.Color.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, horizontalPadding)
                .frame(height: 32)
                .background(isActive ? Theme.Color.primaryText : Theme.Color.card, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Movement icon

/// 28×28 dark circle with a white glyph, used on session rows.
struct MovementIcon: View {
    let movement: Movement

    var body: some View {
        Circle()
            .fill(Theme.Color.card)
            .frame(width: Theme.Metric.rowIconSize, height: Theme.Metric.rowIconSize)
            .overlay {
                Image(systemName: movement.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
            }
    }
}

// MARK: - Session row

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            MovementIcon(movement: session.movement)

            Text("\(session.movement.displayName)  ·  \(session.timeLabel)")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.primaryText)

            Spacer(minLength: 8)

            Text(session.result.displayValue)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .frame(height: 40)
        .contentShape(.rect)
    }
}

// MARK: - Primary button

/// White pill with black bold text — the primary CTA (see Paywall).
struct PrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.Color.background)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.Color.primaryText, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen header

struct ScreenHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Font.header())
            .foregroundStyle(Theme.Color.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
