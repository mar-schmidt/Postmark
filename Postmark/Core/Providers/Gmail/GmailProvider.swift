import Foundation

struct GmailProvider: EmailProvider {
    let authService: GoogleOAuthService
    let apiClient: GmailAPIClient

    func authenticate() async throws {
        try await authService.authorize()
    }

    func fetchInboxPage(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage {
        try await apiClient.fetchInbox(
            pageToken: pageToken,
            labelIDs: labelIDs
        )
    }

    func fetchLabels() async throws -> [EmailLabel] {
        try await apiClient.fetchLabels()
    }

    func fetchAccountEmail() async throws -> String {
        try await apiClient.fetchAccountEmail()
    }

    func reply(with draft: ReplyDraft) async throws {
        try await apiClient.reply(with: draft)
    }

    func archive(messageID: String, labelIDs: [String]) async throws {
        try await apiClient.archive(messageID: messageID, labelIDs: labelIDs)
    }

    func signOut() throws {
        try authService.signOut()
    }
}
