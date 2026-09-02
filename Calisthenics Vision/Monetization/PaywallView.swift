//
//  PaywallView.swift
//  Calisthenics Vision
//
//  Frame 07 — Unlock Pro.
//

import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    private let features = [
        "Planche, Pull-Up & Muscle-Up tracking",
        "Tempo analytics per rep",
        "Real-time audio coaching",
        "Long-term progression graphs",
        "Cloud sync across devices",
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.Color.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("Unlock Pro")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .padding(.top, 72)

                Text("Advanced movements, tempo analytics, and real-time coaching.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.Color.primaryText)
                            Text(feature)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.Color.primaryText)
                        }
                    }
                }
                .padding(.top, 40)

                Spacer(minLength: 24)

                priceCard
                    .padding(.bottom, 16)

                PrimaryButton(title: "Start Free Trial") {
                    entitlements.purchasePro()
                    dismiss()
                }

                Text("Cancel anytime. Auto-renews unless cancelled.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, Theme.Metric.screenPadding)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(Theme.Color.card, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.trailing, Theme.Metric.screenPadding)
        }
        .preferredColorScheme(.dark)
    }

    private var priceCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text("7-day free trial, then billed monthly")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            Spacer()

            Text("$4.99/mo")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
        }
        .padding(20)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }
}

#Preview {
    PaywallView()
        .environment(Entitlements())
}
