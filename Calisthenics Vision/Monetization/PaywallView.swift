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
    @State private var purchaseFailed: String?

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

                PrimaryButton(title: buttonTitle) {
                    Task {
                        let unlocked = await entitlements.purchasePro()
                        if unlocked {
                            dismiss()
                        } else if let error = entitlements.store.lastError {
                            purchaseFailed = error
                        }
                        // A cancelled purchase reports nothing and simply
                        // leaves the paywall open.
                    }
                }
                .disabled(entitlements.store.isPurchasing)
                .overlay {
                    if entitlements.store.isPurchasing {
                        ProgressView().tint(Theme.Color.background)
                    }
                }

                Button("Restore Purchases") {
                    Task {
                        await entitlements.restorePurchases()
                        if entitlements.isProUnlocked { dismiss() }
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

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
        .task { await entitlements.refresh() }
        .alert(
            "Purchase failed",
            isPresented: .init(
                get: { purchaseFailed != nil },
                set: { if !$0 { purchaseFailed = nil } }
            )
        ) {
            Button("OK", role: .cancel) { purchaseFailed = nil }
        } message: {
            Text(purchaseFailed ?? "")
        }
    }

    private var buttonTitle: String {
        entitlements.store.introOfferDescription == nil ? "Subscribe" : "Start Free Trial"
    }

    /// Describes the intro offer from the store, or states the plain terms
    /// when there isn't one. Never promises a trial the product doesn't have.
    private var trialCopy: String {
        if let intro = entitlements.store.introOfferDescription {
            return "\(intro) \(entitlements.store.displayPrice) per month"
        }
        return "\(entitlements.store.displayPrice) per month, cancel anytime"
    }

    private var priceCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(trialCopy)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            Spacer()

            Text("\(entitlements.store.displayPrice)/mo")
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
