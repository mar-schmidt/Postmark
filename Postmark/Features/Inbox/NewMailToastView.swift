//
//  NewMailToastView.swift
//  Postmark
//
//  In-app "new mail" toast that drops in from the top of the panel when a
//  message arrives, mirroring the Triage Deck notification design. Pairs with
//  the system banner posted by NewMailNotifier.
//

import SwiftUI

struct NewMailToastView: View {
    let item: NewMailItem
    let onOpen: () -> Void
    let onArchive: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            VStack(alignment: .leading, spacing: 10) {
                header
                messagePreview
                actions
            }
            .padding(14)
            .frame(width: 320)
            .pmCard(cornerRadius: 18, shadow: true)
        }
        .padding(.top, 10)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var header: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.pmAccent)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text("Postmark")
                .font(PMFont.body(12, weight: .bold))
                .foregroundStyle(Color.pmInk)
            Spacer()
            Text("now")
                .font(PMFont.body(11))
                .foregroundStyle(Color.pmFaint)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.pmFaint)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var messagePreview: some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.pmAvatar(for: item.sender))
                .frame(width: 38, height: 38)
                .overlay(
                    Text(item.senderInitials)
                        .font(PMFont.body(15, weight: .bold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(item.sender)
                    .font(PMFont.body(13.5, weight: .bold))
                    .foregroundStyle(Color.pmInk)
                    .lineLimit(1)
                Text(item.subject.isEmpty ? "New message" : item.subject)
                    .font(PMFont.body(13, weight: .semibold))
                    .foregroundStyle(Color.pmInk)
                    .lineLimit(1)
                Text(item.snippet)
                    .font(PMFont.body(12))
                    .foregroundStyle(Color.pmMuted)
                    .lineLimit(2)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onArchive) {
                Text("Archive")
                    .font(PMFont.body(12.5, weight: .semibold))
                    .foregroundStyle(Color.pmInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.pmSoft)
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button(action: onOpen) {
                Text("Open")
                    .font(PMFont.body(12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.pmAccent)
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NewMailToastView(
        item: NewMailItem(message: PreviewFixtures.messages[0]),
        onOpen: {},
        onArchive: {},
        onClose: {}
    )
    .frame(width: 420, height: 240)
    .background(Color.pmBackground)
}
