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

    /// A cheap opaque token that changes whenever the mailbox changes.
    ///
    /// Used to gate near-real-time polling: when the token is unchanged the
    /// sync loop skips the expensive inbox fetch entirely, so it can run on a
    /// short interval without burning quota. Returns `nil` for providers that
    /// don't support change detection, in which case every tick fetches.
    func latestChangeToken() async throws -> String?
}

extension EmailProvider {
    func latestChangeToken() async throws -> String? { nil }
}
