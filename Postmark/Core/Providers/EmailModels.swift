import Foundation

struct EmailMessage: Equatable, Identifiable, Sendable {
    let id: String
    let threadID: String
    let sender: String
    let senderAddress: String
    let subject: String
    let snippet: String
    let bodyText: String
    let bodyHTML: String?
    let senderPhotoURL: URL?
    let senderInitials: String
    let receivedAt: Date
    let isUnread: Bool
}

struct InboxPage: Sendable {
    let messages: [EmailMessage]
    let nextPageToken: String?
}

struct ReplyDraft: Sendable {
    let messageID: String
    let threadID: String
    let recipient: String
    let subject: String
    let body: String
}

struct EmailLabel: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
}
