import Combine
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AppState: ObservableObject {
    @Published var accounts: [Account] {
        didSet {
            persistAccounts()
        }
    }
    @Published var editingAccountID: UUID? {
        didSet {
            UserDefaults.standard.set(
                editingAccountID?.uuidString,
                forKey: Self.editingAccountIDKey
            )
        }
    }
    @Published var authState: AuthState = .signedOut
    @Published var errorMessage: String?
    @Published var inboxViewModel: InboxViewModel
    @Published var billingEntitlement: BillingEntitlement
    @Published var paywallProducts: [BillingProduct] = []
    @Published var paywallState: PaywallState = .idle
    @Published var isPaywallPresented = false
    @Published var selectedPaywallProductID: String?

    private(set) var unreadCountsByAccountID: [UUID: Int] = [:]
    let providerManager: ProviderManager
    private let keychainTokenStore: KeychainTokenStore
    private let billingService: any BillingService
    private let shouldPoll: Bool
    private let purchaseTimeoutSeconds: Double
    private let validatePurchaseWindowVisibility: Bool
    private weak var purchaseConfirmWindow: NSWindow?
    private var sessionsByAccountID: [UUID: AccountSession] = [:]

    private static let accountsKey = "accounts"
    private static let editingAccountIDKey = "editingAccountID"
    private static let uiTestInboxArgument = "--uitest-inbox"
    private static let uiTestPaywallPurchasingArgument =
        "--uitest-paywall-purchasing"
    private static let uiTestPaywallReadyArgument = "--uitest-paywall-ready"
    static let defaultLabelID = "INBOX"

    init(
        providerManager: ProviderManager? = nil,
        keychainTokenStore: KeychainTokenStore? = nil,
        billingService: (any BillingService)? = nil,
        purchaseTimeoutSeconds: Double = 30,
        validatePurchaseWindowVisibility: Bool = true,
        accounts: [Account]? = nil,
        editingAccountID: UUID? = nil,
        shouldPoll: Bool = !ProcessInfo.processInfo.environment.keys.contains(
            "XCODE_RUNNING_FOR_PREVIEWS"
        )
    ) {
        self.providerManager = providerManager ?? ProviderManager()
        self.keychainTokenStore = keychainTokenStore ?? KeychainTokenStore()
        self.billingService = billingService ?? StoreKitBillingService()
        self.purchaseTimeoutSeconds = purchaseTimeoutSeconds
        self.validatePurchaseWindowVisibility = validatePurchaseWindowVisibility
        self.shouldPoll = shouldPoll
        self.accounts = Self.loadAccountsOverrideAware(accounts: accounts)
        self.editingAccountID = Self.loadEditingOverrideAware(
            editingAccountID: editingAccountID
        )
        self.billingEntitlement = self.billingService.cachedEntitlement
        let placeholderProvider = PlaceholderEmailProvider()
        let placeholderSync = InboxSyncService(provider: placeholderProvider)
        self.inboxViewModel = InboxViewModel(
            provider: placeholderProvider,
            syncService: placeholderSync,
            shouldPoll: false
        )
        normalizeAccountSelection()
        observeEntitlements()
        Task {
            _ = await refreshEntitlementState()
        }
    }

    static func bootstrap() -> AppState {
        let processInfo = ProcessInfo.processInfo
        let arguments = processInfo.arguments
        if arguments.contains(uiTestInboxArgument) {
            return makeUITestInboxState()
        }
        let environment = processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil {
            let state = AppState(
                accounts: [],
                editingAccountID: nil,
                shouldPoll: false
            )
            state.authState = .signedOut
            return state
        }
        let state = AppState()
        Task { @MainActor in
            await state.restorePersistedSessions()
            await state.runStartupSyncIfNeeded()
        }
        return state
    }

    private static func makeUITestInboxState() -> AppState {
        let arguments = ProcessInfo.processInfo.arguments
        let shouldUseUITestBilling =
            arguments.contains(uiTestPaywallPurchasingArgument)
            || arguments.contains(uiTestPaywallReadyArgument)
        let accountID = UUID()
        let account = Account(
            id: accountID,
            email: "uitest@example.com",
            displayName: "UITest",
            isActiveInbox: true,
            emailOpenBehavior: .openDetail,
            selectedLabelIDs: [defaultLabelID]
        )
        let state = AppState(
            billingService: shouldUseUITestBilling
                ? UITestBillingService()
                : nil,
            validatePurchaseWindowVisibility: false,
            accounts: [account],
            editingAccountID: accountID,
            shouldPoll: false
        )
        let provider = UITestEmailProvider(messages: [
            EmailMessage(
                id: "uitest-msg-001",
                threadID: "uitest-thr-001",
                sender: "UI Test Sender",
                senderAddress: "sender@example.com",
                subject: "Swipe action regression fixture",
                snippet: "Use this message to validate swipe actions.",
                bodyText: "Use this message to validate swipe actions.",
                bodyHTML: nil,
                senderPhotoURL: nil,
                senderInitials: "UT",
                receivedAt: Date(),
                isUnread: true
            )
        ])
        state.installSessionForTesting(
            account: account,
            provider: provider,
            makeActive: true
        )
        if arguments.contains(uiTestPaywallPurchasingArgument) {
            state.paywallProducts = [
                BillingProduct(
                    id: PaywallProductID.monthly,
                    displayName: "Monthly",
                    displayPrice: "9 kr",
                    period: .month,
                    hasIntroOffer: true
                )
            ]
            state.selectedPaywallProductID = PaywallProductID.monthly
            state.isPaywallPresented = true
            state.paywallState = PaywallState.purchasing(
                PaywallProductID.monthly
            )
        } else if arguments.contains(uiTestPaywallReadyArgument) {
            state.paywallProducts = [
                BillingProduct(
                    id: PaywallProductID.monthly,
                    displayName: "Monthly",
                    displayPrice: "9 kr",
                    period: .month,
                    hasIntroOffer: true
                )
            ]
            state.selectedPaywallProductID = PaywallProductID.monthly
            state.isPaywallPresented = true
            state.paywallState = PaywallState.loaded
        }
        return state
    }

    var activeAccount: Account? {
        accounts.first(where: \.isActiveInbox)
    }

    var isSubscriptionActive: Bool {
        billingEntitlement.isActive
    }

    var canAddAnotherAccount: Bool {
        accounts.count < 1 || isSubscriptionActive
    }

    var isBillingInProgress: Bool {
        switch paywallState {
        case .purchasing, .restoring:
            return true
        default:
            return false
        }
    }

    var editingAccount: Account? {
        guard let editingAccountID else { return nil }
        return accounts.first { $0.id == editingAccountID }
    }

    var emailOpenBehavior: EmailOpenBehavior {
        get { activeAccount?.emailOpenBehavior ?? .inlineExpand }
        set { updateActiveAccountEmailBehavior(newValue) }
    }

    var selectedLabelIDs: [String] {
        get {
            activeAccount?.selectedLabelIDs ?? [Self.defaultLabelID]
        }
        set {
            updateActiveAccountLabelIDs(newValue)
        }
    }

    func unreadCount(for accountID: UUID) -> Int {
        unreadCountsByAccountID[accountID] ?? 0
    }

    func selectAccount(
        _ accountID: UUID,
        refreshInbox: Bool = true
    ) async {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        var updated = accounts.map { account in
            var copy = account
            copy.isActiveInbox = copy.id == accountID
            return copy
        }
        updated = Self.normalizedAccounts(updated)
        accounts = updated
        editingAccountID = accountID
        activateSession(for: accountID)
        if refreshInbox {
            await inboxViewModel.refresh()
            refreshUnreadCount(for: accountID)
        }
    }

    func updateEditingAccountEmailBehavior(
        _ behavior: EmailOpenBehavior
    ) {
        guard let editingAccountID else { return }
        updateAccount(id: editingAccountID) { account in
            account.emailOpenBehavior = behavior
        }
    }

    func updateEditingAccountLabelIDs(_ raw: [String]) async {
        guard let editingAccountID else { return }
        let normalized = Self.normalizedLabelIDs(raw)
        updateAccount(id: editingAccountID) { account in
            account.selectedLabelIDs = normalized
        }
        guard activeAccount?.id == editingAccountID else { return }
        inboxViewModel.selectedLabelIDs = normalized
        await inboxViewModel.refresh()
        refreshUnreadCount(for: editingAccountID)
    }

    func removeAccount(_ accountID: UUID) async {
        guard let session = sessionsByAccountID[accountID] else { return }
        await session.syncService.stopPolling()
        do {
            try session.provider.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        sessionsByAccountID.removeValue(forKey: accountID)
        providerManager.removeProvider(for: accountID)
        unreadCountsByAccountID.removeValue(forKey: accountID)
        accounts.removeAll { $0.id == accountID }

        if accounts.isEmpty {
            await signOut()
            return
        }

        let nextActive = activeAccount?.id ?? accounts.first?.id
        if let nextActive {
            await selectAccount(nextActive, refreshInbox: true)
        }
    }

    func requestAddAccountAccess() -> Bool {
        guard !canAddAnotherAccount else { return true }
        presentPaywall()
        return false
    }

    func presentPaywall() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPaywallPresented = true
        }
        FirebaseAnalyticsService.shared.log(.paywallPresented)
        if paywallProducts.isEmpty {
            Task {
                await loadPaywallProducts()
            }
        }
    }

    func dismissPaywall() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPaywallPresented = false
        }
    }

    func loadPaywallProducts(force: Bool = false) async {
        if !force && !paywallProducts.isEmpty {
            paywallState = .loaded
            return
        }
        paywallState = .loading
        do {
            let loaded = try await billingService.fetchProducts(
                timeoutSeconds: 4
            )
            paywallProducts = loaded
            if selectedPaywallProductID == nil {
                selectedPaywallProductID = loaded.first?.id
            }
            paywallState = .loaded
        } catch {
            paywallState = .error(error.localizedDescription)
        }
    }

    func purchaseSelectedPaywallProduct() async {
        guard let selectedPaywallProductID else { return }
        await purchasePaywallProduct(productID: selectedPaywallProductID)
    }

    func purchaseSelectedPaywallProduct(confirmIn window: NSWindow?) async {
        if let window {
            updatePurchaseConfirmWindow(window)
        }
        await purchaseSelectedPaywallProduct()
    }

    func updatePurchaseConfirmWindow(_ window: NSWindow?) {
        purchaseConfirmWindow = window
    }

    func purchasePaywallProduct(productID: String) async {
        guard let purchaseConfirmWindow,
            validatePurchaseConfirmWindow(purchaseConfirmWindow)
        else {
            paywallState = .error(
                AppStateError.purchaseWindowUnavailable.localizedDescription
            )
            logPurchase("purchase blocked: missing or invalid window")
            return
        }
        logPurchase(
            "purchase start product=\(productID) "
                + "window=\(purchaseConfirmWindow.windowNumber) "
                + "visible=\(purchaseConfirmWindow.isVisible)"
        )
        paywallState = .purchasing(productID)
        FirebaseAnalyticsService.shared.log(
            .paywallPurchaseStarted,
            parameters: ["product_id": .string(productID)]
        )
        do {
            let entitlement = try await withPurchaseTimeout {
                try await self.billingService.purchase(
                    productID: productID,
                    confirmIn: purchaseConfirmWindow
                )
            }
            applyEntitlement(entitlement)
            paywallState = .loaded
            logPurchase("purchase success product=\(productID)")
            if entitlement.isActive {
                isPaywallPresented = false
            }
            FirebaseAnalyticsService.shared.log(
                .paywallPurchaseSucceeded,
                parameters: ["product_id": .string(productID)]
            )
        } catch BillingError.purchaseCancelled {
            paywallState = .loaded
            logPurchase("purchase cancelled product=\(productID)")
            FirebaseAnalyticsService.shared.log(
                .paywallPurchaseCancelled,
                parameters: ["product_id": .string(productID)]
            )
        } catch {
            paywallState = .error(error.localizedDescription)
            logPurchase(
                "purchase failed product=\(productID) "
                    + "error=\(error.localizedDescription)"
            )
            FirebaseAnalyticsService.shared.log(
                .paywallPurchaseFailed,
                parameters: [
                    "product_id": .string(productID),
                    "error_category": .string(
                        FirebaseAnalyticsService.shared.errorCategory(
                            for: error
                        )
                    )
                ]
            )
        }
    }

    func restorePaywallPurchases() async {
        paywallState = .restoring
        FirebaseAnalyticsService.shared.log(.paywallRestoreStarted)
        do {
            let entitlement = try await billingService.restorePurchases()
            applyEntitlement(entitlement)
            paywallState = .loaded
            if entitlement.isActive {
                isPaywallPresented = false
            }
            FirebaseAnalyticsService.shared.log(
                .paywallRestoreSucceeded
            )
        } catch {
            paywallState = .error(error.localizedDescription)
            FirebaseAnalyticsService.shared.log(
                .paywallRestoreFailed,
                parameters: [
                    "error_category": .string(
                        FirebaseAnalyticsService.shared.errorCategory(
                            for: error
                        )
                    )
                ]
            )
        }
    }

    @discardableResult
    func refreshEntitlementState() async -> BillingEntitlement {
        let entitlement = await billingService.refreshEntitlement()
        applyEntitlement(entitlement)
        return entitlement
    }

    func connectNewGoogleAccount() async throws -> Account {
        guard canAddAnotherAccount else {
            presentPaywall()
            throw AppStateError.proRequiredForMultipleAccounts
        }
        let session = try await createAuthenticatedSession()
        let newAccount = Account(
            id: session.id,
            email: session.email,
            displayName: session.email.localizedUsername,
            isActiveInbox: true,
            emailOpenBehavior: .inlineExpand,
            selectedLabelIDs: [Self.defaultLabelID]
        )
        registerSession(
            session,
            account: newAccount,
            makeActive: true
        )
        authState = .signedIn
        await inboxViewModel.refresh()
        refreshUnreadCount(for: newAccount.id)
        FirebaseAnalyticsService.shared.log(.authSignInSuccess)
        return newAccount
    }

    func signOut() async {
        for session in sessionsByAccountID.values {
            await session.syncService.stopPolling()
            try? session.provider.signOut()
        }
        sessionsByAccountID.removeAll()
        providerManager.clear()
        unreadCountsByAccountID.removeAll()
        accounts = []
        editingAccountID = nil
        inboxViewModel.messages = []
        inboxViewModel.nextPageToken = nil
        inboxViewModel.errorMessage = nil
        authState = .signedOut
        FirebaseAnalyticsService.shared.log(.authSignOut)
    }

    func runStartupSyncIfNeeded() async {
        guard authState == .signedIn else { return }
        await inboxViewModel.ensureInitialLoaded()
        if let activeID = activeAccount?.id {
            refreshUnreadCount(for: activeID)
        }
    }

    func installSessionForTesting(
        account: Account,
        provider: any EmailProvider,
        makeActive: Bool
    ) {
        let syncService = InboxSyncService(provider: provider)
        let viewModel = InboxViewModel(
            provider: provider,
            syncService: syncService,
            shouldPoll: false
        )
        viewModel.selectedLabelIDs = account.selectedLabelIDs
        let session = AccountSession(
            id: account.id,
            email: account.email,
            provider: provider,
            syncService: syncService,
            inboxViewModel: viewModel
        )
        registerSession(session, account: account, makeActive: makeActive)
        authState = .signedIn
    }

    private func restorePersistedSessions() async {
        sessionsByAccountID.removeAll()
        providerManager.clear()
        unreadCountsByAccountID.removeAll()

        var validAccounts: [Account] = []
        for account in accounts {
            let scopedStore = keychainTokenStore.scopedStore(for: account.id)
            let oauth = GoogleOAuthService(tokenStore: scopedStore)
            await oauth.restoreSessionFromStore()
            guard oauth.hasValidSession else { continue }
            let provider = GmailProvider(
                authService: oauth,
                apiClient: GmailAPIClient(authService: oauth)
            )
            let syncService = InboxSyncService(provider: provider)
            let viewModel = InboxViewModel(
                provider: provider,
                syncService: syncService,
                shouldPoll: shouldPoll
            )
            viewModel.selectedLabelIDs = account.selectedLabelIDs
            let session = AccountSession(
                id: account.id,
                email: account.email,
                provider: provider,
                syncService: syncService,
                inboxViewModel: viewModel
            )
            sessionsByAccountID[account.id] = session
            providerManager.register(provider: provider, for: account.id)
            validAccounts.append(account)
        }

        accounts = Self.normalizedAccounts(validAccounts)
        normalizeAccountSelection()
        if sessionsByAccountID.isEmpty {
            await migrateLegacySessionIfNeeded()
        }
        authState = sessionsByAccountID.isEmpty ? .signedOut : .signedIn
        if let activeID = activeAccount?.id {
            activateSession(for: activeID)
        }
    }

    private func migrateLegacySessionIfNeeded() async {
        guard accounts.isEmpty else { return }
        let legacyStore = KeychainTokenStore()
        guard let state = legacyStore.loadAuthState() else { return }

        let migratedID = UUID()
        let scoped = keychainTokenStore.scopedStore(for: migratedID)
        do {
            try scoped.saveAuthState(state)
            try legacyStore.clearAuthState()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let oauth = GoogleOAuthService(tokenStore: scoped)
        await oauth.restoreSessionFromStore()
        guard oauth.hasValidSession else { return }
        let provider = GmailProvider(
            authService: oauth,
            apiClient: GmailAPIClient(authService: oauth)
        )
        let email = (try? await provider.fetchAccountEmail())
            ?? "account@gmail.com"
        let account = Account(
            id: migratedID,
            email: email,
            displayName: email.localizedUsername,
            isActiveInbox: true,
            emailOpenBehavior: .inlineExpand,
            selectedLabelIDs: [Self.defaultLabelID]
        )
        let syncService = InboxSyncService(provider: provider)
        let viewModel = InboxViewModel(
            provider: provider,
            syncService: syncService,
            shouldPoll: shouldPoll
        )
        viewModel.selectedLabelIDs = account.selectedLabelIDs
        let session = AccountSession(
            id: migratedID,
            email: email,
            provider: provider,
            syncService: syncService,
            inboxViewModel: viewModel
        )
        registerSession(session, account: account, makeActive: true)
    }

    private func createAuthenticatedSession() async throws -> AccountSession {
        let sessionID = UUID()
        let scopedStore = keychainTokenStore.scopedStore(for: sessionID)
        let oauth = GoogleOAuthService(tokenStore: scopedStore)
        if let configError = oauth.configurationError {
            throw configError
        }
        try await oauth.authorize()
        let provider = GmailProvider(
            authService: oauth,
            apiClient: GmailAPIClient(authService: oauth)
        )
        let email = try await provider.fetchAccountEmail()
        let syncService = InboxSyncService(provider: provider)
        let viewModel = InboxViewModel(
            provider: provider,
            syncService: syncService,
            shouldPoll: shouldPoll
        )
        viewModel.selectedLabelIDs = [Self.defaultLabelID]
        return AccountSession(
            id: sessionID,
            email: email,
            provider: provider,
            syncService: syncService,
            inboxViewModel: viewModel
        )
    }

    private func registerSession(
        _ session: AccountSession,
        account: Account,
        makeActive: Bool
    ) {
        sessionsByAccountID[session.id] = session
        providerManager.register(provider: session.provider, for: session.id)
        var updated = accounts.filter { $0.id != account.id }
        updated.append(account)
        if makeActive {
            updated = updated.map { item in
                var copy = item
                copy.isActiveInbox = copy.id == account.id
                return copy
            }
            editingAccountID = account.id
            activateSession(for: account.id)
        }
        accounts = Self.normalizedAccounts(updated)
        normalizeAccountSelection()
    }

    private func normalizeAccountSelection() {
        accounts = Self.normalizedAccounts(accounts)
        if let editingAccountID,
            accounts.contains(where: { $0.id == editingAccountID }) {
            return
        }
        editingAccountID = accounts.first?.id
    }

    private func persistAccounts() {
        do {
            let data = try JSONEncoder().encode(accounts)
            UserDefaults.standard.set(data, forKey: Self.accountsKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activateSession(for accountID: UUID) {
        guard let session = sessionsByAccountID[accountID] else { return }
        providerManager.activeAccountID = accountID
        inboxViewModel = session.inboxViewModel
    }

    private func updateAccount(
        id: UUID,
        mutate: (inout Account) -> Void
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        var copy = accounts[index]
        mutate(&copy)
        accounts[index] = copy
    }

    private func updateActiveAccountEmailBehavior(
        _ behavior: EmailOpenBehavior
    ) {
        guard let activeID = activeAccount?.id else { return }
        updateAccount(id: activeID) { account in
            account.emailOpenBehavior = behavior
        }
    }

    private func updateActiveAccountLabelIDs(_ raw: [String]) {
        guard let activeID = activeAccount?.id else { return }
        let normalized = Self.normalizedLabelIDs(raw)
        updateAccount(id: activeID) { account in
            account.selectedLabelIDs = normalized
        }
        inboxViewModel.selectedLabelIDs = normalized
        Task {
            await inboxViewModel.refresh()
            refreshUnreadCount(for: activeID)
        }
    }

    private func observeEntitlements() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await entitlement in billingService.entitlementUpdates {
                applyEntitlement(entitlement)
            }
        }
    }

    private func applyEntitlement(_ entitlement: BillingEntitlement) {
        billingEntitlement = entitlement
        if entitlement.isActive == false && accounts.count > 1 {
            isPaywallPresented = true
        }
    }

    private func withPurchaseTimeout<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask { [purchaseTimeoutSeconds] in
                let nanos = UInt64(purchaseTimeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                throw AppStateError.purchaseTimedOut
            }
            guard let value = try await group.next() else {
                throw AppStateError.purchaseTimedOut
            }
            group.cancelAll()
            return value
        }
    }

    private func validatePurchaseConfirmWindow(_ window: NSWindow) -> Bool {
        guard validatePurchaseWindowVisibility else { return true }
        guard window.isVisible else { return false }
        return window.occlusionState.contains(.visible)
    }

    private func logPurchase(_ message: String) {
#if DEBUG
        print("[PaywallPurchase] \(message)")
#endif
    }

    private func refreshUnreadCount(for accountID: UUID) {
        unreadCountsByAccountID[accountID] = inboxViewModel.messages.count
    }
}

extension AppState {
    static func normalizedAccounts(_ raw: [Account]) -> [Account] {
        var mapped = raw.map { account in
            var copy = account
            copy.selectedLabelIDs = normalizedLabelIDs(copy.selectedLabelIDs)
            return copy
        }
        guard !mapped.isEmpty else { return [] }
        let activeCount = mapped.filter(\.isActiveInbox).count
        if activeCount == 1 { return mapped }
        mapped = mapped.enumerated().map { index, account in
            var copy = account
            copy.isActiveInbox = index == 0
            return copy
        }
        return mapped
    }

    static func normalizedLabelIDs(_ raw: [String]?) -> [String] {
        let trimmed = (raw ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return trimmed.isEmpty ? [defaultLabelID] : trimmed
    }

    private static func loadAccountsOverrideAware(
        accounts: [Account]?
    ) -> [Account] {
        if let accounts {
            return normalizedAccounts(accounts)
        }
        guard
            let data = UserDefaults.standard.data(forKey: accountsKey),
            let decoded = try? JSONDecoder().decode([Account].self, from: data)
        else {
            return []
        }
        return normalizedAccounts(decoded)
    }

    private static func loadEditingOverrideAware(
        editingAccountID: UUID?
    ) -> UUID? {
        if let editingAccountID {
            return editingAccountID
        }
        guard let raw = UserDefaults.standard.string(
            forKey: editingAccountIDKey
        )
        else {
            return nil
        }
        return UUID(uuidString: raw)
    }
}

enum AuthState: Equatable {
    case signedIn
    case signedOut
}

enum AppStateError: LocalizedError {
    case proRequiredForMultipleAccounts
    case purchaseTimedOut
    case purchaseWindowUnavailable

    var errorDescription: String? {
        switch self {
        case .proRequiredForMultipleAccounts:
            return "Postmark Pro is required to add more than one account."
        case .purchaseTimedOut:
            return "Purchase timed out. Keep this window open and try again."
        case .purchaseWindowUnavailable:
            return "Open the main Postmark window and try purchase again."
        }
    }
}

enum EmailOpenBehavior: String, CaseIterable, Identifiable, Codable {
    case inlineExpand
    case openDetail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inlineExpand:
            return "Inline Expand"
        case .openDetail:
            return "Open Detail View"
        }
    }
}

private struct AccountSession {
    let id: UUID
    let email: String
    let provider: any EmailProvider
    let syncService: InboxSyncService
    let inboxViewModel: InboxViewModel
}

private struct PlaceholderEmailProvider: EmailProvider {
    func fetchInboxPage(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage {
        InboxPage(messages: [], nextPageToken: nil)
    }

    func fetchLabels() async throws -> [EmailLabel] {
        []
    }

    func fetchAccountEmail() async throws -> String {
        ""
    }

    func reply(with draft: ReplyDraft) async throws {}

    func archive(messageID: String, labelIDs: [String]) async throws {}

    func signOut() throws {}
}

private final class UITestBillingService: BillingService {
    var cachedEntitlement: BillingEntitlement = .free
    var entitlementUpdates: AsyncStream<BillingEntitlement> { stream }
    private let stream: AsyncStream<BillingEntitlement>
    private var continuation: AsyncStream<BillingEntitlement>.Continuation?

    init() {
        var localContinuation:
            AsyncStream<BillingEntitlement>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
        continuation?.yield(.free)
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
        try await Task.sleep(nanoseconds: 3_000_000_000)
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

private struct UITestEmailProvider: EmailProvider {
    let messages: [EmailMessage]

    func fetchInboxPage(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage {
        InboxPage(messages: messages, nextPageToken: nil)
    }

    func fetchLabels() async throws -> [EmailLabel] {
        [EmailLabel(id: "INBOX", name: "Inbox", type: "system")]
    }

    func fetchAccountEmail() async throws -> String {
        "uitest@example.com"
    }

    func reply(with draft: ReplyDraft) async throws {}

    func archive(messageID: String, labelIDs: [String]) async throws {}

    func signOut() throws {}
}

private extension String {
    var localizedUsername: String {
        guard let atIndex = firstIndex(of: "@") else { return self }
        return String(self[..<atIndex])
    }
}
