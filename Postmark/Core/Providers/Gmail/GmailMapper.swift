import Foundation

struct GmailMapper {
    private let parser = RFC2822DateParser()

    func mapMessage(
        from message: GmailMessageResponse,
        senderPhotoURL: URL?
    ) -> EmailMessage {
        let headers = headerLookup(from: message.payload.headers)
        let senderRaw = headers["from"] ?? "Unknown"
        let senderAddress = extractEmail(from: senderRaw)
        let senderName = senderRaw
            .replacingOccurrences(of: "<\(senderAddress)>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let senderDisplay = senderName.isEmpty ? senderAddress : senderName
        let subject = headers["subject"] ?? "(No Subject)"
        let dateHeader = headers["date"] ?? ""
        let date = receivedDate(
            internalDate: message.internalDate,
            dateHeader: dateHeader
        )
        let unread = message.labelIds.contains("UNREAD")
        let bodies = extractBodyVariants(from: message.payload)
        let normalizedHTML = normalizedHTMLText(bodies.html)
        let trimmedPlain = bodies.plain?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedPlain: String
        if let plain = trimmedPlain, !plain.isEmpty {
            normalizedPlain = normalizedBodyText(plain)
        } else {
            normalizedPlain = normalizedBodyText(message.snippet)
        }

        return EmailMessage(
            id: message.id,
            threadID: message.threadID,
            sender: senderDisplay,
            senderAddress: senderAddress,
            subject: subject,
            snippet: message.snippet,
            bodyText: normalizedPlain,
            bodyHTML: normalizedHTML,
            senderPhotoURL: senderPhotoURL,
            senderInitials: senderInitials(
                from: senderDisplay,
                senderAddress: senderAddress
            ),
            receivedAt: date,
            isUnread: unread
        )
    }

    private func headerLookup(from headers: [GmailHeader]) -> [String: String] {
        headers.reduce(into: [:]) { lookup, header in
            let key = header.name.lowercased()
            guard lookup[key] == nil else {
                return
            }
            lookup[key] = header.value
        }
    }

    private func extractBodyVariants(from payload: GmailPayload) -> BodyVariants {
        let mimeType = payload.mimeType?.lowercased() ?? ""
        if mimeType.hasPrefix("multipart/alternative"),
            let parts = payload.parts {
            return extractAlternativeVariants(parts)
        }
        if mimeType.hasPrefix("multipart/"),
            let parts = payload.parts {
            return extractMixedVariants(parts)
        }

        if mimeType == "text/plain",
            let text = decodeText(from: payload) {
            return BodyVariants(plain: text, html: nil)
        }
        if mimeType == "text/html",
            let html = decodeText(from: payload) {
            return BodyVariants(plain: nil, html: html)
        }
        if let text = decodeText(from: payload) {
            return BodyVariants(plain: text, html: nil)
        }
        return BodyVariants(plain: nil, html: nil)
    }

    private func extractAlternativeVariants(_ parts: [GmailPayload]) -> BodyVariants {
        var candidatePlain: String?
        var candidateHTML: String?
        for part in parts {
            let variants = extractBodyVariants(from: part)
            if let plain = variants.plain {
                candidatePlain = plain
            }
            if let html = variants.html {
                candidateHTML = html
            }
        }
        return BodyVariants(plain: candidatePlain, html: candidateHTML)
    }

    private func extractMixedVariants(_ parts: [GmailPayload]) -> BodyVariants {
        var preferred = BodyVariants(plain: nil, html: nil)
        for part in parts {
            let variants = extractBodyVariants(from: part)
            if preferred.html == nil {
                preferred.html = variants.html
            }
            if preferred.plain == nil {
                preferred.plain = variants.plain
            }
            if preferred.plain != nil, preferred.html != nil {
                return preferred
            }
        }
        return preferred
    }

    private func decodeText(from payload: GmailPayload) -> String? {
        guard let dataString = payload.body?.data,
            let data = Data(base64URLString: dataString) else {
            return nil
        }
        let contentType = contentTypeHeader(from: payload.headers)
        let charset = charset(from: contentType)
        return decodedString(from: data, charset: charset)
    }

    private func contentTypeHeader(from headers: [GmailHeader]) -> String {
        headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?
            .value ?? ""
    }

    private func charset(from contentType: String) -> String? {
        guard !contentType.isEmpty else {
            return nil
        }
        let pattern = #"charset\s*=\s*"?([^;"\s]+)"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(contentType.startIndex..., in: contentType)
        guard let match = regex.firstMatch(in: contentType, range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: contentType) else {
            return nil
        }
        return String(contentType[valueRange]).lowercased()
    }

    private func decodedString(from data: Data, charset: String?) -> String? {
        let declaredEncoding = charset.flatMap {
            String.Encoding(ianaCharsetName: $0)
        }
        var candidates: [(string: String, declared: Bool)] = []

        func appendCandidate(_ encoding: String.Encoding, declared: Bool) {
            guard let candidate = String(data: data, encoding: encoding) else {
                return
            }
            if candidates.contains(where: { $0.string == candidate }) {
                return
            }
            candidates.append((candidate, declared))
        }

        if let declaredEncoding {
            appendCandidate(declaredEncoding, declared: true)
        }
        appendCandidate(.utf8, declared: false)
        appendCandidate(.isoLatin1, declared: false)
        appendCandidate(.windowsCP1252, declared: false)

        guard !candidates.isEmpty else {
            return nil
        }

        let best = candidates.min { lhs, rhs in
            decodeScore(for: lhs.string, declared: lhs.declared)
                < decodeScore(for: rhs.string, declared: rhs.declared)
        }
        return best?.string
    }

    private func decodeScore(for value: String, declared: Bool) -> Int {
        var score = 0
        score += value.countOccurrences(of: "\u{FFFD}") * 80
        score += mojibakePenalty(in: value)
        if !declared {
            score += 2
        }
        return score
    }

    private func mojibakePenalty(in value: String) -> Int {
        let markers = [
            "Ã",
            "Â",
            "â€",
            "â€™",
            "â€œ",
            "â€\u{9D}",
            "â€“",
            "â€”"
        ]
        return markers.reduce(0) { running, marker in
            running + value.countOccurrences(of: marker) * 20
        }
    }

    private func normalizedHTMLText(_ html: String?) -> String? {
        guard let html else {
            return nil
        }
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedBodyText(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let squashed = unified.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return squashed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func receivedDate(
        internalDate: String?,
        dateHeader: String
    ) -> Date {
        if let internalDate,
            let millis = TimeInterval(internalDate) {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        if let parsed = parser.parse(dateHeader) {
            return parsed
        }
        return Date.distantPast
    }

    private func extractEmail(from value: String) -> String {
        if let start = value.firstIndex(of: "<"),
            let end = value.firstIndex(of: ">"),
            start < end {
            return String(value[value.index(after: start)..<end])
        }
        return value
    }

    private func senderInitials(
        from senderDisplay: String,
        senderAddress: String
    ) -> String {
        let base = senderDisplay
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = base.isEmpty ? senderAddress : base
        let words = source
            .split { $0.isWhitespace || $0 == "@" || $0 == "." || $0 == "_" }
        let chars = words
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
        if !chars.isEmpty {
            return chars
        }
        return String(source.prefix(1)).uppercased()
    }
}

private struct BodyVariants {
    var plain: String?
    var html: String?
}

private extension Data {
    init?(base64URLString: String) {
        var value = base64URLString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder != 0 {
            value += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: value)
    }
}

private extension String.Encoding {
    init?(ianaCharsetName: String) {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(
            ianaCharsetName as CFString
        )
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        self.init(rawValue: nsEncoding)
    }
}

private extension String {
    func countOccurrences(of token: String) -> Int {
        guard !token.isEmpty else {
            return 0
        }
        return components(separatedBy: token).count - 1
    }
}

struct RFC2822DateParser {
    private let formatters: [DateFormatter] = {
        let patterns = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm zzz"
        ]
        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    func parse(_ value: String) -> Date? {
        let sanitized = sanitizedDateHeader(value)
        guard !sanitized.isEmpty else {
            return nil
        }
        for formatter in formatters {
            if let date = formatter.date(from: sanitized) {
                return date
            }
        }
        return nil
    }

    private func sanitizedDateHeader(_ value: String) -> String {
        // Headers can include comments like "(UTC)" that break DateFormatter.
        let stripped = value.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
