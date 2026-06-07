import Foundation
import StoreKit

/// StoreKit 2 wrapper. Loads the four IAP products, exposes purchase + restore, and listens to
/// `Transaction.updates` so out-of-band entitlements (renew, refund, family-share) flip `entitledTier` immediately.
///
/// Backend reconciliation: Apple ASN webhook (already wired) is the source of truth for `users.premium` in Neon. This
/// store is the client-side view so the iOS UI can show "currently subscribed" without waiting on a backend round-trip.
@MainActor
@Observable
final class SubscriptionStore {
    /// The four App Store products, keyed by our `SubscriptionID`. Empty until `loadProducts()` resolves.
    private(set) var products: [SubscriptionID: Product] = [:]
    /// The product the user is currently entitled to (if any). Driven by `Transaction.currentEntitlements`.
    private(set) var entitled: SubscriptionID?
    /// Latest error to surface in the UI. Cleared on next successful action.
    var error: String?

    /// `@ObservationIgnored` skips @Observable's tracking machinery so the deinit can read it from a nonisolated context. `nonisolated(unsafe)` is safe because Task<Void, Never> is Sendable and the property is written once in init.
    @ObservationIgnored private nonisolated(unsafe) var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Fetch the four IAP product metadata (display name, localized price, intro offer). Idempotent — safe to call on
    /// view appear.
    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: SubscriptionID.all.map(\.rawValue))
            var keyed: [SubscriptionID: Product] = [:]
            for product in storeProducts {
                if let id = SubscriptionID(rawValue: product.id) {
                    keyed[id] = product
                }
            }
            products = keyed
            await refreshEntitlement()
            error = nil
        } catch {
            self.error = "Couldn't load subscriptions. \(error.localizedDescription)"
        }
    }

    /// Walk current entitlements and pin the highest-tier one (Family > Individual). Called after load, after a
    /// purchase, and on `Transaction.updates`.
    func refreshEntitlement() async {
        var found: SubscriptionID?
        for await result in Transaction.currentEntitlements {
            if case let .verified(txn) = result,
               txn.revocationDate == nil,
               let id = SubscriptionID(rawValue: txn.productID)
            {
                if found == nil || id.tier == .family {
                    found = id
                }
            }
        }
        entitled = found
    }

    /// Trigger an App Store purchase flow. Returns `true` on a verified success.
    @discardableResult
    func purchase(_ id: SubscriptionID) async -> Bool {
        guard let product = products[id] else {
            error = "Subscription not available yet. Try again in a moment."
            return false
        }
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                if case let .verified(txn) = verification {
                    await txn.finish()
                    await refreshEntitlement()
                    error = nil
                    return true
                }
                error = "Apple couldn't verify that purchase."
                return false
            case .userCancelled:
                return false
            case .pending:
                error = "Payment is pending approval (Ask to Buy / SCA)."
                return false
            @unknown default:
                return false
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Re-sync entitlements from Apple. Useful after a restore-purchases tap.
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        if case let .verified(txn) = transactionResult {
            await txn.finish()
            await refreshEntitlement()
        }
    }
}
