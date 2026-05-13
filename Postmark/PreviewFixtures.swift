import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum PreviewFixtures {
    static let messages: [EmailMessage] = [
        EmailMessage(
            id: "msg-001",
            threadID: "th-001",
            sender: "Jony Ive",
            senderAddress: "jony@example.com",
            subject: "Design review notes",
            snippet: "Pushed updates for the menu interaction and motion.",
            bodyText: """
            Pushed updates for the menu interaction and motion.

            The entry transition now feels less abrupt, and the archive
            affordance appears earlier in the flow.
            """,
            bodyHTML: """
            <p>Pushed updates for the menu interaction and motion.</p>
            <p>The entry transition now feels less abrupt, and the archive
            affordance appears earlier in the flow.</p>
            """,
            senderPhotoURL: nil,
            senderInitials: "JI",
            receivedAt: Date().addingTimeInterval(-1_500),
            isUnread: true
        ),
        EmailMessage(
            id: "msg-002",
            threadID: "th-002",
            sender: "Mina Lee",
            senderAddress: "mina@example.com",
            subject: "Beta feedback roundup",
            snippet: "Users like quick archive; reply needs a send indicator.",
            bodyText: """
            Users like quick archive; reply needs a send indicator.

            Several testers asked for clearer spacing in long messages.
            """,
            bodyHTML: """
            <p>Users like quick archive; reply needs a send indicator.</p>
            <p>Several testers asked for clearer spacing in long
            messages.</p>
            """,
            senderPhotoURL: nil,
            senderInitials: "ML",
            receivedAt: Date().addingTimeInterval(-7_200),
            isUnread: false
        )
    ]
}

struct PreviewEmailProvider: EmailProvider {
    let messages: [EmailMessage]

    func fetchInboxPage(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage {
        InboxPage(messages: messages, nextPageToken: nil)
    }

    func fetchLabels() async throws -> [EmailLabel] {
        [
            EmailLabel(id: "INBOX", name: "Inbox", type: "system"),
            EmailLabel(id: "STARRED", name: "Starred", type: "system")
        ]
    }

    func fetchAccountEmail() async throws -> String {
        "preview@example.com"
    }

    func reply(with draft: ReplyDraft) async throws {}

    func archive(messageID: String, labelIDs: [String]) async throws {}

    func signOut() throws {}
}

final class PreviewBillingService: BillingService {
    private let stream: AsyncStream<BillingEntitlement>
    private var continuation: AsyncStream<BillingEntitlement>.Continuation?
    private(set) var cachedEntitlement: BillingEntitlement

    var entitlementUpdates: AsyncStream<BillingEntitlement> {
        stream
    }

    init(entitlement: BillingEntitlement = .free) {
        self.cachedEntitlement = entitlement
        var localContinuation:
            AsyncStream<BillingEntitlement>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
        continuation?.yield(entitlement)
    }

    func refreshEntitlement() async -> BillingEntitlement {
        cachedEntitlement
    }

    func fetchProducts(
        timeoutSeconds: Double
    ) async throws -> [BillingProduct] {
        _ = timeoutSeconds
        return [
            BillingProduct(
                id: PaywallProductID.annual,
                displayName: "Yearly",
                displayPrice: "100 kr",
                period: .year,
                hasIntroOffer: false
            ),
            BillingProduct(
                id: PaywallProductID.monthly,
                displayName: "Monthly",
                displayPrice: "9 kr",
                period: .month,
                hasIntroOffer: true
            )
        ]
    }

    func purchase(
        productID: String,
        confirmIn window: NSWindow
    ) async throws -> BillingEntitlement {
        _ = productID
        _ = window
        cachedEntitlement = BillingEntitlement(
            tier: .pro,
            expirationDate: Date().addingTimeInterval(86_400 * 365)
        )
        continuation?.yield(cachedEntitlement)
        return cachedEntitlement
    }

    func restorePurchases() async throws -> BillingEntitlement {
        cachedEntitlement
    }
}

@MainActor
extension AppState {
    static func previewSignedOut() -> AppState {
        let state = AppState(
            billingService: PreviewBillingService(),
            accounts: [],
            editingAccountID: nil,
            shouldPoll: false
        )
        state.authState = .signedOut
        return state
    }

    static func previewSignedIn() -> AppState {
        let account = Account(
            id: UUID(),
            email: "preview@example.com",
            displayName: "Preview",
            isActiveInbox: true,
            emailOpenBehavior: .openDetail,
            selectedLabelIDs: ["INBOX"]
        )
        let provider = PreviewEmailProvider(messages: PreviewFixtures.messages)
        let state = AppState(
            billingService: PreviewBillingService(
                entitlement: BillingEntitlement(
                    tier: .pro,
                    expirationDate: Date().addingTimeInterval(86_400 * 365)
                )
            ),
            accounts: [account],
            editingAccountID: account.id,
            shouldPoll: false
        )
        state.installSessionForTesting(
            account: account,
            provider: provider,
            makeActive: true
        )
        state.inboxViewModel.messages = PreviewFixtures.messages
        state.inboxViewModel.nextPageToken = nil
        return state
    }

    static func previewSignedIn(
        accountsWithProviders: [(Account, any EmailProvider)]
    ) -> AppState {
        let normalized = AppState.normalizedAccounts(
            accountsWithProviders.map(\.0)
        )
        let state = AppState(
            billingService: PreviewBillingService(
                entitlement: BillingEntitlement(
                    tier: .pro,
                    expirationDate: Date().addingTimeInterval(86_400 * 365)
                )
            ),
            accounts: normalized,
            editingAccountID: normalized.first?.id,
            shouldPoll: false
        )
        for (index, pair) in accountsWithProviders.enumerated() {
            state.installSessionForTesting(
                account: pair.0,
                provider: pair.1,
                makeActive: index == 0
            )
        }
        return state
    }
}
