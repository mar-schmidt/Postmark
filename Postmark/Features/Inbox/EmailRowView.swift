import SwiftUI

struct EmailRowView: View {
    private let avatarSize: CGFloat = 40

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    let message: EmailMessage
    let isExpanded: Bool
    let onSelect: (() -> Void)?

    var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    avatarView
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(message.sender)
                                .font(PMFont.body(14.5, weight: .bold))
                                .foregroundStyle(Color.pmInk)
                                .lineLimit(1)
                            if message.isUnread {
                                Circle()
                                    .fill(Color.pmAccent)
                                    .frame(width: 7, height: 7)
                            }
                            Spacer(minLength: 4)
                            Text(relativeTime)
                                .font(PMFont.body(12))
                                .foregroundStyle(Color.pmFaint)
                        }
                        Text(message.subject)
                            .font(PMFont.body(
                                13.5,
                                weight: message.isUnread ? .semibold : .medium
                            ))
                            .foregroundStyle(Color.pmInk)
                            .lineLimit(1)
                        Text(message.snippet)
                            .font(PMFont.body(12.5))
                            .foregroundStyle(Color.pmMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                if isExpanded {
                    expandedDetail
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pmCard(cornerRadius: 18)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashedDivider()
                .padding(.top, 12)
            Text(message.snippet)
                .font(PMFont.body(12.5))
                .foregroundStyle(Color.pmMuted)
                .multilineTextAlignment(.leading)
            Text("From: \(message.senderAddress)")
                .font(PMFont.body(11.5))
                .foregroundStyle(Color.pmFaint)
        }
        .padding(.top, 0)
        .transition(.opacity)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = message.senderPhotoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallbackAvatar
                }
            }
            .transaction { $0.animation = nil }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
            fallbackAvatar
                .transaction { $0.animation = nil }
        }
    }

    private var fallbackAvatar: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.pmAvatar(for: message.senderAddress))
            .frame(width: avatarSize, height: avatarSize)
            .overlay(
                Text(message.senderInitials)
                    .font(PMFont.body(15, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var relativeTime: String {
        Self.timeFormatter.localizedString(
            for: message.receivedAt,
            relativeTo: Date()
        )
    }
}

/// A hairline dashed rule used inside expanded cards.
struct DashedDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay(
                Line()
                    .stroke(
                        Color.pmLine,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            )
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

#Preview {
    VStack {
        EmailRowView(
            message: PreviewFixtures.messages[0],
            isExpanded: true,
            onSelect: {}
        )
        EmailRowView(
            message: PreviewFixtures.messages[1],
            isExpanded: false,
            onSelect: {}
        )
    }
    .padding()
    .frame(width: 380)
    .background(Color.pmBackground)
}
