import SwiftUI

struct ReplyComposerView: View {
    var subject: String = ""
    let onSend: @Sendable (String) async -> Void
    let onCancel: (() -> Void)?
    @State private var replyText = ""
    @State private var isSending = false
    @FocusState private var isEditorFocused: Bool

    private let smartReplies = [
        "Thanks!", "On it.", "Sounds good.",
        "Let me check and get back to you."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chips
            editor
            sendButton
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(smartReplies, id: \.self) { suggestion in
                    Button {
                        applySuggestion(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(PMFont.body(12.5, weight: .semibold))
                            .foregroundStyle(Color.pmAccent)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(Color.pmAccentSoft)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color.pmAccent.opacity(0.35),
                                        lineWidth: 1
                                    )
                            )
                            .contentShape(.capsule)
                    }
                    .buttonStyle(PMPressStyle())
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if replyText.isEmpty {
                Text("Write a reply…")
                    .font(PMFont.body(14))
                    .foregroundStyle(Color.pmFaint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            TextEditor(text: $replyText)
                .focused($isEditorFocused)
                .font(PMFont.body(14))
                .foregroundStyle(Color.pmInk)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 84, maxHeight: 120)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.pmSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.pmLine, lineWidth: 1)
        )
    }

    private var sendButton: some View {
        Button {
            Task {
                isSending = true
                await onSend(replyText)
                replyText = ""
                isSending = false
            }
        } label: {
            Text(isSending ? "Sending…" : "Send reply")
                .font(PMFont.body(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canSend ? Color.pmAccent : Color.pmAccent.opacity(0.4))
                )
                .contentShape(.rect)
        }
        .buttonStyle(PMPressStyle())
        .disabled(!canSend)
    }

    private var canSend: Bool {
        !isSending && !replyText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private func applySuggestion(_ suggestion: String) {
        if replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            replyText = suggestion
        } else {
            replyText += (replyText.hasSuffix(" ") ? "" : " ") + suggestion
        }
        isEditorFocused = true
    }
}

#Preview {
    ReplyComposerView(
        subject: "Design review",
        onSend: { _ in },
        onCancel: {}
    )
    .padding()
    .frame(width: 380)
    .background(Color.pmBackground)
}
