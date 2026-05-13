import Foundation

actor InboxSyncService {
    private let provider: EmailProvider
    private var loopTask: Task<Void, Never>?
    private var isPrimarySyncInFlight = false

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

    func startPolling(
        labelIDs: [String],
        intervalSeconds: TimeInterval = 45,
        onPage: @escaping @Sendable (InboxPage) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        loopTask?.cancel()
        loopTask = Task {
            while !Task.isCancelled {
                if isPrimarySyncInFlight {
                    try? await Task.sleep(
                        for: .seconds(intervalSeconds)
                    )
                    continue
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
                try? await Task.sleep(
                    for: .seconds(intervalSeconds)
                )
            }
        }
    }

    func stopPolling() {
        loopTask?.cancel()
        loopTask = nil
    }
}
