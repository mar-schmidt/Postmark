//
//  NewMailNotifier.swift
//  Postmark
//
//  Wraps UNUserNotificationCenter to surface system banners when new mail
//  arrives, and routes notification actions (open / archive) back into the
//  app. The in-app toast is handled separately in the SwiftUI layer.
//

import Foundation
import UserNotifications

/// A lightweight, Sendable description of a freshly-arrived message used to
/// drive both the system banner and the in-app toast.
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

@MainActor
final class NewMailNotifier: NSObject {
    static let shared = NewMailNotifier()

    /// Invoked when the user opens a notification (default action or "Open").
    var onOpen: ((String) -> Void)?
    /// Invoked when the user picks the "Archive" action on a notification.
    var onArchive: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private static let categoryID = "PM_NEW_MAIL"
    private static let archiveActionID = "PM_ARCHIVE"
    private var isConfigured = false
    private var isAuthorized = false

    private override init() {
        super.init()
    }

    /// Registers the delegate and notification category. Safe to call early.
    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        center.delegate = self
        let archive = UNNotificationAction(
            identifier: Self.archiveActionID,
            title: "Archive",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [archive],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Requests banner authorization. No-ops after the first grant/denial.
    func requestAuthorization() {
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else {
                Task { @MainActor in
                    self?.isAuthorized =
                        settings.authorizationStatus == .authorized
                }
                return
            }
            self?.center.requestAuthorization(
                options: [.alert, .sound, .badge]
            ) { granted, _ in
                Task { @MainActor in self?.isAuthorized = granted }
            }
        }
    }

    /// Posts a system banner for a newly-arrived message.
    func post(_ item: NewMailItem) {
        let content = UNMutableNotificationContent()
        content.title = item.sender
        content.subtitle = item.subject.isEmpty ? "New message" : item.subject
        content.body = item.snippet
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = "postmark-inbox"
        content.userInfo = ["messageID": item.id]

        let request = UNNotificationRequest(
            identifier: "pm-\(item.id)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
}

extension NewMailNotifier: UNUserNotificationCenterDelegate {
    // Show banners even while Postmark is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let messageID = response.notification.request.content
            .userInfo["messageID"] as? String
        let actionID = response.actionIdentifier
        Task { @MainActor in
            guard let messageID else { return }
            if actionID == Self.archiveActionID {
                self.onArchive?(messageID)
            } else {
                self.onOpen?(messageID)
            }
        }
        completionHandler()
    }
}
