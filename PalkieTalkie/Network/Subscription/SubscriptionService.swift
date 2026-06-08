import Foundation
import StoreKit

/// Lightweight, non-StoreKit view of an IAP product. SubscriptionView reads these; SubscriptionStore exposes a dictionary of them. Decouples the UI + store from `StoreKit.Product` (a non-extensible stdlib struct that can't be constructed outside Apple's framework, so tests can't fake it). The store keeps a parallel cache of real `Product`s internally for the purchase call.
struct SubscriptionProduct: Equatable {
    let id: SubscriptionID
    let displayPrice: String
    let description: String
}

/// Outcome of a `purchase()` call. Mirrors StoreKit's `Product.PurchaseResult` cases the store actually distinguishes — success, user-cancel, payment-pending, and a flattened error.
enum PurchaseOutcome: Equatable {
    case success
    case userCancelled
    case pending
    case unverified
    case failed(String)
}

/// Seam over the StoreKit 2 surface SubscriptionStore needs. Production uses `DefaultSubscriptionService` which wraps the real `Product` / `Transaction` / `AppStore` APIs; tests inject a fake that returns canned outcomes. Lets every SubscriptionStore + SubscriptionView body branch run under XCTest without depending on Apple's StoreKit interception (which is unreliable in Xcode 26.2 — see SubscriptionStoreTests).
protocol SubscriptionService: Sendable {
    func loadProducts() async throws -> [SubscriptionID: SubscriptionProduct]
    func purchase(_ id: SubscriptionID) async -> PurchaseOutcome
    /// Returns the highest-tier active entitlement, if any.
    func currentEntitlement() async -> SubscriptionID?
    /// Apple's StoreKit sync — re-pulls entitlements from the App Store. Called by "Restore purchases."
    func sync() async throws
}

/// Production implementation. Holds the cached `[SubscriptionID: Product]` map internally so purchase calls can reach the real `Product.purchase()` method without surfacing `StoreKit.Product` to callers.
@MainActor
final class DefaultSubscriptionService: SubscriptionService {
    /// Mutable cache populated by loadProducts; read inside purchase. `nonisolated(unsafe)` is safe because writes happen on @MainActor and the Sendable contract on the protocol is honored by main-actor confinement of this concrete type.
    private nonisolated(unsafe) var nativeProducts: [SubscriptionID: Product] = [:]

    nonisolated init() {}

    func loadProducts() async throws -> [SubscriptionID: SubscriptionProduct] {
        let storeProducts = try await Product.products(for: SubscriptionID.all.map(\.rawValue))
        var native: [SubscriptionID: Product] = [:]
        var view: [SubscriptionID: SubscriptionProduct] = [:]
        for product in storeProducts {
            guard let id = SubscriptionID(rawValue: product.id) else { continue }
            native[id] = product
            view[id] = SubscriptionProduct(
                id: id,
                displayPrice: product.displayPrice,
                description: product.description,
            )
        }
        nativeProducts = native
        return view
    }

    func purchase(_ id: SubscriptionID) async -> PurchaseOutcome {
        guard let product = nativeProducts[id] else {
            return .failed("Subscription not available yet. Try again in a moment.")
        }
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                if case let .verified(txn) = verification {
                    await txn.finish()
                    return .success
                }
                return .unverified
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Unknown purchase result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func currentEntitlement() async -> SubscriptionID? {
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
        return found
    }

    func sync() async throws {
        try await AppStore.sync()
    }
}
