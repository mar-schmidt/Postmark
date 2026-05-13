import Foundation

protocol EmailProvider: Sendable {
    func fetchInboxPage(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage
    func fetchLabels() async throws -> [EmailLabel]
    func fetchAccountEmail() async throws -> String
    func reply(with draft: ReplyDraft) async throws
    func archive(messageID: String, labelIDs: [String]) async throws
    func signOut() throws
}
