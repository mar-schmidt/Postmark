import SwiftUI

struct ReplyComposerView: View {
    let onSend: @Sendable (String) async -> Void
    let onCancel: (() -> Void)?
    @State private var replyText = ""
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick reply")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextEditor(text: $replyText)
                .frame(minHeight: 78, maxHeight: 110)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25))
                )
            HStack {
                Button("Cancel") {
                    onCancel?()
                }
                .disabled(isSending)
                Spacer()
                Button(isSending ? "Sending..." : "Send") {
                    Task {
                        isSending = true
                        await onSend(replyText)
                        replyText = ""
                        isSending = false
                    }
                }
                .disabled(isSending || replyText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    ReplyComposerView(onSend: { _ in }, onCancel: {})
        .padding()
        .frame(width: 360)
}
