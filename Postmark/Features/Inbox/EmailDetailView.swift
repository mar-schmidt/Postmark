import SwiftUI
import WebKit

struct EmailDetailView: View {
    let message: EmailMessage
    @State private var showQuotedContent = false
    private let collapsedHTMLContent: CollapsedContent?
    private let collapsedPlainContent: CollapsedContent
    private let fullParagraphItems: [ParagraphItem]
    private let collapsedParagraphItems: [ParagraphItem]

    init(message: EmailMessage) {
        self.message = message

        if let html = message.bodyHTML {
            collapsedHTMLContent = Self.collapseQuotedHTML(html)
        } else {
            collapsedHTMLContent = nil
        }

        collapsedPlainContent = Self.collapseQuotedPlainText(message.bodyText)
        fullParagraphItems = Self.makeParagraphItems(
            from: Self.bodyParagraphs(
                from: message.bodyText,
                fallbackSnippet: message.snippet
            )
        )
        collapsedParagraphItems = Self.makeParagraphItems(
            from: Self.bodyParagraphs(
                from: collapsedPlainContent.display,
                fallbackSnippet: message.snippet
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.pmLine).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.pmBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message.subject)
                .font(PMFont.display(24, weight: .bold))
                .foregroundStyle(Color.pmInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pmAvatar(for: message.senderAddress))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text(message.senderInitials)
                            .font(PMFont.body(16, weight: .bold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.sender)
                        .font(PMFont.body(14.5, weight: .bold))
                        .foregroundStyle(Color.pmInk)
                    Text(
                        message.senderAddress + " · "
                            + message.receivedAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                    )
                    .font(PMFont.body(12.5))
                    .foregroundStyle(Color.pmMuted)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if let htmlToRender {
            VStack(alignment: .leading, spacing: 0) {
                collapseButton
                EmailHTMLView(html: htmlToRender)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(paragraphItems) { paragraph in
                        Text(paragraph.text)
                            .font(PMFont.body(14.5))
                            .foregroundStyle(Color.pmInk)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    }
                    collapseButton
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var collapseButton: some View {
        if hasCollapsedContent {
            Button(showQuotedContent ? "Hide quoted content"
                : "Show quoted content") {
                showQuotedContent.toggle()
            }
            .buttonStyle(.plain)
            .font(PMFont.body(12.5, weight: .semibold))
            .foregroundStyle(Color.pmMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.pmSoft))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var htmlToRender: String? {
        guard let html = message.bodyHTML else {
            return nil
        }
        if showQuotedContent {
            return html
        }
        return collapsedHTMLContent?.display ?? html
    }

    private var hasCollapsedContent: Bool {
        if message.bodyHTML != nil {
            return collapsedHTMLContent?.didCollapse ?? false
        }
        return collapsedPlainContent.didCollapse
    }

    private var paragraphItems: [ParagraphItem] {
        showQuotedContent ? fullParagraphItems : collapsedParagraphItems
    }

    private static func bodyParagraphs(
        from text: String,
        fallbackSnippet: String
    ) -> [String] {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return [fallbackSnippet]
        }
        return trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func collapseQuotedPlainText(_ text: String)
        -> CollapsedContent {
        let lines = text.components(separatedBy: "\n")
        var keep: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") || trimmed.hasPrefix("-- ")
                || trimmed == "-----Original Message-----"
                || isOnDateWroteLine(trimmed) {
                let display = keep.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return CollapsedContent(display: display, didCollapse: true)
            }
            keep.append(line)
        }
        return CollapsedContent(display: text, didCollapse: false)
    }

    private static func isOnDateWroteLine(_ line: String) -> Bool {
        line.hasPrefix("On ") && line.lowercased().contains(" wrote:")
    }

    private static let blockquoteRegex = try? NSRegularExpression(
        pattern: #"(?is)<blockquote\b[^>]*>.*?</blockquote>"#
    )

    private static func collapseQuotedHTML(_ html: String) -> CollapsedContent {
        guard let regex = blockquoteRegex else {
            return CollapsedContent(display: html, didCollapse: false)
        }
        let range = NSRange(html.startIndex..., in: html)
        let collapsed = regex.stringByReplacingMatches(
            in: html,
            range: range,
            withTemplate: ""
        )
        let didCollapse = collapsed != html
        let hasEnoughContent = collapsed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count > 40
        if didCollapse && hasEnoughContent {
            return CollapsedContent(display: collapsed, didCollapse: true)
        }
        return CollapsedContent(display: html, didCollapse: false)
    }

    private static func makeParagraphItems(from source: [String])
        -> [ParagraphItem] {
        var counts: [String: Int] = [:]
        return source.map { text in
            let index = counts[text, default: 0]
            counts[text] = index + 1
            return ParagraphItem(id: "\(text)#\(index)", text: text)
        }
    }
}

private struct ParagraphItem: Identifiable {
    let id: String
    let text: String
}

private struct CollapsedContent {
    let display: String
    let didCollapse: Bool
}

private struct EmailHTMLView: NSViewRepresentable {
    let html: String

    final class Coordinator {
        var lastLoadedDocument: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let document = htmlDocument(for: html)
        if context.coordinator.lastLoadedDocument == document {
            return
        }
        context.coordinator.lastLoadedDocument = document
        webView.loadHTMLString(document, baseURL: nil)
    }

    private func htmlDocument(for body: String) -> String {
        """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 14px;
            line-height: 1.5;
            margin: 0;
            color: #111111;
            background: transparent;
        }
        img {
            max-width: 100%;
            height: auto;
        }
        blockquote {
            border-left: 2px solid #D0D0D0;
            padding-left: 10px;
            margin-left: 4px;
            color: #666666;
        }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

#Preview {
    EmailDetailView(message: PreviewFixtures.messages[0])
        .frame(width: 420, height: 560)
}
