import Foundation
import StoreKit

/// Observable client-side view of the StoreKit 2 subscription state. All real StoreKit interaction lives in `SubscriptionService` so tests can inject a fake — see SubscriptionStoreTests. Backend reconciliation: Apple ASN webhook is the source of truth for `users.premium` in Neon. This store is the iOS UI's "currently subscribed" cache without waiting on a backend round-trip.
@MainActor
@Observable
final class SubscriptionStore {
    /// The four App Store products, keyed by `SubscriptionID`. Empty until `loadProducts()` resolves.
    private(set) var products: [SubscriptionID: SubscriptionProduct] = [:]
    /// The product the user is currently entitled to (if any). Driven by Transaction.currentEntitlements via the service.
    private(set) var entitled: SubscriptionID?
    /// Latest error to surface in the UI. Cleared on next successful action.
    var error: String?

    @ObservationIgnored private let service: any SubscriptionService
    /// `@ObservationIgnored` skips @Observable's tracking machinery so the deinit can read it from a nonisolated context. `nonisolated(unsafe)` is safe because Task<Void, Never> is Sendable and the property is written once in init.
    @ObservationIgnored private nonisolated(unsafe) var transactionListener: Task<Void, Never>?

    init(service: any SubscriptionService = DefaultSubscriptionService()) {
        self.service = service
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(txn) = result {
                    await txn.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Fetch the four IAP product metadata. Idempotent — safe to call on view appear.
    func loadProducts() async {
        do {
            products = try await service.loadProducts()
            await refreshEntitlement()
            error = nil
        } catch {
            self.error = "Couldn't load subscriptions. \(error.localizedDescription)"
        }
    }

    func refreshEntitlement() async {
        entitled = await service.currentEntitlement()
    }

    /// Trigger an App Store purchase flow. Returns `true` on a verified success.
    @discardableResult
    func purchase(_ id: SubscriptionID) async -> Bool {
        let outcome = await service.purchase(id)
        switch outcome {
        case .success:
            await refreshEntitlement()
            error = nil
            return true
        case .userCancelled:
            return false
        case .pending:
            error = "Payment is pending approval (Ask to Buy / SCA)."
            return false
        case .unverified:
            error = "Apple couldn't verify that purchase."
            return false
        case let .failed(message):
            error = message
            return false
        }
    }

    /// Re-sync entitlements from Apple. Useful after a restore-purchases tap.
    func restore() async {
        do {
            try await service.sync()
            await refreshEntitlement()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
