import SwiftUI

/// Subscription / billing screen. Focused on the actions a user can actually take here: see what plan they're on, upgrade (when products are available), restore a prior purchase, and jump to Apple's Settings screen to manage / downgrade / cancel (Apple owns that flow; iOS apps can't do it inline).
@MainActor
struct SubscriptionView: View {
    @Environment(\.backendAPI) private var api
    @State private var store: SubscriptionStore
    @State private var purchasing: SubscriptionID?
    @State private var entitlement: Entitlement?
    @State private var entitlementError: String?

    init(service: (any SubscriptionService)? = nil) {
        if let service {
            _store = State(initialValue: SubscriptionStore(service: service))
        } else {
            _store = State(initialValue: SubscriptionStore())
        }
    }

    var body: some View {
        List {
            currentPlanSection
            if store.entitled == nil {
                upgradeSection
            }
            manageSection
            if let err = store.error ?? entitlementError {
                Section {
                    Text(err).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Subscription")
        .task {
            await store.loadProducts()
            await loadEntitlement()
        }
        .refreshable {
            await store.loadProducts()
            await loadEntitlement()
        }
    }

    /// Surface entitlement-fetch failures instead of `try?`-swallowing them — a silently-missing entitlement shows the user the wrong plan/limits with no signal anything broke.
    private func loadEntitlement() async {
        do {
            entitlement = try await api.getEntitlement()
            entitlementError = nil
        } catch {
            entitlementError = "Couldn't load your plan: \(error.localizedDescription)"
        }
    }

    /// Render free limits with concrete numbers pulled from `/entitlement` (backend is single source of truth). Falls back to the current values if the fetch hasn't returned yet.
    private var freeLimitsCopy: String {
        let day = entitlement?.freeMinutesPerDayCap ?? 10
        let week = entitlement?.freeMinutesPerWeekCap ?? 30
        return "\(day) min/day, \(week) min/week. Resets at local midnight (daily) and Monday (weekly)."
    }

    // MARK: - Current plan

    private var currentPlanSection: some View {
        Section("Current plan") {
            if let entitled = store.entitled {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(entitled.tier.rawValue.capitalized) · \(entitled.cycle.rawValue.capitalized)")
                            .font(.headline)
                        Text("Unlimited voice practice").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "person.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free").font(.headline)
                        Text(freeLimitsCopy).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Upgrade (free users only)

    @ViewBuilder
    private var upgradeSection: some View {
        if store.products.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upgrades not available yet").font(.headline)
                    Text(
                        "Our subscription products are still pending Apple's review. You'll be able to upgrade here as soon as they're approved.",
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Upgrade")
            }
        } else {
            // Explicit ordering: Individual first (the common single-user pick), then Family. The codegen-generated `SubscriptionTier.allCases` returns the enum-declaration order, which pushes Family above Individual — visually wrong.
            ForEach([SubscriptionTier.individual, .family], id: \.self) { tier in
                Section(tier.rawValue.capitalized) {
                    ForEach(SubscriptionCycle.allCases) { cycle in
                        let id = SubscriptionID(tier: tier, cycle: cycle)
                        productRow(id: id)
                    }
                }
            }
        }
    }

    // MARK: - Manage (Apple-owned actions)

    private var manageSection: some View {
        Section {
            // Apple requires downgrade / cancel / change-cycle to go through the App Store subscription settings — apps cannot do these inline. We deep-link to that exact screen.
            if store.entitled != nil, let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                Link(destination: url) {
                    Label("Change or cancel in App Store", systemImage: "arrow.up.forward.app")
                }
            }
            Button("Restore purchases") {
                Task { await store.restore() }
            }
        } footer: {
            if store.entitled != nil {
                Text(
                    "To downgrade, switch tier, or cancel: tap above to open Settings → Apple ID → Subscriptions. Apple handles all changes — they take effect at the end of your current billing period.",
                )
            } else {
                Text("Already paid through Apple but don't see it here? Tap Restore to re-sync.")
            }
        }
    }

    @ViewBuilder
    private func productRow(id: SubscriptionID) -> some View {
        let product = store.products[id]
        let isCurrent = store.entitled == id
        let isPurchasing = purchasing == id
        Button {
            guard !isPurchasing, !isCurrent else { return }
            purchasing = id
            Task {
                await store.purchase(id)
                purchasing = nil
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    // Section header carries the tier — row label is just the cycle so we don't stack "Family / Family · Monthly".
                    Text(id.cycle.rawValue.capitalized).font(.headline)
                    if let description = product?.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isPurchasing {
                    ProgressView()
                } else if isCurrent {
                    Image(systemName: "checkmark").foregroundStyle(.green)
                } else if let price = product?.displayPrice {
                    Text(price).font(.body)
                } else {
                    Text(verbatim: "-").font(.body).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isCurrent || product == nil)
    }
}
