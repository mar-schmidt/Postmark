import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var replySheetMessage: EmailMessage?
    @State private var isReplySheetPresented = false

    var body: some View {
        ZStack {
            switch appState.authState {
            case .signedOut:
                SignedOutView()
            case .signedIn:
                InboxListView(
                    viewModel: appState.inboxViewModel,
                    onRequestReply: { message in
                        presentReplySheet(for: message)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.pmBackground)
        .overlay { overlays }
        .overlay(alignment: .top) { toastOverlay }
        .animation(.easeInOut(duration: 0.2), value: isReplySheetPresented)
        .animation(.easeInOut(duration: 0.2), value: appState.isPaywallPresented)
        .task {
            await appState.runStartupSyncIfNeeded()
        }
        .onChange(of: appState.authState) { _, newValue in
            guard newValue == .signedIn else { return }
            Task { await appState.runStartupSyncIfNeeded() }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = appState.newMailToast {
            NewMailToastView(
                item: toast,
                onOpen: { appState.openToastMessage() },
                onArchive: { appState.archiveToastMessage() },
                onClose: { appState.dismissToast() }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(10)
        }
    }

    @ViewBuilder
    private var overlays: some View {
        ZStack {
            if let message = replySheetMessage, isReplySheetPresented {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { dismissReplyOverlay() }
                ReplySheetView(
                    message: message,
                    onSend: { text in
                        await appState.inboxViewModel.reply(
                            to: message,
                            body: text
                        )
                    },
                    onCancel: { dismissReplyOverlay() },
                    onSent: { dismissReplyOverlay() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
            if appState.isPaywallPresented {
                Color.black.opacity(0.26)
                    .ignoresSafeArea()
                    .onTapGesture { appState.dismissPaywall() }
                PaywallView(
                    products: appState.paywallProducts,
                    state: appState.paywallState,
                    selectedProductID: appState.selectedPaywallProductID,
                    onSelected: { productID in
                        appState.selectedPaywallProductID = productID
                        FirebaseAnalyticsService.shared.log(
                            .paywallPlanSelected,
                            parameters: ["product_id": .string(productID)]
                        )
                    },
                    onPurchase: { window in
                        Task {
                            await appState.purchaseSelectedPaywallProduct(
                                confirmIn: window
                            )
                        }
                    },
                    onRestore: {
                        Task { await appState.restorePaywallPurchases() }
                    },
                    onRetry: {
                        Task { await appState.loadPaywallProducts(force: true) }
                    },
                    onClose: { appState.dismissPaywall() },
                    onHostWindowChanged: { window in
                        appState.updatePurchaseConfirmWindow(window)
                    }
                )
                .frame(width: 390)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(2)
            }
        }
    }

    private func presentReplySheet(for message: EmailMessage) {
        replySheetMessage = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isReplySheetPresented = true
        }
    }

    private func dismissReplyOverlay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isReplySheetPresented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            replySheetMessage = nil
        }
    }
}

private struct ReplySheetView: View {
    let message: EmailMessage
    let onSend: @Sendable (String) async -> Void
    let onCancel: () -> Void
    let onSent: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Reply to \(message.sender)")
                        .font(PMFont.display(20, weight: .bold))
                        .foregroundStyle(Color.pmInk)
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.pmMuted)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.pmSoft))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 14)

                ReplyComposerView(
                    subject: message.subject,
                    onSend: { text in
                        await onSend(text)
                        onSent()
                    },
                    onCancel: onCancel
                )
            }
            .padding(20)
            .frame(width: 420)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    topTrailingRadius: 24,
                    style: .continuous
                )
                .fill(Color.pmBackground)
            )
            .accessibilityIdentifier("reply-sheet")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SignedOutView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isErrorExpanded = false
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Color.pmAccent)
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color.pmAccent.opacity(0.35), radius: 18, y: 8)
                .padding(.bottom, 22)

            Text("Postmark")
                .font(PMFont.display(40, weight: .bold))
                .foregroundStyle(Color.pmInk)
                .padding(.bottom, 10)

            Text("Your inbox, distilled to a deck you can clear in seconds.")
                .font(PMFont.body(14.5))
                .foregroundStyle(Color.pmMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.bottom, 28)

            Button {
                Task { await signIn() }
            } label: {
                HStack(spacing: 10) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image("GoogleGMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .background(Circle().fill(.white))
                    }
                    Text(isConnecting ? "Connecting…" : "Continue with Google")
                        .font(PMFont.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: 260)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.pmInk)
                )
                .contentShape(.rect)
            }
            .buttonStyle(PMPressStyle())
            .disabled(isConnecting)

            Text("Postmark never sees your password.")
                .font(PMFont.body(12))
                .foregroundStyle(Color.pmFaint)
                .padding(.top, 16)

            if let errorMessage = appState.errorMessage {
                errorBox(errorMessage)
                    .padding(.top, 18)
                    .frame(maxWidth: 280)
            }
            Spacer()
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pmBackground)
        .onChange(of: appState.errorMessage) { _, _ in
            isErrorExpanded = false
        }
    }

    private func errorBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(PMFont.body(12))
                .foregroundStyle(Color.pmInk)
                .lineLimit(isErrorExpanded ? nil : 3)
                .textSelection(.enabled)
            HStack {
                Button(isErrorExpanded ? "Collapse" : "Expand") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isErrorExpanded.toggle()
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Dismiss") { appState.errorMessage = nil }
                    .buttonStyle(.plain)
            }
            .font(PMFont.body(12, weight: .semibold))
            .foregroundStyle(Color.pmCoral)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.pmCoral.opacity(0.12))
        )
    }

    private func signIn() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            _ = try await appState.connectNewGoogleAccount()
        } catch {
            FirebaseAnalyticsService.shared.log(
                .authSignInFailed,
                parameters: [
                    "error_category": .string(
                        FirebaseAnalyticsService.shared.errorCategory(for: error)
                    )
                ]
            )
            appState.errorMessage = error.localizedDescription
        }
    }
}

#Preview("Signed Out") {
    RootView()
        .environmentObject(AppState.previewSignedOut())
        .frame(width: 420, height: 560)
}

#Preview("Signed In") {
    RootView()
        .environmentObject(AppState.previewSignedIn())
        .frame(width: 420, height: 560)
}
