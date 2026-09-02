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

    var isProUnlocked: Bool { tier == .pro }

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

    // Placeholder purchase hooks so the UI can be wired now and swapped for
    // real StoreKit calls later.
    func purchasePro() { tier = .pro }
    func restorePurchases() {}

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
        UserDefaults.standard.removeObject(forKey: Self.overrideKey)
        tier = .free
        UserDefaults.standard.removeObject(forKey: Self.overrideKey)
    }
    #endif
}
