import AppAuth
import Foundation
import Security

protocol AuthStateStore: Sendable {
    func loadAuthState() -> OIDAuthState?
    func saveAuthState(_ state: OIDAuthState) throws
    func clearAuthState() throws
}

enum TokenStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed: \(status)"
        }
    }
}

final class KeychainTokenStore: AuthStateStore {
    private static let service = "com.decoded.Postmark.oauth"
    static let legacyAccount = "google_auth_state"
    private let account: String

    init(account: String = KeychainTokenStore.legacyAccount) {
        self.account = account
    }

    func scopedStore(for accountID: UUID) -> KeychainTokenStore {
        KeychainTokenStore(account: scopedKey(for: accountID))
    }

    func scopedStore(for storageKey: String) -> KeychainTokenStore {
        KeychainTokenStore(account: scopedKey(for: storageKey))
    }

    private func scopedKey(for value: UUID) -> String {
        scopedKey(for: value.uuidString.lowercased())
    }

    private func scopedKey(for value: String) -> String {
        "\(Self.legacyAccount).\(value)"
    }

    func loadAuthState() -> OIDAuthState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
            let data = result as? Data else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: OIDAuthState.self,
            from: data
        )
    }

    func saveAuthState(_ state: OIDAuthState) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: state,
            requiringSecureCoding: true
        )
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TokenStoreError.unexpectedStatus(addStatus)
            }
            return
        }
        guard update == errSecSuccess else {
            throw TokenStoreError.unexpectedStatus(update)
        }
    }

    func clearAuthState() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.unexpectedStatus(status)
        }
    }
}

final class InMemoryTokenStore: AuthStateStore {
    private var state: OIDAuthState?

    func loadAuthState() -> OIDAuthState? { state }

    func saveAuthState(_ state: OIDAuthState) throws {
        self.state = state
    }

    func clearAuthState() throws {
        state = nil
    }
}
