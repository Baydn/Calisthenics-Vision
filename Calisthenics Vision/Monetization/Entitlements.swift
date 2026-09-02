//
//  Entitlements.swift
//  Calisthenics Vision
//
//  Tier gating (SPEC.md §4). This is a UI-layer stand-in — when StoreKit 2 /
//  RevenueCat lands, `tier` should be driven by live subscription status.
//

import Foundation
import Observation

@Observable
final class Entitlements {

    enum Tier: String, CaseIterable, Identifiable {
        case free, pro

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .free: "Free"
            case .pro:  "Pro"
            }
        }
    }

    /// Current tier.
    ///
    /// In debug builds this persists, so flipping to Pro to test a gated
    /// screen survives a relaunch instead of resetting every time. Release
    /// builds keep it in memory only — a locally persisted "pro" flag must
    /// never be what unlocks paid features once real billing exists.
    var tier: Tier = .free {
        didSet { persistOverride() }
    }

    /// Live subscription state. This is the source of truth in release builds.
    let store = SubscriptionStore()

    /// Whether Pro features are available.
    ///
    /// A real subscription always unlocks. In debug builds the tier switch can
    /// also unlock, so gated screens can be exercised without buying anything
    /// — but that path is compiled out of release, where only the store
    /// decides.
    var isProUnlocked: Bool {
        #if DEBUG
        return store.hasPro || tier == .pro
        #else
        return store.hasPro
        #endif
    }

    /// Loads products and reconciles entitlement with the App Store.
    func refresh() async {
        await store.load()
    }

    /// Free tier keeps a rolling 7-day local history (SPEC.md §4).
    var historyWindowDays: Int? { isProUnlocked ? nil : 7 }

    init() {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: Self.overrideKey),
           let stored = Tier(rawValue: raw) {
            tier = stored
        }
        #endif
    }

    func canTrack(_ movement: Movement) -> Bool {
        isProUnlocked || !movement.isPro
    }

    /// - Returns: true if Pro is active afterwards.
    @discardableResult
    func purchasePro() async -> Bool {
        await store.purchase()
    }

    func restorePurchases() async {
        await store.restore()
    }

    // MARK: - Debug persistence

    private static let overrideKey = "debug.entitlementTier"

    private func persistOverride() {
        #if DEBUG
        UserDefaults.standard.set(tier.rawValue, forKey: Self.overrideKey)
        #endif
    }

    #if DEBUG
    /// Returns the app to a first-launch tier state.
    func resetToNewUser() {
        tier = .free
        UserDefaults.standard.removeObject(forKey: Self.overrideKey)
        // Onboarding is part of a first launch, so a simulated new user has
        // to see it again.
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }
    #endif
}
