/// Build-time product flags.
enum FeatureFlags {
    /// Ships false for the v1 free launch: paid IAPs can't function until the Paid Applications Agreement is Active, which needs tax and banking filed under Gitauto, Inc.'s EIN, and that's blocked until the Apple account finishes converting from Individual to the company.
    /// While the agreement is pending, StoreKit returns no products, so any in-app reference to purchasable subscriptions trips App Review 2.1(b). Flip to true and resubmit once the agreement is Active.
    static let subscriptionsEnabled = false
}
