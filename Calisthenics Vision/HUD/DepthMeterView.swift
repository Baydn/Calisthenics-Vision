//
//  DepthMeterView.swift
//  Calisthenics Vision
//
//  Live depth readout for the movements the state machine gates on depth
//  (Movement.tunesRepDepth). The bar runs from full extension at the top to
//  the floor at the bottom and fills downward as you descend, so it moves the
//  way your body does. The line across it is the depth the rep starts
//  counting at, read straight off the tracker's own gate.
//
//  What the scale means, and why it's fixed rather than personal, is in
//  `DepthGauge` — the short version is that a bar whose ends move with your
//  own range changes meaning mid-set and can't be read.
//
//  Two deliberate silences. The meter dims to an empty track when the tracker
//  isn't judging you, rather than holding the last value it saw — a frozen
//  gauge reads as a live one, which is the same lie the skeleton's faded
//  state exists to avoid. And there is no line at all until the tracker knows
//  your range: drawing the pre-calibration seed put it at the very bottom of
//  the bar, where it then jumped as soon as a real rep landed.
//
//  Not animated: this tracks pose data at capture frame rate, and easing it
//  would put the bar behind the body it's meant to be read against.
//

import SwiftUI

struct DepthMeterView: View {
    /// What the tracker is reading, or nil when it isn't judging you.
    var gauge: DepthGauge?
    var height: CGFloat = 280

    private let width: CGFloat = 18

    var body: some View {
        VStack(spacing: 10) {
            Text("DEPTH")
                .font(.system(size: 10, weight: .bold))
                .tracking(Theme.Metric.labelTracking)
                .foregroundStyle(Theme.Color.secondaryText)
                .shadow(color: .black.opacity(0.6), radius: 4)

            ZStack(alignment: gauge?.risesOnScreen == true ? .bottom : .top) {
                Rectangle()
                    .fill(.black.opacity(0.4))

                if let gauge {
                    Rectangle()
                        .fill(gauge.hasReachedGate
                              ? Theme.Color.valid
                              : Theme.Color.primaryText.opacity(0.92))
                        .frame(height: height * min(1, max(0, gauge.depth)))
                }
            }
            .frame(width: width, height: height)
            .overlay(alignment: .top) { gateLine }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.Color.primaryText.opacity(0.3), lineWidth: 1))
            .opacity(gauge == nil ? 0.45 : 1)

            // Said out loud rather than implied by a missing line: the first
            // rep is what teaches the tracker how far you go.
            if gauge != nil && gauge?.countsAt == nil {
                Text("1ST REP")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(Theme.Metric.labelTracking)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .shadow(color: .black.opacity(0.6), radius: 4)
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 6)
    }

    /// Where the rep starts counting. Drawn white over a dark halo, the same
    /// way the skeleton is, so it stays legible against both the filled and
    /// the empty half of the bar.
    @ViewBuilder
    private var gateLine: some View {
        if let gauge, let countsAt = gauge.countsAt {
            let fromTop = gauge.risesOnScreen ? 1 - countsAt : countsAt
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .frame(height: 5)
                Rectangle()
                    .fill(Theme.Color.primaryText)
                    .frame(height: 2.5)
            }
            .frame(width: width)
            .offset(y: height * min(1, max(0, fromTop)) - 2.5)
        }
    }
}

#Preview {
    HStack(spacing: 44) {
        DepthMeterView(gauge: DepthGauge(depth: 0.2, countsAt: 0.56))
        DepthMeterView(gauge: DepthGauge(depth: 0.8, countsAt: 0.56))
        DepthMeterView(gauge: DepthGauge(depth: 0.35, countsAt: nil))
        DepthMeterView(gauge: DepthGauge(depth: 0.7, countsAt: 0.58, risesOnScreen: true))
        DepthMeterView(gauge: nil)
    }
    .padding(40)
    .background(Theme.Color.background)
}
