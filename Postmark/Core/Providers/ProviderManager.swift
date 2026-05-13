import Foundation

@MainActor
final class ProviderManager {
    private var providersByAccountID: [UUID: EmailProvider] = [:]
    var activeAccountID: UUID?

    var activeProvider: EmailProvider? {
        guard let activeAccountID else { return nil }
        return providersByAccountID[activeAccountID]
    }

    func register(provider: EmailProvider, for accountID: UUID) {
        providersByAccountID[accountID] = provider
    }

    func provider(for accountID: UUID) -> EmailProvider? {
        providersByAccountID[accountID]
    }

    func removeProvider(for accountID: UUID) {
        providersByAccountID.removeValue(forKey: accountID)
    }

    func clear() {
        providersByAccountID.removeAll()
        activeAccountID = nil
    }
}
