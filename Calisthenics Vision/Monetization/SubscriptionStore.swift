//
//  SubscriptionStore.swift
//  Calisthenics Vision
//
//  StoreKit 2 wrapper for the Pro subscription (SPEC.md §4).
//
//  Entitlement is derived from `Transaction.currentEntitlements` — the store's
//  own record — rather than from anything this app writes down. A locally
//  stored "is pro" flag is trivially forged, and would also go stale the
//  moment a subscription lapses or is refunded on another device.
//

import Foundation
import Observation
import StoreKit

@Observable
final class SubscriptionStore {

    static let proMonthlyID = "com.baydon.CalisthenicsVision.pro.monthly"

    enum LoadState: Equatable {
        case idle
        case loading
        /// Products couldn't be fetched — no App Store Connect entry yet, no
        /// local .storekit file selected in the scheme, or no network.
        case unavailable(String)
        case loaded
    }

    private(set) var loadState: LoadState = .idle
    private(set) var proProduct: Product?
    /// Whether an unexpired Pro entitlement exists right now.
    private(set) var hasPro = false
    private(set) var isPurchasing = false
    private(set) var lastError: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        // Start listening before anything else: a purchase approved elsewhere
        // (Ask to Buy, another device) arrives here and nowhere else.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self.refreshEntitlement()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Loading

    func load() async {
        loadState = .loading
        do {
            let products = try await Product.products(for: [Self.proMonthlyID])
            proProduct = products.first
            loadState = proProduct == nil
                ? .unavailable("No products configured for this build.")
                : .loaded
        } catch {
            loadState = .unavailable(error.localizedDescription)
        }
        await refreshEntitlement()
    }

    /// Recomputes entitlement from the store's records.
    func refreshEntitlement() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard transaction.productID == Self.proMonthlyID else { continue }
            // A revoked or expired transaction still appears here.
            if transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > .now }) ?? true {
                active = true
            }
        }
        hasPro = active
    }

    // MARK: - Purchasing

    /// - Returns: true if the purchase completed and Pro is now active.
    @discardableResult
    func purchase() async -> Bool {
        guard let proProduct else {
            lastError = "This product isn't available right now."
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await proProduct.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // Failed verification means the receipt didn't come from
                    // Apple; never unlock on it.
                    lastError = "That purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlement()
                return hasPro

            case .pending:
                // Ask to Buy and similar — approval arrives via Transaction.updates.
                lastError = "Your purchase is awaiting approval."
                return false

            case .userCancelled:
                return false

            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlement()
    }

    // MARK: - Display

    /// Localized price, falling back to the spec price when the store can't
    /// be reached — better than showing a blank where a number belongs.
    var displayPrice: String {
        proProduct?.displayPrice ?? "$4.99"
    }

    var introOfferDescription: String? {
        guard let offer = proProduct?.subscription?.introductoryOffer else {
            return nil
        }
        let unit: String
        switch offer.period.unit {
        case .day:   unit = "day"
        case .week:  unit = "week"
        case .month: unit = "month"
        case .year:  unit = "year"
        @unknown default: unit = "period"
        }
        let count = offer.period.value
        return offer.paymentMode == .freeTrial
            ? "\(count) \(unit)\(count == 1 ? "" : "s") free, then"
            : nil
    }
}
