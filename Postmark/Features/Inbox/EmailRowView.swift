import SwiftUI

struct EmailRowView: View {
    private let avatarSize: CGFloat = 38

    private static let receivedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    let message: EmailMessage
    let isExpanded: Bool
    let onSelect: (() -> Void)?

    var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    avatarView
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.sender)
                            .font(.headline)
                            .lineLimit(1)
                        Text(message.subject)
                            .font(.subheadline.weight(
                                message.isUnread ? .semibold : .regular
                            ))
                            .lineLimit(1)
                        Text(message.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(
                        Self.receivedAtFormatter.string(
                            from: message.receivedAt
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("From: \(message.senderAddress)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Thread: \(message.threadID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        message.isUnread
                            ? Color.surfacePrimary.opacity(0.9)
                            : Color.surfaceSecondary.opacity(0.7)
                    )
            )
            .clipped()
            .contentShape(.rect)
        }
        .accessibilityIdentifier("inbox-message-\(message.id)")
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = message.senderPhotoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackAvatar
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
        } else {
            fallbackAvatar
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(avatarColor)
            .frame(width: avatarSize, height: avatarSize)
            .overlay(
                Text(message.senderInitials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            )
    }

    private var avatarColor: Color {
        let palette = Color.tagPalette
        let seed = message.senderAddress.unicodeScalars.reduce(0) {
            $0 + Int($1.value)
        }
        return palette[seed % palette.count]
    }
}

#Preview {
    EmailRowView(
        message: PreviewFixtures.messages[0],
        isExpanded: true,
        onSelect: {}
    )
    .padding()
    .frame(width: 380)
}
