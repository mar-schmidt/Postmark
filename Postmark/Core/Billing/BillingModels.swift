import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum PaywallProductID {
    static let monthly = "PostmarkPro.Monthly"
    static let annual = "PostmarkPro.Annual"

    static let all = [monthly, annual]
}

enum SubscriptionTier: String, Codable {
    case free
    case pro
}

struct BillingEntitlement: Equatable, Codable {
    var tier: SubscriptionTier
    var expirationDate: Date?

    static let free = BillingEntitlement(
        tier: .free,
        expirationDate: nil
    )

    var isActive: Bool {
        guard tier == .pro else { return false }
        guard let expirationDate else { return true }
        return expirationDate > Date()
    }
}

enum BillingPeriod: String, Equatable, Codable {
    case month
    case year
    case unknown

    var title: String {
        switch self {
        case .month:
            return "Monthly"
        case .year:
            return "Yearly"
        case .unknown:
            return "Plan"
        }
    }
}

struct BillingProduct: Identifiable, Equatable {
    let id: String
    let displayName: String
    let displayPrice: String
    let period: BillingPeriod
    let hasIntroOffer: Bool
}

enum PaywallState: Equatable {
    case idle
    case loading
    case loaded
    case purchasing(String)
    case restoring
    case error(String)

    var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}

enum BillingError: LocalizedError {
    case productsUnavailable
    case productNotFound
    case timedOut
    case purchaseCancelled
    case purchasePending
    case unverifiedTransaction
    case unknownPurchaseResult

    var errorDescription: String? {
        switch self {
        case .productsUnavailable:
            return "No subscription plans are available right now."
        case .productNotFound:
            return "The selected plan could not be found."
        case .timedOut:
            return "The App Store took too long to respond. Try again."
        case .purchaseCancelled:
            return "Purchase cancelled."
        case .purchasePending:
            return "Purchase is pending approval."
        case .unverifiedTransaction:
            return "Unable to verify your purchase. Try again."
        case .unknownPurchaseResult:
            return "Unexpected purchase result from App Store."
        }
    }
}

protocol BillingService: AnyObject {
    var cachedEntitlement: BillingEntitlement { get }
    var entitlementUpdates: AsyncStream<BillingEntitlement> { get }

    func refreshEntitlement() async -> BillingEntitlement
    func fetchProducts(timeoutSeconds: Double) async throws -> [BillingProduct]
    #if canImport(AppKit)
    func purchase(
        productID: String,
        confirmIn window: NSWindow
    ) async throws -> BillingEntitlement
    #else
    func purchase(productID: String) async throws -> BillingEntitlement
    #endif
    func restorePurchases() async throws -> BillingEntitlement
}
