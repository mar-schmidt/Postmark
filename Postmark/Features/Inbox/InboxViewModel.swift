import Combine
import Foundation
import SwiftUI

@MainActor
final class InboxViewModel: ObservableObject {
    @Published var messages: [EmailMessage] = []
    @Published var nextPageToken: String?
    @Published var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var selectedLabelIDs: [String] = ["INBOX"]
    private var hasLoadedInitial = false
    private var activeLoadMoreToken: String?
    private var lastLoadMoreTriggerAt: Date?
    private let loadMoreThrottleInterval: TimeInterval = 0.5

    private let provider: EmailProvider
    private let syncService: InboxSyncService
    private let shouldPoll: Bool

    init(
        provider: EmailProvider,
        syncService: InboxSyncService,
        shouldPoll: Bool = true
    ) {
        self.provider = provider
        self.syncService = syncService
        self.shouldPoll = shouldPoll
    }

    func loadInitial() async {
        await loadInitial(force: false)
    }

    func ensureInitialLoaded() async {
        await loadInitial(force: false)
    }

    private func loadInitial(force: Bool) async {
        guard !isLoading else { return }
        if hasLoadedInitial && !messages.isEmpty && !force {
            return
        }
        let wasLoadedBeforeRequest = hasLoadedInitial
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await syncService.initialLoad(
                labelIDs: selectedLabelIDs
            )
            messages = page.messages
            nextPageToken = page.nextPageToken
            hasLoadedInitial = true
            if force {
                FirebaseAnalyticsService.shared.log(
                    .inboxRefresh,
                    parameters: ["message_count": .int(page.messages.count)]
                )
            } else if !wasLoadedBeforeRequest {
                FirebaseAnalyticsService.shared.log(
                    .inboxInitialLoaded,
                    parameters: ["message_count": .int(page.messages.count)]
                )
            }
            if shouldPoll {
                beginPolling()
            }
        } catch {
            if force {
                FirebaseAnalyticsService.shared.log(
                    .inboxRefreshFailed,
                    parameters: [
                        "error_category": .string(
                            FirebaseAnalyticsService.shared.errorCategory(
                                for: error
                            )
                        )
                    ]
                )
            }
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeededForTrailingMessage(_ messageID: String) async {
        guard messageID == messages.last?.id else { return }
        if let last = lastLoadMoreTriggerAt,
            Date().timeIntervalSince(last) < loadMoreThrottleInterval {
            return
        }
        lastLoadMoreTriggerAt = Date()
        guard let token = nextPageToken else { return }
        guard !isLoadingMore else { return }
        guard activeLoadMoreToken != token else { return }
        isLoadingMore = true
        activeLoadMoreToken = token
        defer {
            isLoadingMore = false
            activeLoadMoreToken = nil
        }
        do {
            let page = try await syncService.loadNext(
                pageToken: token,
                labelIDs: selectedLabelIDs
            )
            nextPageToken = page.nextPageToken
            messages.append(contentsOf: page.messages)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archive(_ message: EmailMessage) async {
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.removeAll { $0.id == message.id }
        }
        do {
            try await provider.archive(
                messageID: message.id,
                labelIDs: selectedLabelIDs
            )
        } catch {
            withAnimation(.easeInOut(duration: 0.2)) {
                messages.insert(message, at: 0)
            }
            errorMessage = error.localizedDescription
        }
    }

    func reply(to message: EmailMessage, body: String) async {
        let draft = ReplyDraft(
            messageID: message.id,
            threadID: message.threadID,
            recipient: message.senderAddress,
            subject: message.subject,
            body: body
        )
        do {
            try await provider.reply(with: draft)
            FirebaseAnalyticsService.shared.log(.replySendSuccess)
        } catch {
            FirebaseAnalyticsService.shared.log(
                .replySendFailed,
                parameters: [
                    "error_category": .string(
                        FirebaseAnalyticsService.shared.errorCategory(for: error)
                    )
                ]
            )
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await loadInitial(force: true)
    }

    func stopPolling() async {
        await syncService.stopPolling()
    }

    private func beginPolling() {
        Task {
            await syncService.startPolling(
                labelIDs: selectedLabelIDs,
                onPage: { [weak self] page in
                    Task { @MainActor in
                        guard let self else { return }
                        guard !self.matchesCurrentPage(page) else { return }
                        self.applyPollingPageUpdate(page)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                    }
                }
            )
        }
    }

    private func matchesCurrentPage(_ page: InboxPage) -> Bool {
        guard nextPageToken == page.nextPageToken else { return false }
        guard messages.count == page.messages.count else { return false }
        return zip(messages, page.messages).allSatisfy { lhs, rhs in
            lhs.id == rhs.id
        }
    }

    private func applyPollingPageUpdate(_ page: InboxPage) {
        nextPageToken = page.nextPageToken

        let currentIDs = messages.map(\.id)
        let incomingIDs = page.messages.map(\.id)

        guard currentIDs == incomingIDs else {
            messages = page.messages
            return
        }

        var updated = messages
        var changed = false
        for index in updated.indices {
            let incoming = page.messages[index]
            if updated[index] != incoming {
                updated[index] = incoming
                changed = true
            }
        }

        if changed {
            messages = updated
        }
    }
}
