//
//  PostmarkTests.swift
//  PostmarkTests
//
//  Created by Marcus Schmidt on 2026-04-14.
//

import AppAuth
import AppKit
import Foundation
import Testing
@testable import Postmark

@Suite(.serialized)
struct PostmarkTests {
    @Test
    func gmailMapperParsesHeaders() {
        let response = GmailMessageResponse(
            id: "msg_1",
            threadID: "thr_1",
            snippet: "Hello from Postmark",
            labelIds: ["INBOX", "UNREAD"],
            internalDate: nil,
            payload: GmailPayload(
                mimeType: nil,
                headers: [
                    GmailHeader(name: "From", value: "Ada <ada@example.com>"),
                    GmailHeader(name: "Subject", value: "Status update"),
                    GmailHeader(
                        name: "Date",
                        value: "Tue, 14 Apr 2026 10:00:00 +0000"
                    )
                ],
                body: nil,
                parts: nil
            )
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(mapped.id == "msg_1")
        #expect(mapped.threadID == "thr_1")
        #expect(mapped.sender == "Ada")
        #expect(mapped.senderAddress == "ada@example.com")
        #expect(mapped.subject == "Status update")
        #expect(mapped.isUnread)
    }

    @Test
    func gmailMapperPrefersInternalDateForReceivedAt() {
        let response = GmailMessageResponse(
            id: "msg_2",
            threadID: "thr_2",
            snippet: "Internal timestamp wins",
            labelIds: ["INBOX"],
            internalDate: "1713088800000",
            payload: GmailPayload(
                mimeType: nil,
                headers: [
                    GmailHeader(name: "From", value: "Ada <ada@example.com>"),
                    GmailHeader(
                        name: "Subject",
                        value: "Timestamp priority"
                    ),
                    GmailHeader(
                        name: "Date",
                        value: "Tue, 14 Apr 2026 10:00:00 +0000"
                    )
                ],
                body: nil,
                parts: nil
            )
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(
            mapped.receivedAt == Date(timeIntervalSince1970: 1713088800)
        )
    }

    @Test
    func gmailMapperFallsBackToDistantPastForInvalidDateSources() {
        let response = GmailMessageResponse(
            id: "msg_3",
            threadID: "thr_3",
            snippet: "Invalid timestamps",
            labelIds: ["INBOX"],
            internalDate: "not-a-number",
            payload: GmailPayload(
                mimeType: nil,
                headers: [
                    GmailHeader(name: "From", value: "Ada <ada@example.com>"),
                    GmailHeader(name: "Subject", value: "Invalid date"),
                    GmailHeader(name: "Date", value: "totally invalid")
                ],
                body: nil,
                parts: nil
            )
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(mapped.receivedAt == .distantPast)
    }

    @Test
    func gmailMapperIgnoresDuplicateHeaders() {
        let response = GmailMessageResponse(
            id: "msg_4",
            threadID: "thr_4",
            snippet: "Duplicate header test",
            labelIds: ["INBOX"],
            internalDate: nil,
            payload: GmailPayload(
                mimeType: nil,
                headers: [
                    GmailHeader(name: "From", value: "Ada <ada@example.com>"),
                    GmailHeader(name: "Received", value: "hop-1"),
                    GmailHeader(name: "Received", value: "hop-2"),
                    GmailHeader(name: "Subject", value: "Duplicate received")
                ],
                body: nil,
                parts: nil
            )
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(mapped.senderAddress == "ada@example.com")
        #expect(mapped.subject == "Duplicate received")
    }

    @Test
    func gmailMapperPrefersLastAlternativePart() {
        let plainPart = GmailPayload(
            mimeType: "text/plain",
            headers: [
                GmailHeader(
                    name: "Content-Type",
                    value: "text/plain; charset=UTF-8"
                )
            ],
            body: GmailBody(size: 5, data: b64url("plain")),
            parts: nil
        )
        let firstHTMLPart = GmailPayload(
            mimeType: "text/html",
            headers: [
                GmailHeader(
                    name: "Content-Type",
                    value: "text/html; charset=UTF-8"
                )
            ],
            body: GmailBody(size: 12, data: b64url("<p>first</p>")),
            parts: nil
        )
        let preferredHTMLPart = GmailPayload(
            mimeType: "text/html",
            headers: [
                GmailHeader(
                    name: "Content-Type",
                    value: "text/html; charset=UTF-8"
                )
            ],
            body: GmailBody(size: 14, data: b64url("<p>second</p>")),
            parts: nil
        )
        let response = GmailMessageResponse(
            id: "msg_5",
            threadID: "thr_5",
            snippet: "fallback",
            labelIds: ["INBOX"],
            internalDate: nil,
            payload: GmailPayload(
                mimeType: "multipart/alternative",
                headers: [],
                body: nil,
                parts: [plainPart, firstHTMLPart, preferredHTMLPart]
            )
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(mapped.bodyHTML?.contains("second") == true)
        #expect(mapped.bodyText == "plain")
    }

    @Test
    func gmailMapperTraversesNestedMultipartPayloads() {
        let nestedPlain = GmailPayload(
            mimeType: "text/plain",
            headers: [
                GmailHeader(
                    name: "Content-Type",
                    value: "text/plain; charset=UTF-8"
                )
            ],
            body: GmailBody(size: 11, data: b64url("nested body")),
            parts: nil
        )
        let nestedHTML = GmailPayload(
            mimeType: "text/html",
            headers: [
                GmailHeader(
                    name: "Content-Type",
                    value: "text/html; charset=UTF-8"
                )
            ],
            body: GmailBody(size: 18, data: b64url("<p>nested html</p>")),
            parts: nil
        )
        let alternative = GmailPayload(
            mimeType: "multipart/alternative",
            headers: [],
            body: nil,
            parts: [nestedPlain, nestedHTML]
        )
        let mixed = GmailPayload(
            mimeType: "multipart/mixed",
            headers: [],
            body: nil,
            parts: [
                alternative,
                GmailPayload(
                    mimeType: "application/pdf",
                    headers: [],
                    body: GmailBody(size: 4, data: "dGVzdA"),
                    parts: nil
                )
            ]
        )
        let response = GmailMessageResponse(
            id: "msg_6",
            threadID: "thr_6",
            snippet: "fallback",
            labelIds: ["INBOX"],
            internalDate: nil,
            payload: mixed
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(mapped.bodyHTML?.contains("nested html") == true)
        #expect(mapped.bodyText == "nested body")
    }

    @Test
    func gmailMapperDecodesCharsetFromContentType() {
        let isoData = Data([0x63, 0x61, 0x66, 0xE9])
        let response = GmailMessageResponse(
            id: "msg_7",
            threadID: "thr_7",
            snippet: "fallback",
            labelIds: ["INBOX"],
            internalDate: nil,
            payload: GmailPayload(
                mimeType: "text/plain",
                headers: [
                    GmailHeader(
                        name: "Content-Type",
                        value: "text/plain; charset=iso-8859-1"
                    )
                ],
                body: GmailBody(
                    size: isoData.count,
                    data: isoData.base64URLEncodedString()
                ),
                parts: nil
            )
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(mapped.bodyText == "café")
    }

    @Test
    func gmailMapperRecoversFromMisdeclaredUTF8Charset() {
        let swedish = """
        Tack för att du gick med i Splitwise Pro! Här är en översikt över \
        de funktioner du har låst upp
        """
        let utf8Data = Data(swedish.utf8)
        let response = GmailMessageResponse(
            id: "msg_8",
            threadID: "thr_8",
            snippet: "fallback",
            labelIds: ["INBOX"],
            internalDate: nil,
            payload: GmailPayload(
                mimeType: "text/html",
                headers: [
                    GmailHeader(
                        name: "Content-Type",
                        value: "text/html; charset=iso-8859-1"
                    )
                ],
                body: GmailBody(
                    size: utf8Data.count,
                    data: utf8Data.base64URLEncodedString()
                ),
                parts: nil
            )
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(mapped.bodyHTML == swedish)
        #expect(mapped.bodyHTML?.contains("för") == true)
        #expect(mapped.bodyHTML?.contains("översikt") == true)
        #expect(mapped.bodyHTML?.contains("låst") == true)
    }

    @Test
    func gmailMapperPreservesUTF8WhenCharsetIsCorrect() {
        let swedish = "Här är din bekräftelse med svenska tecken: å ä ö"
        let utf8Data = Data(swedish.utf8)
        let response = GmailMessageResponse(
            id: "msg_9",
            threadID: "thr_9",
            snippet: "fallback",
            labelIds: ["INBOX"],
            internalDate: nil,
            payload: GmailPayload(
                mimeType: "text/plain",
                headers: [
                    GmailHeader(
                        name: "Content-Type",
                        value: "text/plain; charset=UTF-8"
                    )
                ],
                body: GmailBody(
                    size: utf8Data.count,
                    data: utf8Data.base64URLEncodedString()
                ),
                parts: nil
            )
        )

        let mapped = GmailMapper().mapMessage(
            from: response,
            senderPhotoURL: nil
        )

        #expect(mapped.bodyText == swedish)
    }

    @Test
    func inMemoryAuthStateStoreLifecycle() throws {
        let store = InMemoryTokenStore()
        #expect(store.loadAuthState() == nil)

        let authState = makeAuthState()
        try store.saveAuthState(authState)

        #expect(store.loadAuthState() != nil)
        try store.clearAuthState()
        #expect(store.loadAuthState() == nil)
    }

    @Test
    @MainActor
    func oauthConfigurationValidation() {
        let service = GoogleOAuthService(
            tokenStore: InMemoryTokenStore(),
            configuration: nil
        )
        guard case .missingConfiguration = service.configurationError else {
            Issue.record("Expected missingConfiguration error")
            return
        }
    }

    @Test
    @MainActor
    func appStateNormalizesSelectedLabelDefaults() {
        #expect(AppState.normalizedLabelIDs(nil) == ["INBOX"])
        #expect(AppState.normalizedLabelIDs([]) == ["INBOX"])
        #expect(
            AppState.normalizedLabelIDs(["  ", "STARRED", " "])
                == ["STARRED"]
        )
    }

    @Test
    @MainActor
    func appStateSwitchesActiveAndEditingAccounts() async {
        let firstID = UUID()
        let secondID = UUID()
        let first = Account(
            id: firstID,
            email: "first@example.com",
            displayName: "First",
            isActiveInbox: true,
            emailOpenBehavior: .openDetail,
            selectedLabelIDs: ["INBOX"]
        )
        let second = Account(
            id: secondID,
            email: "second@example.com",
            displayName: "Second",
            isActiveInbox: false,
            emailOpenBehavior: .inlineExpand,
            selectedLabelIDs: ["INBOX", "STARRED"]
        )
        let state = AppState(
            billingService: MockBillingService(),
            accounts: [first, second],
            editingAccountID: firstID,
            shouldPoll: false
        )
        state.installSessionForTesting(
            account: first,
            provider: TestEmailProvider(),
            makeActive: true
        )
        state.installSessionForTesting(
            account: second,
            provider: TestEmailProvider(),
            makeActive: false
        )

        await state.selectAccount(secondID, refreshInbox: false)

        #expect(state.activeAccount?.id == secondID)
        #expect(state.editingAccount?.id == secondID)
        #expect(state.emailOpenBehavior == .inlineExpand)
    }

    @Test
    @MainActor
    func appStateUpdatesOnlyEditingAccountLabels() async {
        let firstID = UUID()
        let secondID = UUID()
        let first = Account(
            id: firstID,
            email: "first@example.com",
            displayName: "First",
            isActiveInbox: true,
            emailOpenBehavior: .openDetail,
            selectedLabelIDs: ["INBOX"]
        )
        let second = Account(
            id: secondID,
            email: "second@example.com",
            displayName: "Second",
            isActiveInbox: false,
            emailOpenBehavior: .openDetail,
            selectedLabelIDs: ["INBOX", "STARRED"]
        )
        let state = AppState(
            billingService: MockBillingService(),
            accounts: [first, second],
            editingAccountID: secondID,
            shouldPoll: false
        )
        state.installSessionForTesting(
            account: first,
            provider: TestEmailProvider(),
            makeActive: false
        )
        state.installSessionForTesting(
            account: second,
            provider: TestEmailProvider(),
            makeActive: true
        )

        await state.updateEditingAccountLabelIDs(["INBOX", "IMPORTANT"])

        let updatedFirst = state.accounts.first(where: { $0.id == firstID })
        let updatedSecond = state.accounts.first(where: { $0.id == secondID })
        #expect(updatedFirst?.selectedLabelIDs == ["INBOX"])
        #expect(updatedSecond?.selectedLabelIDs == ["INBOX", "IMPORTANT"])
    }

    @Test
    @MainActor
    func removingLastAccountSignsOut() async {
        let account = Account(
            id: UUID(),
            email: "one@example.com",
            displayName: "One",
            isActiveInbox: true,
            emailOpenBehavior: .openDetail,
            selectedLabelIDs: ["INBOX"]
        )
        let state = AppState(
            billingService: MockBillingService(),
            accounts: [account],
            editingAccountID: account.id,
            shouldPoll: false
        )
        state.installSessionForTesting(
            account: account,
            provider: TestEmailProvider(),
            makeActive: true
        )

        await state.removeAccount(account.id)

        #expect(state.accounts.isEmpty)
        #expect(state.authState == .signedOut)
    }

    @Test
    @MainActor
    func additionalAccountRequiresProEntitlement() {
        let account = Account(
            id: UUID(),
            email: "one@example.com",
            displayName: "One",
            isActiveInbox: true,
            emailOpenBehavior: .inlineExpand,
            selectedLabelIDs: ["INBOX"]
        )
        let billing = MockBillingService(entitlement: .free)
        let state = AppState(
            billingService: billing,
            accounts: [account],
            editingAccountID: account.id,
            shouldPoll: false
        )

        #expect(state.canAddAnotherAccount == false)
        #expect(state.requestAddAccountAccess() == false)
        #expect(state.isPaywallPresented)
    }

    @Test
    @MainActor
    func additionalAccountAllowedForProEntitlement() {
        let account = Account(
            id: UUID(),
            email: "one@example.com",
            displayName: "One",
            isActiveInbox: true,
            emailOpenBehavior: .inlineExpand,
            selectedLabelIDs: ["INBOX"]
        )
        let billing = MockBillingService(
            entitlement: BillingEntitlement(
                tier: .pro,
                expirationDate: Date().addingTimeInterval(86_400)
            )
        )
        let state = AppState(
            billingService: billing,
            accounts: [account],
            editingAccountID: account.id,
            shouldPoll: false
        )

        #expect(state.isSubscriptionActive)
        #expect(state.canAddAnotherAccount)
        #expect(state.requestAddAccountAccess())
    }

    @Test
    @MainActor
    func paywallLoadsProductsAndPurchasesSuccessfully() async {
        let billing = MockBillingService(entitlement: .free)
        billing.products = [
            BillingProduct(
                id: PaywallProductID.annual,
                displayName: "Yearly",
                displayPrice: "100 kr",
                period: .year,
                hasIntroOffer: true
            )
        ]
        billing.purchaseEntitlement = BillingEntitlement(
            tier: .pro,
            expirationDate: Date().addingTimeInterval(86_400)
        )
        let account = Account(
            id: UUID(),
            email: "one@example.com",
            displayName: "One",
            isActiveInbox: true,
            emailOpenBehavior: .inlineExpand,
            selectedLabelIDs: ["INBOX"]
        )
        let state = AppState(
            billingService: billing,
            validatePurchaseWindowVisibility: false,
            accounts: [account],
            editingAccountID: account.id,
            shouldPoll: false
        )
        let purchaseWindow = NSWindow()

        await state.loadPaywallProducts(force: true)
        #expect(state.paywallProducts.count == 1)
        #expect(state.paywallState == PaywallState.loaded)
        state.selectedPaywallProductID = PaywallProductID.annual
        await state.purchaseSelectedPaywallProduct(confirmIn: purchaseWindow)

        #expect(state.isSubscriptionActive)
        #expect(state.paywallState == PaywallState.loaded)
    }

    @Test
    @MainActor
    func paywallShowsErrorWhenProductsFailToLoad() async {
        let billing = MockBillingService(entitlement: .free)
        billing.fetchError = BillingError.timedOut
        let state = AppState(
            billingService: billing,
            accounts: [],
            editingAccountID: nil,
            shouldPoll: false
        )

        await state.loadPaywallProducts(force: true)
        if case .error(let message) = state.paywallState {
            #expect(message.contains("too long"))
        } else {
            Issue.record("Expected paywall error state")
        }
    }

    @Test
    @MainActor
    func purchaseRequiresAvailableWindowAnchor() async {
        let billing = MockBillingService(entitlement: .free)
        let state = AppState(
            billingService: billing,
            accounts: [],
            editingAccountID: nil,
            shouldPoll: false
        )
        state.selectedPaywallProductID = PaywallProductID.monthly

        await state.purchaseSelectedPaywallProduct()

        if case .error(let message) = state.paywallState {
            #expect(message.contains("main Postmark window"))
        } else {
            Issue.record("Expected missing window anchor error state")
        }
    }

    @Test
    @MainActor
    func purchaseRejectsStaleWindowWhenValidationEnabled() async {
        let billing = MockBillingService(entitlement: .free)
        let state = AppState(
            billingService: billing,
            accounts: [],
            editingAccountID: nil,
            shouldPoll: false
        )
        state.selectedPaywallProductID = PaywallProductID.monthly
        let staleWindow = NSWindow()

        await state.purchaseSelectedPaywallProduct(confirmIn: staleWindow)

        if case .error(let message) = state.paywallState {
            #expect(message.contains("main Postmark window"))
        } else {
            Issue.record("Expected stale window error state")
        }
    }

    @Test
    @MainActor
    func billingInProgressTracksPurchaseLifecycle() async {
        let billing = MockBillingService(entitlement: .free)
        billing.purchaseDelaySeconds = 0.08
        billing.purchaseEntitlement = BillingEntitlement(
            tier: .pro,
            expirationDate: Date().addingTimeInterval(86_400)
        )
        let state = AppState(
            billingService: billing,
            purchaseTimeoutSeconds: 1,
            validatePurchaseWindowVisibility: false,
            accounts: [],
            editingAccountID: nil,
            shouldPoll: false
        )
        let purchaseWindow = NSWindow()
        state.selectedPaywallProductID = PaywallProductID.monthly

        let task = Task {
            await state.purchaseSelectedPaywallProduct(
                confirmIn: purchaseWindow
            )
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(state.isBillingInProgress)
        await task.value
        #expect(state.isBillingInProgress == false)
        #expect(state.paywallState == PaywallState.loaded)
    }

    @Test
    @MainActor
    func purchaseTimeoutReturnsToErrorState() async {
        let billing = MockBillingService(entitlement: .free)
        billing.purchaseDelaySeconds = 0.2
        let state = AppState(
            billingService: billing,
            purchaseTimeoutSeconds: 0.03,
            validatePurchaseWindowVisibility: false,
            accounts: [],
            editingAccountID: nil,
            shouldPoll: false
        )
        let purchaseWindow = NSWindow()
        state.selectedPaywallProductID = PaywallProductID.monthly

        await state.purchaseSelectedPaywallProduct(confirmIn: purchaseWindow)

        #expect(state.isBillingInProgress == false)
        if case .error(let message) = state.paywallState {
            #expect(message.contains("timed out"))
        } else {
            Issue.record("Expected timeout error state")
        }
    }

    @Test
    func keychainStoreRoundTripWithAuthStateArchive() throws {
        let store = InMemoryTokenStore()
        let authState = makeAuthState()
        try store.saveAuthState(authState)

        guard let loaded = store.loadAuthState() else {
            Issue.record("Auth state not loaded from store")
            return
        }
        #expect(loaded.lastAuthorizationResponse != nil)
    }

    private func makeAuthState() -> OIDAuthState {
        let serviceConfiguration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string:
                "https://accounts.google.com/o/oauth2/v2/auth"
            )!,
            tokenEndpoint: URL(string:
                "https://oauth2.googleapis.com/token"
            )!
        )
        let request = OIDAuthorizationRequest(
            configuration: serviceConfiguration,
            clientId: "client-id",
            clientSecret: nil,
            scopes: ["openid"],
            redirectURL: URL(string: "com.decoded.Postmark:/oauth2redirect")!,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["state": "test-state"]
        )

        let parameters: [String: NSObject & NSCopying] = [
            "code": "test-code" as NSString,
            "state": "test-state" as NSString
        ]
        let response = OIDAuthorizationResponse(
            request: request,
            parameters: parameters
        )
        return OIDAuthState(authorizationResponse: response)
    }

    private func b64url(_ value: String) -> String {
        value.data(using: .utf8)!.base64URLEncodedString()
    }
}

private struct TestEmailProvider: EmailProvider {
    func fetchInboxPage(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage {
        InboxPage(messages: [], nextPageToken: nil)
    }

    func fetchLabels() async throws -> [EmailLabel] { [] }

    func fetchAccountEmail() async throws -> String {
        "test@example.com"
    }

    func reply(with draft: ReplyDraft) async throws {}

    func archive(messageID: String, labelIDs: [String]) async throws {}

    func signOut() throws {}
}

private final class MockBillingService: BillingService {
    var cachedEntitlement: BillingEntitlement
    var entitlementUpdates: AsyncStream<BillingEntitlement> { stream }
    var products: [BillingProduct] = []
    var fetchError: Error?
    var purchaseError: Error?
    var purchaseEntitlement: BillingEntitlement
    var purchaseDelaySeconds: Double = 0

    private let stream: AsyncStream<BillingEntitlement>
    private var continuation: AsyncStream<BillingEntitlement>.Continuation?

    init(entitlement: BillingEntitlement = .free) {
        self.cachedEntitlement = entitlement
        self.purchaseEntitlement = entitlement
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
        if let fetchError {
            throw fetchError
        }
        return products
    }

    func purchase(
        productID: String,
        confirmIn window: NSWindow
    ) async throws -> BillingEntitlement {
        _ = productID
        _ = window
        if purchaseDelaySeconds > 0 {
            let nanos = UInt64(purchaseDelaySeconds * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanos)
        }
        if let purchaseError {
            throw purchaseError
        }
        cachedEntitlement = purchaseEntitlement
        continuation?.yield(purchaseEntitlement)
        return purchaseEntitlement
    }

    func restorePurchases() async throws -> BillingEntitlement {
        cachedEntitlement
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
