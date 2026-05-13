import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    let onAddAccount: () -> Void
    @State private var availableLabels: [EmailLabel] = []
    @State private var isLoadingLabels = false
    @State private var labelsErrorMessage: String?
    @State private var isLabelsExpanded = false
    @State private var reloadRotation: Double = 0
    @State private var isRemoveAlertPresented = false

    init(onAddAccount: @escaping () -> Void = {}) {
        self.onAddAccount = onAddAccount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                accountsCard
                scopeDivider
                interactionCard
                labelsCard
                footerRow
            }
            .padding(12)
        }
        // .background(Color.appBackgroundNeutral.opacity(0.35))
        .task {
            await loadLabels()
        }
        .onChange(of: appState.editingAccountID) { _, _ in
            Task { await loadLabels(force: true) }
        }
    }

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Accounts")
                Spacer()
              
                Button {
                    onAddAccount()
                } label: {
                    Label("Add account",
                        systemImage: "plus"
                    )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.stateSuccess)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            Color.stateSuccess.opacity(0.12),
                            in: Capsule()
                        )
                }

            }
            .buttonStyle(.plain)
            
            VStack(spacing: 2) {
                ForEach(appState.accounts) { account in
                    accountRow(account)
                }
            }
        }
        .cardBackground(padding: 10)
    }

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        let isSelected = appState.editingAccountID == account.id
        Button {
            Task {
                await appState.selectAccount(account.id)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    AccountAvatar(account: account, size: 34)
                    if account.isActiveInbox {
                        Circle()
                            .fill(Color.stateSuccess)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().strokeBorder(
                                    Color(nsColor: .windowBackgroundColor),
                                    lineWidth: 1.5
                                )
                            )
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? Color.accentColor : Color.primary
                        )
                        .lineLimit(1)
                    Text(account.isActiveInbox ? "Active inbox" : "Click to switch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let unread = appState.unreadCount(for: account.id)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.stateDestructive, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.1)
                            : Color.surfacePrimary
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.borderSubtle.opacity(0.35),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var scopeDivider: some View {
        Group {
            if let editing = appState.editingAccount {
                HStack(spacing: 6) {
                  Spacer()
                    HStack(spacing: 5) {
                        Text("Settings for \(editing.email)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                  Spacer()
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var interactionCard: some View {
        let selectedBehavior = appState.editingAccount?.emailOpenBehavior
            ?? .inlineExpand
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Opening emails")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                ForEach(EmailOpenBehavior.allCases) { behavior in
                    behaviorCard(for: behavior, selectedBehavior: selectedBehavior)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: selectedBehavior)
        }
        .cardBackground(padding: 14)
    }

    private func behaviorCard(
        for behavior: EmailOpenBehavior,
        selectedBehavior: EmailOpenBehavior
    ) -> some View {
        let isSelected = selectedBehavior == behavior
        return Button {
            appState.updateEditingAccountEmailBehavior(behavior)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: behavior.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(
                        isSelected ? Color.accentColor : .secondary
                    )
                Text(behavior.cardTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        isSelected ? Color.accentColor : .primary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color.surfaceSecondary
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.4)
                            : Color.borderSubtle.opacity(0.6),
                        lineWidth: 1.5
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var labelsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            labelsHeader
            selectedLabelChips
            if isLabelsExpanded {
                Divider()
                expandedLabelList
            }
            if let labelsErrorMessage {
                Text(labelsErrorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.stateWarning)
                    .textSelection(.enabled)
            }
        }
        .cardBackground(padding: 14)
    }

    private var labelsHeader: some View {
        HStack(spacing: 8) {
            SectionLabel("Inbox labels")
            Spacer()
            Button {
                Task { await loadLabels(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(reloadRotation))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingLabels)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLabelsExpanded.toggle()
                }
            } label: {
                Text(isLabelsExpanded ? "Done" : "Edit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .onChange(of: isLoadingLabels) { _, loading in
            if loading {
                withAnimation(
                    .linear(duration: 0.6).repeatForever(autoreverses: false)
                ) {
                    reloadRotation = 360
                }
            } else {
                withAnimation(.linear(duration: 0.2)) {
                    reloadRotation = 0
                }
            }
        }
    }

    private var selectedLabelChips: some View {
        let selectedIDs = appState.editingAccount?.selectedLabelIDs
            ?? [AppState.defaultLabelID]
        return ChipFlow(spacing: 5, lineSpacing: 5) {
            ForEach(selectedIDs, id: \.self) { id in
                labelChip(for: id)
            }
        }
    }

    private func labelChip(for id: String) -> some View {
        let name = availableLabels.first(where: { $0.id == id })?.name ?? id
        let canDismiss = (appState.editingAccount?.selectedLabelIDs.count ?? 0) > 1
        return HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.stateInfo)
            if canDismiss {
                Button {
                    Task { await toggleLabelSelection(id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.stateInfo.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.stateInfo.opacity(0.14)))
    }

    private var expandedLabelList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedCountCopy)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if availableLabels.isEmpty && !isLoadingLabels {
                Text("No labels loaded yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(availableLabels) { label in
                            labelRow(for: label)
                        }
                    }
                }
                .frame(maxHeight: 148)
            }
        }
    }

    private func labelRow(for label: EmailLabel) -> some View {
        let selected = appState.editingAccount?.selectedLabelIDs ?? []
        let isOn = selected.contains(label.id)
        return Button {
            Task { await toggleLabelSelection(label.id) }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isOn ? Color.accentColor : Color.clear)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isOn
                                        ? Color.clear
                                        : Color.borderSubtle.opacity(0.7),
                                    lineWidth: 1.5
                                )
                        )
                        .frame(width: 16, height: 16)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(label.name)
                    .font(.system(size: 13))
                    .fontWeight(isOn ? .medium : .regular)
                    .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.08) : .clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var footerRow: some View {
        let username = appState.editingAccount?.email
            ?? "account"
        return HStack {
            Text("Postmark v\(appVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Logout \(username)") {
                isRemoveAlertPresented = true
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.red)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .alert("Logout from account?", isPresented: $isRemoveAlertPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) {
                Task { await removeEditingAccount() }
            }
        } message: {
            Text("This account will be removed from Postmark.")
        }
    }

    private var selectedCountCopy: String {
        let selected = appState.editingAccount?.selectedLabelIDs.count ?? 0
        let total = availableLabels.count
        return "\(selected) of \(total) selected"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0"
    }

    private func toggleLabelSelection(_ labelID: String) async {
        guard let selected = appState.editingAccount?.selectedLabelIDs else {
            return
        }
        var updated = selected
        if let index = updated.firstIndex(of: labelID) {
            if updated.count == 1 { return }
            updated.remove(at: index)
        } else {
            updated.append(labelID)
        }
        await appState.updateEditingAccountLabelIDs(updated)
    }

    private func loadLabels(force: Bool = false) async {
        if !force && !availableLabels.isEmpty { return }
        guard let editingID = appState.editingAccountID else {
            availableLabels = []
            return
        }
        guard let provider = appState.providerManager.provider(for: editingID) else {
            availableLabels = []
            return
        }
        isLoadingLabels = true
        labelsErrorMessage = nil
        defer { isLoadingLabels = false }

        do {
            let labels = try await provider.fetchLabels()
            availableLabels = labels
                .filter { $0.type == "system" || $0.type == "user" }
                .sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                        == .orderedAscending
                }
        } catch {
            labelsErrorMessage = labelsErrorText(for: error)
        }
    }

    private func removeEditingAccount() async {
        guard let editingID = appState.editingAccountID else { return }
        await appState.removeAccount(editingID)
    }

    private func labelsErrorText(for error: Error) -> String {
        let raw = error.localizedDescription
        let lowered = raw.lowercased()
        if lowered.contains("insufficient") || lowered.contains("permission") {
            return """
                Label access requires new Gmail permissions. Logout from this \
                account, then add it again to grant label access.
                """
        }
        return raw
    }
}

private extension EmailOpenBehavior {
    var cardTitle: String {
        switch self {
        case .inlineExpand: return "Expand in list"
        case .openDetail: return "Open detail"
        }
    }

    var iconName: String {
        switch self {
        case .inlineExpand: return "arrow.up.and.down"
        case .openDetail: return "arrow.up.forward.square"
        }
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.5)
    }
}

private struct ChipFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var hasLine = false

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needsSpacing = lineWidth > 0
            let tentativeWidth = lineWidth
                + (needsSpacing ? spacing : 0)
                + size.width
            if tentativeWidth > maxWidth && lineWidth > 0 {
                totalHeight += lineHeight + lineSpacing
                totalWidth = max(totalWidth, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
                hasLine = true
            } else {
                lineWidth = tentativeWidth
                lineHeight = max(lineHeight, size.height)
                hasLine = true
            }
        }
        if hasLine {
            totalHeight += lineHeight
            totalWidth = max(totalWidth, lineWidth)
        }
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private extension View {
    func cardBackground(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .fill(Color.gray.opacity(0.05))
            )
    }
}

private struct SettingsPreviewProvider: EmailProvider {
    let email: String
    let labels: [EmailLabel]

    func fetchInboxPage(
        pageToken: String?,
        labelIDs: [String]
    ) async throws -> InboxPage {
        InboxPage(messages: PreviewFixtures.messages, nextPageToken: nil)
    }

    func fetchLabels() async throws -> [EmailLabel] { labels }
    func fetchAccountEmail() async throws -> String { email }
    func reply(with draft: ReplyDraft) async throws {}
    func archive(messageID: String, labelIDs: [String]) async throws {}
    func signOut() throws {}
}

@MainActor
private func previewState(
    selected: [String] = ["INBOX"],
    behavior: EmailOpenBehavior = .openDetail,
    labels: [EmailLabel] = [
        EmailLabel(id: "INBOX", name: "Inbox", type: "system"),
        EmailLabel(id: "STARRED", name: "Starred", type: "system"),
        EmailLabel(id: "SENT", name: "Sent", type: "system"),
        EmailLabel(id: "DRAFT", name: "Drafts", type: "system"),
        EmailLabel(id: "TRASH", name: "Trash", type: "system"),
        EmailLabel(id: "SPAM", name: "Spam", type: "system"),
        EmailLabel(id: "IMPORTANT", name: "Important", type: "system"),
        EmailLabel(id: "lbl_work", name: "Work", type: "user"),
        EmailLabel(id: "lbl_finance", name: "Finance", type: "user"),
        EmailLabel(id: "lbl_news", name: "Newsletters", type: "user"),
        EmailLabel(id: "lbl_all", name: "All Mail", type: "user")
    ]
) -> AppState {
    let providerOne = SettingsPreviewProvider(
        email: "marcus@gmail.com",
        labels: labels
    )
    let providerTwo = SettingsPreviewProvider(
        email: "marcus@work.io",
        labels: labels
    )
    let accountOne = Account(
        id: UUID(),
        email: "marcus@gmail.com",
        displayName: "Marcus",
        isActiveInbox: true,
        emailOpenBehavior: behavior,
        selectedLabelIDs: selected
    )
    let accountTwo = Account(
        id: UUID(),
        email: "marcus@work.io",
        displayName: "Marcus Work",
        isActiveInbox: false,
        emailOpenBehavior: .inlineExpand,
        selectedLabelIDs: ["INBOX", "lbl_work"]
    )
    return AppState.previewSignedIn(
        accountsWithProviders: [
            (accountOne, providerOne),
            (accountTwo, providerTwo)
        ]
    )
}

@MainActor
private func previewUnsubscribedState() -> AppState {
    let account = Account(
        id: UUID(),
        email: "marcus@gmail.com",
        displayName: "Marcus",
        isActiveInbox: true,
        emailOpenBehavior: .openDetail,
        selectedLabelIDs: ["INBOX", "STARRED"]
    )
    let provider = SettingsPreviewProvider(
        email: account.email,
        labels: [
            EmailLabel(id: "INBOX", name: "Inbox", type: "system"),
            EmailLabel(id: "STARRED", name: "Starred", type: "system")
        ]
    )
    let state = AppState(
        billingService: PreviewBillingService(entitlement: .free),
        accounts: [account],
        editingAccountID: account.id,
        shouldPoll: false
    )
    state.installSessionForTesting(
        account: account,
        provider: provider,
        makeActive: true
    )
    return state
}

#Preview("Default") {
    SettingsView()
        .environmentObject(previewState())
        .frame(width: 420, height: 560)
}

#Preview("Many Labels Selected") {
    SettingsView()
        .environmentObject(
            previewState(
                selected: [
                    "INBOX", "STARRED", "lbl_work",
                    "lbl_finance", "lbl_news", "IMPORTANT"
                ],
                behavior: .inlineExpand
            )
        )
        .frame(width: 420, height: 560)
}

#Preview("Long Email") {
    SettingsView()
        .environmentObject(previewState(selected: ["INBOX", "lbl_news"]))
        .frame(width: 420, height: 560)
}

#Preview("Unsubscribed") {
    SettingsView()
        .environmentObject(previewUnsubscribedState())
        .frame(width: 420, height: 560)
}
