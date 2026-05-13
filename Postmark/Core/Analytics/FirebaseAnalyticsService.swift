import FirebaseAnalytics
import FirebaseCore
import Foundation

@MainActor
final class FirebaseAnalyticsService: @unchecked Sendable {
    static let shared = FirebaseAnalyticsService()

    private let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func log(
        _ event: AnalyticsEvent,
        parameters: [String: AnalyticsValue] = [:]
    ) {
        guard isEnabled else { return }
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(event.rawValue, parameters: sanitized(parameters))
    }

    func errorCategory(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "network"
        }
        if nsError.domain.contains("AppAuth") {
            return "auth"
        }
        return "general"
    }

    private func sanitized(_ params: [String: AnalyticsValue]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        normalized.reserveCapacity(params.count)
        for (rawKey, value) in params {
            let key = normalizedKey(rawKey)
            normalized[key] = value.rawValue
        }
        return normalized
    }

    private func normalizedKey(_ raw: String) -> String {
        let allowed = raw.lowercased().map { char in
            switch char {
            case "a"..."z", "0"..."9", "_":
                return char
            default:
                return "_"
            }
        }
        return String(allowed.prefix(40))
    }
}

enum AnalyticsEvent: String {
    case authSignInSuccess = "auth_sign_in_success"
    case authSignInFailed = "auth_sign_in_failed"
    case authSignOut = "auth_sign_out"
    case inboxInitialLoaded = "inbox_initial_loaded"
    case inboxRefresh = "inbox_refresh"
    case inboxRefreshFailed = "inbox_refresh_failed"
    case replySendSuccess = "reply_send_success"
    case replySendFailed = "reply_send_failed"
    case paywallPresented = "paywall_presented"
    case paywallPlanSelected = "paywall_plan_selected"
    case paywallPurchaseStarted = "paywall_purchase_started"
    case paywallPurchaseSucceeded = "paywall_purchase_succeeded"
    case paywallPurchaseFailed = "paywall_purchase_failed"
    case paywallPurchaseCancelled = "paywall_purchase_cancelled"
    case paywallRestoreStarted = "paywall_restore_started"
    case paywallRestoreSucceeded = "paywall_restore_succeeded"
    case paywallRestoreFailed = "paywall_restore_failed"
}

enum AnalyticsValue {
    case string(String)
    case int(Int)
    case bool(Bool)

    var rawValue: Any {
        switch self {
        case .string(let value):
            return String(value.prefix(100))
        case .int(let value):
            return value
        case .bool(let value):
            return value
        }
    }
}
