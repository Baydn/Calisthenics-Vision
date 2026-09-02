//
//  Entitlements.swift
//  Calisthenics Vision
//
//  Tier gating (SPEC.md §4). This is a UI-layer stand-in — when StoreKit 2 /
//  RevenueCat lands, `isProUnlocked` should be driven by the live
//  subscription status rather than in-memory state.
//

import Foundation
import Observation

@Observable
final class Entitlements {
    /// Whether the user has an active Pro subscription.
    var isProUnlocked: Bool = false

    /// Free tier keeps a rolling 7-day local history (SPEC.md §4).
    var historyWindowDays: Int? { isProUnlocked ? nil : 7 }

    func canTrack(_ movement: Movement) -> Bool {
        isProUnlocked || !movement.isPro
    }

    // Placeholder purchase hooks so the UI can be wired now and swapped for
    // real StoreKit calls later.
    func purchasePro() { isProUnlocked = true }
    func restorePurchases() {}
}
