import Foundation

actor GooglePeopleClient {
    private let authService: GoogleOAuthService
    private let baseURL = URL(string: "https://people.googleapis.com/v1")!
    private var cachedByEmail: [String: URL] = [:]
    private var cachedAt: Date?
    private let cacheTTL: TimeInterval = 15 * 60
    private let lookupTimeoutSeconds: TimeInterval = 2.0
    private let maxPagesPerRefresh = 3

    init(authService: GoogleOAuthService) {
        self.authService = authService
    }

    func senderPhotoLookup() async -> [String: URL] {
        if let cachedAt,
            Date().timeIntervalSince(cachedAt) < cacheTTL {
            return cachedByEmail
        }
        let staleCache = cachedByEmail
        do {
            let fresh = try await fetchLookupWithTimeout()
            cachedByEmail = fresh
            cachedAt = Date()
            return fresh
        } catch {
            return staleCache
        }
    }

    private func fetchLookupWithTimeout() async throws -> [String: URL] {
        let lookupTask = Task { try await fetchLookup() }
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(lookupTimeoutSeconds))
            throw PeopleLookupTimeoutError.timedOut
        }

        do {
            let fresh = try await lookupTask.value
            timeoutTask.cancel()
            return fresh
        } catch {
            lookupTask.cancel()
            throw error
        }
    }

    private func fetchLookup() async throws -> [String: URL] {
        var lookup: [String: URL] = [:]
        var pageToken: String?
        var pageCount = 0

        while true {
            let response = try await listConnections(pageToken: pageToken)
            pageCount += 1
            for person in response.connections ?? [] {
                guard let photoURL = primaryPhotoURL(from: person.photos) else {
                    continue
                }
                for address in person.emailAddresses ?? [] {
                    let key = normalizedEmail(address.value)
                    guard !key.isEmpty else {
                        continue
                    }
                    lookup[key] = photoURL
                }
            }
            guard let next = response.nextPageToken, !next.isEmpty else {
                break
            }
            guard pageCount < maxPagesPerRefresh else {
                break
            }
            pageToken = next
        }
        return lookup
    }

    private func listConnections(
        pageToken: String?
    ) async throws -> PeopleConnectionsResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "people/me/connections"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "personFields", value: "emailAddresses,photos"),
            URLQueryItem(name: "pageSize", value: "500")
        ]
        if let pageToken, !pageToken.isEmpty {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let token = try await authService.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
                ?? "People API request failed."
            throw OAuthError.serverError(message)
        }
        return try JSONDecoder().decode(PeopleConnectionsResponse.self, from: data)
    }

    private func primaryPhotoURL(from photos: [PeoplePhoto]?) -> URL? {
        guard let photos else {
            return nil
        }
        if let primary = photos.first(where: { $0.metadata?.primary == true }),
            let url = URL(string: primary.url) {
            return url
        }
        if let first = photos.first,
            let url = URL(string: first.url) {
            return url
        }
        return nil
    }

    private func normalizedEmail(_ email: String?) -> String {
        guard let email else {
            return ""
        }
        return email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct PeopleConnectionsResponse: Decodable {
    let connections: [PeoplePerson]?
    let nextPageToken: String?
}

private struct PeoplePerson: Decodable {
    let emailAddresses: [PeopleEmailAddress]?
    let photos: [PeoplePhoto]?
}

private struct PeopleEmailAddress: Decodable {
    let value: String?
}

private struct PeoplePhoto: Decodable {
    let metadata: PeoplePhotoMetadata?
    let url: String
}

private struct PeoplePhotoMetadata: Decodable {
    let primary: Bool?
}

private enum PeopleLookupTimeoutError: Error {
    case timedOut
}
