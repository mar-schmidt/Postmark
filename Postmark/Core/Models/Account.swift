import Foundation

struct Account: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var email: String
    var displayName: String
    var isActiveInbox: Bool
    var emailOpenBehavior: EmailOpenBehavior
    var selectedLabelIDs: [String]
}

extension Account {
    var localizedEmailUsername: String {
        guard let atIndex = email.firstIndex(of: "@") else { return email }
        return String(email[..<atIndex])
    }
}
