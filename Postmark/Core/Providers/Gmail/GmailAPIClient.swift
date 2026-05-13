import Foundation

actor GmailAPIClient {
    private let authService: GoogleOAuthService
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1")!
    private let mapper = GmailMapper()
    private let peopleClient: GooglePeopleClient
    private let maxDetailRequests = 4

    init(authService: GoogleOAuthService) {
        self.authService = authService
        peopleClient = GooglePeopleClient(authService: authService)
    }

    func fetchInbox(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage {
        var components = URLComponents(
            url: baseURL.appending(path: "users/me/messages"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "maxResults", value: "25")]
        queryItems.append(
            contentsOf: labelIDs.map { labelID in
                URLQueryItem(name: "labelIds", value: labelID)
            }
        )
        if let pageToken {
            queryItems.append(
                URLQueryItem(name: "pageToken", value: pageToken)
            )
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let list = try await request(
            url: url,
            method: "GET"
        ) as GmailListResponse
        var mapped: [EmailMessage] = []
        let senderPhotos = await peopleClient.senderPhotoLookup()

        let messageIDs = list.messages ?? []
        for chunk in messageIDs.chunked(size: maxDetailRequests) {
            try await withThrowingTaskGroup(of: GmailMessageResponse.self) {
                group in
                for item in chunk {
                    group.addTask {
                        try await self.fetchMessage(id: item.id)
                    }
                }
                for try await details in group {
                    let senderAddress = senderAddress(from: details)
                    let senderPhotoURL = senderPhotos[senderAddress.lowercased()]
                    mapped.append(
                        mapper.mapMessage(
                            from: details,
                            senderPhotoURL: senderPhotoURL
                        )
                    )
                }
            }
        }

        mapped.sort { $0.receivedAt > $1.receivedAt }
        return InboxPage(messages: mapped, nextPageToken: list.nextPageToken)
    }

    func archive(messageID: String, labelIDs: [String]) async throws {
        let url = baseURL.appending(
            path: "users/me/messages/\(messageID)/modify"
        )
        let body = GmailModifyRequest(removeLabelIds: labelIDs)
        try await requestStatusOnly(
            url: url,
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
    }

    func fetchAccountEmail() async throws -> String {
        let url = baseURL.appending(path: "users/me/profile")
        let response = try await request(
            url: url,
            method: "GET"
        ) as GmailProfileResponse
        return response.emailAddress
    }

    func fetchLabels() async throws -> [EmailLabel] {
        let url = baseURL.appending(path: "users/me/labels")
        let response = try await request(
            url: url,
            method: "GET"
        ) as GmailLabelsResponse
        return (response.labels ?? []).map { label in
            EmailLabel(id: label.id, name: label.name, type: label.type)
        }
    }

    func reply(with draft: ReplyDraft) async throws {
        let to = draft.recipient
        let subject = draft.subject.hasPrefix("Re:")
            ? draft.subject : "Re: \(draft.subject)"
        let raw = """
        To: \(to)
        Subject: \(subject)
        In-Reply-To: \(draft.messageID)
        References: \(draft.messageID)

        \(draft.body)
        """
        let payload = GmailSendRequest(
            raw: raw.data(using: .utf8)?.base64URLEncodedString() ?? "",
            threadID: draft.threadID
        )

        let url = baseURL.appending(path: "users/me/messages/send")
        _ = try await request(
            url: url,
            method: "POST",
            body: try JSONEncoder().encode(payload)
        ) as GmailMessageResponse
    }

    private func fetchMessage(id: String) async throws -> GmailMessageResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "users/me/messages/\(id)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "format", value: "full")
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        return try await request(
            url: url,
            method: "GET"
        ) as GmailMessageResponse
    }

    private func request<T: Decodable>(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws -> T {
        let (data, _) = try await executeRequest(
            url: url,
            method: method,
            body: body
        )
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func senderAddress(from message: GmailMessageResponse) -> String {
        let fromHeader = message.payload.headers.first {
            $0.name.caseInsensitiveCompare("From") == .orderedSame
        }?.value ?? ""
        if let start = fromHeader.firstIndex(of: "<"),
            let end = fromHeader.firstIndex(of: ">"),
            start < end {
            return String(fromHeader[fromHeader.index(after: start)..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fromHeader.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestStatusOnly(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws {
        _ = try await executeRequest(
            url: url,
            method: method,
            body: body
        )
    }

    private func executeRequest(
        url: URL,
        method: String,
        body: Data?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = try await authService.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var attempt = 0
        let maxAttempts = 4

        while true {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if (200 ... 299).contains(http.statusCode) {
                return (data, http)
            }

            let message = String(data: data, encoding: .utf8)
                ?? "Unknown API error"
            let canRetry = shouldRetry(
                statusCode: http.statusCode,
                body: message
            )
            let retryAfter = parseRetryAfterSeconds(from: http)
            attempt += 1

            guard canRetry, attempt < maxAttempts else {
                throw OAuthError.serverError(message)
            }

            let delay = retryDelaySeconds(
                attempt: attempt,
                retryAfter: retryAfter
            )
            try await Task.sleep(for: .seconds(delay))
        }
    }

    private func shouldRetry(statusCode: Int, body: String) -> Bool {
        if statusCode == 429 {
            return true
        }
        guard statusCode == 403 else {
            return false
        }
        let lowered = body.lowercased()
        let reasons = [
            "ratelimitexceeded",
            "userratelimitexceeded",
            "too many concurrent requests for user"
        ]
        return reasons.contains { lowered.contains($0) }
    }

    private func parseRetryAfterSeconds(
        from response: HTTPURLResponse
    ) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")
        else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return seconds
        }
        return nil
    }

    private func retryDelaySeconds(
        attempt: Int,
        retryAfter: TimeInterval?
    ) -> TimeInterval {
        if let retryAfter {
            return min(max(retryAfter, 0.25), 10)
        }
        let base = min(pow(2.0, Double(attempt)) * 0.25, 10)
        let jitter = Double.random(in: 0 ... 0.35)
        return base + jitter
    }
}

private struct GmailProfileResponse: Decodable {
    let emailAddress: String
}

private struct GmailListResponse: Decodable {
    let messages: [GmailMessageID]?
    let nextPageToken: String?
}

private struct GmailMessageID: Decodable {
    let id: String
}

private struct GmailLabelsResponse: Decodable {
    let labels: [GmailLabelResponse]?
}

private struct GmailLabelResponse: Decodable {
    let id: String
    let name: String
    let type: String
}

struct GmailMessageResponse: Decodable {
    let id: String
    let threadID: String
    let snippet: String
    let labelIds: [String]
    let internalDate: String?
    let payload: GmailPayload

    enum CodingKeys: String, CodingKey {
        case id
        case threadID = "threadId"
        case snippet
        case labelIds
        case internalDate
        case payload
    }
}

struct GmailPayload: Decodable {
    let mimeType: String?
    let headers: [GmailHeader]
    let body: GmailBody?
    let parts: [GmailPayload]?
}

struct GmailHeader: Decodable {
    let name: String
    let value: String
}

struct GmailBody: Decodable {
    let size: Int?
    let data: String?
}

private struct GmailModifyRequest: Encodable {
    let removeLabelIds: [String]
}

private struct GmailSendRequest: Encodable {
    let raw: String
    let threadID: String

    enum CodingKeys: String, CodingKey {
        case raw
        case threadID = "threadId"
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

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var start = 0
        while start < count {
            let end = Swift.min(start + size, count)
            chunks.append(Array(self[start..<end]))
            start = end
        }
        return chunks
    }
}
