import Foundation
import StoreKit
#if canImport(AppKit)
import AppKit
#endif

final class StoreKitBillingService: BillingService {
    private let productIDs: [String]
    private let entitlementKey = "billing_entitlement"
    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?

    private let stream: AsyncStream<BillingEntitlement>
    private var continuation: AsyncStream<BillingEntitlement>.Continuation?

    private(set) var cachedEntitlement: BillingEntitlement

    var entitlementUpdates: AsyncStream<BillingEntitlement> {
        stream
    }

    init(
        productIDs: [String] = PaywallProductID.all,
        defaults: UserDefaults = .standard
    ) {
        self.productIDs = productIDs
        self.defaults = defaults
        self.cachedEntitlement = Self.loadCachedEntitlement(
            key: entitlementKey,
            defaults: defaults
        )
        var localContinuation:
            AsyncStream<BillingEntitlement>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
        continuation?.yield(cachedEntitlement)
        startTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
        continuation?.finish()
    }

    func refreshEntitlement() async -> BillingEntitlement {
        let entitlement = await evaluateCurrentEntitlement()
        cache(entitlement)
        continuation?.yield(entitlement)
        return entitlement
    }

    func fetchProducts(
        timeoutSeconds: Double
    ) async throws -> [BillingProduct] {
        let products = try await runWithTimeout(seconds: timeoutSeconds) {
            try await Product.products(for: self.productIDs)
        }
        let mapped = products.compactMap(Self.map(product:))
        guard !mapped.isEmpty else {
            throw BillingError.productsUnavailable
        }
        return mapped.sorted { lhs, rhs in
            Self.sortRank(for: lhs.period) > Self.sortRank(for: rhs.period)
        }
    }

    func purchase(
        productID: String,
        confirmIn window: NSWindow
    ) async throws -> BillingEntitlement {
        log(
            "request purchase product=\(productID) "
                + "window=\(window.windowNumber)"
        )
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw BillingError.productNotFound
        }
        let result: Product.PurchaseResult
        if #available(macOS 15.2, *) {
            result = try await product.purchase(confirmIn: window)
        } else {
            result = try await product.purchase()
        }
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                let entitlement = await refreshEntitlement()
                log("purchase verified transaction=\(transaction.id)")
                return entitlement
            case .unverified:
                log("purchase unverified")
                throw BillingError.unverifiedTransaction
            }
        case .pending:
            log("purchase pending")
            throw BillingError.purchasePending
        case .userCancelled:
            log("purchase cancelled")
            throw BillingError.purchaseCancelled
        @unknown default:
            log("purchase unknown result")
            throw BillingError.unknownPurchaseResult
        }
    }

    func restorePurchases() async throws -> BillingEntitlement {
        try await AppStore.sync()
        let entitlement = await refreshEntitlement()
        return entitlement
    }

    private func startTransactionUpdates() {
        updatesTask?.cancel()
        updatesTask = Task {
            for await verification in Transaction.updates {
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    let entitlement = await evaluateCurrentEntitlement()
                    cache(entitlement)
                    continuation?.yield(entitlement)
                case .unverified:
                    break
                }
            }
        }
    }

    private func evaluateCurrentEntitlement() async -> BillingEntitlement {
        var bestExpiration: Date?
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else {
                continue
            }
            guard productIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expiration = transaction.expirationDate,
                expiration <= Date() {
                continue
            }
            if let expiration = transaction.expirationDate {
                if let previousBest = bestExpiration {
                    bestExpiration = max(previousBest, expiration)
                } else {
                    bestExpiration = expiration
                }
            } else {
                return BillingEntitlement(
                    tier: .pro,
                    expirationDate: nil
                )
            }
        }
        if bestExpiration != nil {
            return BillingEntitlement(
                tier: .pro,
                expirationDate: bestExpiration
            )
        }
        return .free
    }

    private func cache(_ entitlement: BillingEntitlement) {
        cachedEntitlement = entitlement
        guard let data = try? JSONEncoder().encode(entitlement) else { return }
        defaults.set(data, forKey: entitlementKey)
    }

    private static func loadCachedEntitlement(
        key: String,
        defaults: UserDefaults
    ) -> BillingEntitlement {
        guard let data = defaults.data(forKey: key) else { return .free }
        guard let value = try? JSONDecoder().decode(
            BillingEntitlement.self,
            from: data
        ) else {
            return .free
        }
        return value
    }

    private static func map(product: Product) -> BillingProduct? {
        let period: BillingPeriod
        if let unit = product.subscription?.subscriptionPeriod.unit {
            switch unit {
            case .month:
                period = .month
            case .year:
                period = .year
            default:
                period = .unknown
            }
        } else {
            period = .unknown
        }
        return BillingProduct(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            period: period,
            hasIntroOffer: product.subscription?.introductoryOffer != nil
        )
    }

    private static func sortRank(for period: BillingPeriod) -> Int {
        switch period {
        case .year:
            return 2
        case .month:
            return 1
        case .unknown:
            return 0
        }
    }

    private func log(_ message: String) {
#if DEBUG
        print("[StoreKitBilling] \(message)")
#endif
    }
}

private func runWithTimeout<T>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            let nanos = UInt64(seconds * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanos)
            throw BillingError.timedOut
        }
        guard let value = try await group.next() else {
            throw BillingError.timedOut
        }
        group.cancelAll()
        return value
    }
}
