//
//  DepthMeterView.swift
//  Calisthenics Vision
//
//  Live depth readout for the movements the state machine gates on depth
//  (push-ups, dips, pull-ups, squats — Movement.tunesRepDepth). The bar fills
//  the way the body actually moves: empty at full extension, full at maximum
//  depth, growing downward as you go down. The tick marks the one number this
//  whole thing exists to answer — how far you actually have to go for the rep
//  to count — read straight off the tracker's own gate rather than guessed at
//  separately, so it can never disagree with what gets counted.
//
//  Deliberately not animated: this tracks live pose data at capture frame
//  rate, and easing it would make the gauge lag behind the body it's meant to
//  be read against in real time.
//

import SwiftUI

struct DepthMeterView: View {
    /// 0 at full extension (lockout / standing / hang), 1 at maximum depth.
    var progress: Double
    /// Fraction of `progress` at or beyond which the rep in progress will
    /// count. Nil while the tracker hasn't calibrated enough to know yet.
    var gateProgress: Double?

    private let width: CGFloat = 10
    private let height: CGFloat = 190

    var body: some View {
        VStack(spacing: 8) {
            Text("DEPTH")
                .font(.system(size: 10, weight: .bold))
                .tracking(Theme.Metric.labelTracking)
                .foregroundStyle(Theme.Color.secondaryText)
                .shadow(color: .black.opacity(0.6), radius: 4)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.black.opacity(0.35))

                Rectangle()
                    .fill(hasReachedGate ? Theme.Color.valid : Theme.Color.primaryText.opacity(0.9))
                    .frame(height: height * clamped)

                if let gateProgress {
                    Rectangle()
                        .fill(Theme.Color.primaryText.opacity(0.85))
                        .frame(height: 2)
                        .offset(y: height * gateProgress)
                }
            }
            .frame(width: width, height: height)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.Color.primaryText.opacity(0.25), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.4), radius: 6)
    }

    private var clamped: Double { min(1, max(0, progress)) }

    private var hasReachedGate: Bool {
        guard let gateProgress else { return false }
        return clamped >= gateProgress
    }
}

#Preview {
    HStack(spacing: 40) {
        DepthMeterView(progress: 0.15, gateProgress: 0.58)
        DepthMeterView(progress: 0.7, gateProgress: 0.58)
        DepthMeterView(progress: 0.3, gateProgress: nil)
    }
    .padding(40)
    .background(Theme.Color.background)
}
