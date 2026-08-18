import AppAuth
import Foundation

enum OAuthError: LocalizedError {
    case missingConfiguration
    case invalidIssuer
    case browserFlowFailed
    case noAccessToken
    case authorizationCodeMissing
    case archivedStateInvalid
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Google OAuth config is missing."
        case .invalidIssuer:
            return "Invalid Google issuer URL."
        case .browserFlowFailed:
            return "Google browser sign-in could not be started."
        case .noAccessToken:
            return "No access token was returned."
        case .authorizationCodeMissing:
            return "Authorization code was not returned."
        case .archivedStateInvalid:
            return "Stored authorization state could not be loaded."
        case .serverError(let message):
            return message
        }
    }
}

struct GoogleOAuthConfiguration {
    let clientID: String
    let clientSecret: String?
    let issuerURL: URL
    let successRedirectURL: URL?
    let scopes: [String]

    /// Reads an Info.plist entry, treating blank values as absent. Credentials are
    /// injected from Config/Secrets.xcconfig at build time, so an unconfigured
    /// checkout leaves these keys as empty strings rather than removing them.
    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: key
        ) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fromBundle() -> GoogleOAuthConfiguration? {
        guard let id = infoValue("GOOGLE_CLIENT_ID") else {
            return nil
        }

        let secret = infoValue("GOOGLE_CLIENT_SECRET")
        let success = infoValue("GOOGLE_OAUTH_SUCCESS_URL")

        return GoogleOAuthConfiguration(
            clientID: id,
            clientSecret: secret,
            issuerURL: URL(string: "https://accounts.google.com")!,
            successRedirectURL: success.flatMap(URL.init(string:)),
            scopes: [
                "https://www.googleapis.com/auth/gmail.modify",
                "https://www.googleapis.com/auth/gmail.labels",
                "https://www.googleapis.com/auth/gmail.send",
                "https://www.googleapis.com/auth/contacts.readonly"
            ]
        )
    }
}

@MainActor
final class GoogleOAuthService: NSObject, @unchecked Sendable {
    let tokenStore: AuthStateStore
    private let configuration: GoogleOAuthConfiguration
    private var redirectHandler: OIDRedirectHTTPHandler?
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private var authState: OIDAuthState?

    init(
        tokenStore: AuthStateStore,
        configuration: GoogleOAuthConfiguration? = .fromBundle()
    ) {
        self.tokenStore = tokenStore
        self.configuration = configuration ?? GoogleOAuthConfiguration(
            clientID: "",
            clientSecret: nil,
            issuerURL: URL(string: "https://accounts.google.com")!,
            successRedirectURL: nil,
            scopes: []
        )
        super.init()
    }

    var hasValidSession: Bool {
        authState != nil
    }

    var configurationError: OAuthError? {
        guard !configuration.clientID.isEmpty else {
            return .missingConfiguration
        }
        return nil
    }

    func authorize() async throws {
        if let error = configurationError {
            throw error
        }

        let serviceConfiguration = try await discoverServiceConfiguration()
        let redirectURL = try startRedirectHandler()
        let request = OIDAuthorizationRequest(
            configuration: serviceConfiguration,
            clientId: configuration.clientID,
            clientSecret: configuration.clientSecret,
            scopes: configuration.scopes,
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        let newState = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<OIDAuthState, Error>) in
            currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request
            ) { [weak self] authState, error in
                self?.activateApp()
                self?.redirectHandler?.cancelHTTPListener()
                self?.redirectHandler = nil
                self?.currentAuthorizationFlow = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let authState else {
                    continuation.resume(
                        throwing: OAuthError.authorizationCodeMissing
                    )
                    return
                }
                continuation.resume(returning: authState)
            }

            guard let flow = currentAuthorizationFlow else {
                continuation.resume(throwing: OAuthError.browserFlowFailed)
                return
            }
            redirectHandler?.currentAuthorizationFlow = flow
        }

        newState.stateChangeDelegate = self
        newState.errorDelegate = self
        authState = newState
        persistAuthState(newState)
    }

    func restoreSessionFromStore() async {
        let store = tokenStore
        let restoredState = await Task.detached(priority: .utility) {
            store.loadAuthState()
        }.value
        restoredState?.stateChangeDelegate = self
        restoredState?.errorDelegate = self
        authState = restoredState
    }

    func accessToken() async throws -> String {
        guard let authState else {
            throw OAuthError.missingConfiguration
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, Error>) in
            authState.performAction { [weak self] accessToken, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let accessToken else {
                    continuation.resume(throwing: OAuthError.noAccessToken)
                    return
                }
                if let self, let current = self.authState {
                    self.persistAuthState(current)
                }
                continuation.resume(returning: accessToken)
            }
        }
    }

    func signOut() throws {
        authState = nil
        currentAuthorizationFlow?.cancel()
        currentAuthorizationFlow = nil
        redirectHandler?.cancelHTTPListener()
        redirectHandler = nil
        try tokenStore.clearAuthState()
    }

    private func discoverServiceConfiguration() async throws
        -> OIDServiceConfiguration {
        try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.discoverConfiguration(
                forIssuer: configuration.issuerURL
            ) { serviceConfiguration, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let serviceConfiguration else {
                    continuation.resume(
                        throwing: OAuthError.serverError(
                            "OIDC discovery returned no configuration."
                        )
                    )
                    return
                }
                continuation.resume(returning: serviceConfiguration)
            }
        }
    }

    private func startRedirectHandler() throws -> URL {
        let handler = OIDRedirectHTTPHandler(
            successURL: configuration.successRedirectURL
        )
        var error: NSError?
        let redirectURL = handler.startHTTPListener(&error)
        if let error {
            throw error
        }
        redirectHandler = handler
        return redirectURL
    }

    private func activateApp() {
        NSRunningApplication.current.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        )
    }
}

extension GoogleOAuthService: OIDAuthStateChangeDelegate,
    OIDAuthStateErrorDelegate {
    func didChange(_ state: OIDAuthState) {
        persistAuthState(state)
    }

    func authState(
        _ state: OIDAuthState,
        didEncounterAuthorizationError error: Error
    ) {
        authState = nil
        try? tokenStore.clearAuthState()
    }

    private func persistAuthState(_ state: OIDAuthState) {
        let store = tokenStore
        Task.detached(priority: .utility) {
            try? store.saveAuthState(state)
        }
    }
}
