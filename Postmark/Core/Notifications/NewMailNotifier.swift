//
//  NewMailNotifier.swift
//  Postmark
//
//  Describes a freshly-arrived message used to drive the new-mail toast. The
//  toast is shown in-app when the panel is open, and in a floating window
//  (see FloatingToastController) when it is closed — the latter replaces the
//  macOS system banner this type previously fed.
//

import Foundation

/// A lightweight, Sendable description of a freshly-arrived message used to
/// drive the in-app and floating new-mail toasts.
struct NewMailItem: Identifiable, Equatable, Sendable {
    let id: String
    let threadID: String
    let sender: String
    let senderInitials: String
    let subject: String
    let snippet: String
    let receivedAt: Date

    init(message: EmailMessage) {
        id = message.id
        threadID = message.threadID
        sender = message.sender.isEmpty ? message.senderAddress : message.sender
        senderInitials = message.senderInitials
        subject = message.subject
        snippet = message.snippet
        receivedAt = message.receivedAt
    }
}
