import SwiftUI

struct InboxListView: View {
    private let rowExpansionAnimation = Animation.spring(
        response: 0.32,
        dampingFraction: 0.92,
        blendDuration: 0.08
    )

    private enum Screen {
        case inbox
        case settings
        case addAccount
        case detail(EmailMessage)
    }

    @ObservedObject var viewModel: InboxViewModel
    let onRequestReply: (EmailMessage) -> Void
    @EnvironmentObject private var appState: AppState
    @State private var screen: Screen = .inbox
    @State private var expandedMessageID: String?
    @State private var isErrorExpanded = false
    @State private var labelNamesByID: [String: String] = [:]
    @State private var isArchivingFromDetail = false

    var body: some View {
        VStack(spacing: 0) {
            header
            errorBanner
            Group {
                content
            }
            .animation(.easeInOut(duration: 0.2), value: screenID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.pmBackground)
        .onChange(of: viewModel.errorMessage) { _, _ in
            isErrorExpanded = false
        }
        .task {
            await appState.runStartupSyncIfNeeded()
            await loadLabelNames()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .inbox:
            if viewModel.isLoading && viewModel.messages.isEmpty {
                loadingView
            } else if viewModel.messages.isEmpty {
                inboxZeroView
            } else {
                inboxList
            }
        case .settings:
            SettingsView(onAddAccount: {
                if appState.requestAddAccountAccess() {
                    navigate(to: .addAccount)
                }
            })
            .environmentObject(appState)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .addAccount:
            AddAccountView(onConnected: { _ in
                navigate(to: .settings)
            })
            .environmentObject(appState)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .detail(let message):
            EmailDetailView(message: message)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var inboxList: some View {
        List {
            ForEach(viewModel.messages) { message in
                row(
                    for: message,
                    isTrailingMessage: message.id == viewModel.messages.last?.id
                )
                .padding(.top, 5)
                .padding(.horizontal, 14)
                .padding(.bottom, 5)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if viewModel.nextPageToken != nil {
                paginationRow
                    .padding(.top, 6)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .accessibilityIdentifier("inbox-list")
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading your inbox…")
                .font(PMFont.body(13))
                .foregroundStyle(Color.pmMuted)
                .padding(.top, 10)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if case .inbox = screen {
            inboxHeader
        } else {
            navHeader
        }
    }

    private var inboxHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Inbox")
                    .font(PMFont.display(28, weight: .bold))
                    .foregroundStyle(Color.pmInk)
                Text(inboxCountLabel)
                    .font(PMFont.body(12))
                    .foregroundStyle(Color.pmMuted)
            }
            Spacer()
            HStack(spacing: 8) {
                iconTile(systemName: "arrow.clockwise") {
                    Task { await viewModel.refresh() }
                }
                iconTile(systemName: "gearshape") {
                    navigate(to: .settings)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func iconTile(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.pmMuted)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.pmSoft)
                )
                .contentShape(.rect)
        }
        .buttonStyle(PMPressStyle())
    }

    private var navHeader: some View {
        HStack {
            Button {
                guard !isArchivingFromDetail else { return }
                navigate(to: previousScreen)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                    Text("Inbox")
                }
                .font(PMFont.body(14))
                .foregroundStyle(Color.pmMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isArchivingFromDetail)

            Spacer()

            Text(titleText)
                .font(PMFont.display(22, weight: .bold))
                .foregroundStyle(Color.pmInk)

            Spacer()

            if case .detail(let message) = screen {
                detailActions(for: message)
            } else {
                Color.clear.frame(width: 52, height: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.pmLine).frame(height: 1)
        }
    }

    @ViewBuilder
    private func detailActions(for message: EmailMessage) -> some View {
        HStack(spacing: 14) {
            Button {
                guard !isArchivingFromDetail else { return }
                onRequestReply(message)
            } label: {
                Text("Reply")
                    .font(PMFont.body(14, weight: .bold))
                    .foregroundStyle(Color.pmAccent)
            }
            .buttonStyle(PMPressStyle())
            .disabled(isArchivingFromDetail)

            Button {
                guard !isArchivingFromDetail else { return }
                Task { await archiveFromDetail(message) }
            } label: {
                Group {
                    if isArchivingFromDetail {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Archive")
                            .font(PMFont.body(14, weight: .bold))
                            .foregroundStyle(Color.pmCoral)
                    }
                }
                .frame(minWidth: 52)
                .contentShape(.rect)
            }
            .buttonStyle(PMPressStyle())
            .disabled(isArchivingFromDetail)
        }
    }

    private var errorBanner: some View {
        Group {
            if let message = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(PMFont.body(12))
                        .foregroundStyle(Color.pmInk)
                        .lineLimit(isErrorExpanded ? nil : 2)
                        .textSelection(.enabled)
                    HStack {
                        Button(isErrorExpanded ? "Collapse" : "Expand") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isErrorExpanded.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button("Dismiss") { viewModel.errorMessage = nil }
                            .buttonStyle(.plain)
                    }
                    .font(PMFont.body(12, weight: .semibold))
                    .foregroundStyle(Color.pmCoral)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pmCoral.opacity(0.12))
            }
        }
    }

    // MARK: - Inbox zero

    private var inboxZeroView: some View {
        VStack(spacing: 12) {
            Spacer()
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.pmOkSoft)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.pmOk)
                )
            Text("Inbox zero")
                .font(PMFont.display(26, weight: .bold))
                .foregroundStyle(Color.pmInk)
            Text("Every card cleared. Nothing left to triage.")
                .font(PMFont.body(13.5))
                .foregroundStyle(Color.pmMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            labelBadgesView
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private var labelBadgesView: some View {
        let selectedLabels = appState.selectedLabelIDs.map { labelID in
            (id: labelID, name: labelNamesByID[labelID] ?? labelID)
        }
        return HStack(spacing: 6) {
            ForEach(Array(selectedLabels.enumerated()), id: \.element.id) {
                index, label in
                ZStack(alignment: .topTrailing) {
                    Text(label.name)
                        .font(PMFont.body(12, weight: .semibold))
                        .foregroundStyle(Color.pmAccent)
                        .padding(.leading, 10)
                        .padding(.trailing, 18)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.pmAccentSoft))
                    if appState.selectedLabelIDs.count > 1 {
                        Button {
                            removeSelectedLabel(label.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white, Color.pmCoral)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 3, y: -3)
                        .accessibilityLabel("Remove \(label.name) label")
                    }
                }
            }
        }
    }

    private func removeSelectedLabel(_ labelID: String) {
        guard appState.selectedLabelIDs.count > 1 else { return }
        appState.selectedLabelIDs.removeAll { $0 == labelID }
    }

    private func loadLabelNames() async {
        guard let provider = appState.providerManager.activeProvider else {
            return
        }
        do {
            let labels = try await provider.fetchLabels()
            labelNamesByID = labels.reduce(into: [:]) { lookup, label in
                lookup[label.id] = label.name
            }
        } catch {
            // Keep ID fallback in empty-state text if lookup fails.
        }
    }

    private func row(
        for message: EmailMessage,
        isTrailingMessage: Bool
    ) -> some View {
        EmailRowView(
            message: message,
            isExpanded: expandedMessageID == message.id,
            onSelect: { handleSelection(for: message) }
        )
        .accessibilityIdentifier("inbox-message-\(message.id)")
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Reply") { onRequestReply(message) }
                .tint(Color.pmAccent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Archive") {
                Task { await viewModel.archive(message) }
            }
            .tint(Color.pmCoral)
        }
        .onAppear {
            guard isTrailingMessage else { return }
            Task {
                await viewModel.loadMoreIfNeededForTrailingMessage(message.id)
            }
        }
    }

    private var paginationRow: some View {
        HStack(spacing: 8) {
            Spacer()
            if viewModel.isLoadingMore {
                ProgressView().controlSize(.small)
                Text("Loading more…")
                    .font(PMFont.body(12))
                    .foregroundStyle(Color.pmMuted)
            } else {
                Text("Scroll to load more")
                    .font(PMFont.body(12))
                    .foregroundStyle(Color.pmFaint)
            }
            Spacer()
        }
    }

    private var inboxCountLabel: String {
        let unread = viewModel.messages.filter(\.isUnread).count
        if unread > 0 {
            return "\(unread) unread · \(viewModel.messages.count) total"
        }
        return "\(viewModel.messages.count) message"
            + (viewModel.messages.count == 1 ? "" : "s")
    }

    private var titleText: String {
        switch screen {
        case .inbox: return "Inbox"
        case .settings: return "Settings"
        case .addAccount: return "Add Account"
        case .detail: return "Email"
        }
    }

    private var previousScreen: Screen {
        switch screen {
        case .addAccount: return .settings
        case .settings, .detail, .inbox: return .inbox
        }
    }

    private func handleSelection(for message: EmailMessage) {
        switch appState.emailOpenBehavior {
        case .inlineExpand:
            withAnimation(rowExpansionAnimation) {
                expandedMessageID =
                    expandedMessageID == message.id ? nil : message.id
            }
        case .openDetail:
            navigate(to: .detail(message))
        }
    }

    private var screenID: String {
        switch screen {
        case .inbox: return "inbox"
        case .settings: return "settings"
        case .addAccount: return "add-account"
        case .detail(let message): return "detail-\(message.id)"
        }
    }

    private func navigate(to destination: Screen) {
        withAnimation(.easeInOut(duration: 0.2)) {
            screen = destination
        }
    }

    private func archiveFromDetail(_ message: EmailMessage) async {
        isArchivingFromDetail = true
        defer { isArchivingFromDetail = false }
        await viewModel.archive(message)
        navigate(to: .inbox)
    }
}

/// A subtle press-scale style used for header controls.
struct PMPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

#Preview("Signed In") {
    RootView()
        .environmentObject(AppState.previewSignedIn())
        .frame(width: 420, height: 560)
}
