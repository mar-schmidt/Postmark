import Foundation

actor InboxSyncService {
    private let provider: EmailProvider
    private var loopTask: Task<Void, Never>?
    private var isPrimarySyncInFlight = false
    private var lastChangeToken: String?

    init(provider: EmailProvider) {
        self.provider = provider
    }

    func initialLoad(labelIDs: [String]) async throws -> InboxPage {
        isPrimarySyncInFlight = true
        defer { isPrimarySyncInFlight = false }
        return try await provider.fetchInboxPage(
            pageToken: nil,
            labelIDs: labelIDs
        )
    }

    func loadNext(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage {
        isPrimarySyncInFlight = true
        defer { isPrimarySyncInFlight = false }
        return try await provider.fetchInboxPage(
            pageToken: pageToken,
            labelIDs: labelIDs
        )
    }

    /// Near-real-time polling.
    ///
    /// Each tick first asks the provider for a cheap change token
    /// (`latestChangeToken`, e.g. Gmail's `historyId`). When the token is
    /// unchanged the loop skips the expensive inbox fetch, which lets it run
    /// on a short interval — new mail surfaces within a few seconds without
    /// repeatedly pulling full message bodies. Providers without change
    /// detection fall back to fetching every tick.
    ///
    /// True server push (Gmail `users.watch` + Cloud Pub/Sub) would require a
    /// backend endpoint to receive push events; this client-only approach is
    /// the closest equivalent without standing up that infrastructure.
    func startPolling(
        labelIDs: [String],
        intervalSeconds: TimeInterval = 20,
        onPage: @escaping @Sendable (InboxPage) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        loopTask?.cancel()
        loopTask = Task {
            while !Task.isCancelled {
                if isPrimarySyncInFlight {
                    try? await Task.sleep(for: .seconds(intervalSeconds))
                    continue
                }

                // Cheap gate: only do real work when the mailbox changed.
                if let token = try? await provider.latestChangeToken() {
                    if token == lastChangeToken {
                        try? await Task.sleep(for: .seconds(intervalSeconds))
                        continue
                    }
                    lastChangeToken = token
                }

                do {
                    isPrimarySyncInFlight = true
                    let page = try await provider.fetchInboxPage(
                        pageToken: nil,
                        labelIDs: labelIDs
                    )
                    isPrimarySyncInFlight = false
                    onPage(page)
                } catch {
                    isPrimarySyncInFlight = false
                    onError(error)
                }
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    func stopPolling() {
        loopTask?.cancel()
        loopTask = nil
    }
}
