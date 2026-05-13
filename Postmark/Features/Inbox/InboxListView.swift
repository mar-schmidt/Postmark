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
                Spacer()
                ProgressView("Loading inbox...")
                Spacer()
            } else if viewModel.messages.isEmpty {
                emptyInboxView
            } else {
                List {
                    ForEach(viewModel.messages) { message in
                        row(
                            for: message,
                            isTrailingMessage: message.id
                                == viewModel.messages.last?.id
                        )
                        .padding(.top, 5)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 5)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    if viewModel.nextPageToken != nil {
                        paginationRow
                            .padding(.top, 6)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
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
                .transition(
                    .move(edge: .trailing).combined(with: .opacity)
                )
        }
    }

    private var header: some View {
        HStack {
            if case .inbox = screen {
                Image(systemName: "tray")
                    .opacity(0)
                    .allowsHitTesting(false)
            } else {
                Button {
                    guard !isArchivingFromDetail else { return }
                    navigate(to: previousScreen)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isArchivingFromDetail)
            }

            Spacer()

            Text(titleText)
                .font(.title3.bold())

            Spacer()

            if case .inbox = screen {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button {
                    navigate(to: .settings)
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else if case .detail(let message) = screen {
                Button {
                    guard !isArchivingFromDetail else { return }
                    onRequestReply(message)
                } label: {
                    Text("Reply")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .buttonStyle(PressAnimatedButtonStyle())
                .disabled(isArchivingFromDetail)
                Button {
                    guard !isArchivingFromDetail else { return }
                    Task { await archiveFromDetail(message) }
                } label: {
                    Group {
                        if isArchivingFromDetail {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Archive")
                        }
                    }
                    .frame(minWidth: 56, minHeight: 30)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .buttonStyle(PressAnimatedButtonStyle())
                .disabled(isArchivingFromDetail)
            }
        }
        .padding(12)
    }

    private var errorBanner: some View {
        Group {
            if let message = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.caption)
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

                        Button("Dismiss") {
                            viewModel.errorMessage = nil
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.stateDestructive.opacity(0.14))
            }
        }
    }

    private var emptyInboxView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("No emails found for selected labels.")
                .font(.headline)
            labelBadgesView
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
            ForEach(
                Array(selectedLabels.enumerated()),
                id: \.element.id
            ) { index, label in
                ZStack(alignment: .topTrailing) {
                    Text(label.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badgeForegroundColor(for: index))
                        .padding(.leading, 8)
                        .padding(.trailing, 18)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(badgeBackgroundColor(for: index))
                        )

                    Button {
                        removeSelectedLabel(label.id)
                    } label: {
                      Image(systemName: "xmark.circle.fill")
                          .font(.system(size: 10, weight: .bold))
                          .foregroundStyle(.white, Color.stateDestructive)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 3, y: -3)
                    .accessibilityLabel("Remove \(label.name) label")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func removeSelectedLabel(_ labelID: String) {
        guard appState.selectedLabelIDs.count > 1 else { return }
        appState.selectedLabelIDs.removeAll { $0 == labelID }
    }

    private func badgeBackgroundColor(for index: Int) -> Color {
        let palette = Color.tagPalette.map { $0.opacity(0.2) }
        return palette[index % palette.count]
    }

    private func badgeForegroundColor(for index: Int) -> Color {
        let palette = Color.tagPalette
        return palette[index % palette.count]
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
            onSelect: {
                handleSelection(for: message)
            }
        )
        .accessibilityIdentifier("inbox-message-\(message.id)")
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Reply") {
                onRequestReply(message)
            }
            .tint(Color.stateInfo)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Archive") {
                Task { await viewModel.archive(message) }
            }
            .tint(Color.stateWarning)
        }
        .onAppear {
            guard isTrailingMessage else { return }
            Task {
                await viewModel.loadMoreIfNeededForTrailingMessage(
                    message.id
                )
            }
        }
    }

    private var paginationRow: some View {
        HStack(spacing: 8) {
            Spacer()
            if viewModel.isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                Text("Loading more...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Scroll to load more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var titleText: String {
        switch screen {
        case .inbox:
            return "Inbox"
        case .settings:
            return "Settings"
        case .addAccount:
            return "Add Account"
        case .detail:
            return "Email"
        }
    }

    private var previousScreen: Screen {
        switch screen {
        case .addAccount:
            return .settings
        case .settings, .detail:
            return .inbox
        case .inbox:
            return .inbox
        }
    }

    private func handleSelection(for message: EmailMessage) {
        switch appState.emailOpenBehavior {
        case .inlineExpand:
            withAnimation(rowExpansionAnimation) {
                if expandedMessageID == message.id {
                    expandedMessageID = nil
                    return
                }
                expandedMessageID = message.id
            }
        case .openDetail:
            navigate(to: .detail(message))
        }
    }

    private var screenID: String {
        switch screen {
        case .inbox:
            return "inbox"
        case .settings:
            return "settings"
        case .addAccount:
            return "add-account"
        case .detail(let message):
            return "detail-\(message.id)"
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

private struct PressAnimatedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
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
