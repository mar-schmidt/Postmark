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
        .background(Color.surfacePrimary)
        .overlay {
            ZStack {
                if let message = replySheetMessage, isReplySheetPresented {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissReplyOverlay()
                        }

                    ReplySheetView(
                        message: message,
                        onSend: { text in
                            await appState.inboxViewModel.reply(
                                to: message,
                                body: text
                            )
                        },
                        onCancel: {
                            dismissReplyOverlay()
                        },
                        onSent: {
                            dismissReplyOverlay()
                        }
                    )
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 14)
                    .transition(
                        .scale(scale: 0.94).combined(with: .opacity)
                    )
                    .zIndex(1)
                }
                if appState.isPaywallPresented {
                    Color.black.opacity(0.26)
                        .ignoresSafeArea()
                        .onTapGesture {
                            appState.dismissPaywall()
                        }
                    PaywallView(
                        products: appState.paywallProducts,
                        state: appState.paywallState,
                        selectedProductID: appState.selectedPaywallProductID,
                        onSelected: { productID in
                            appState.selectedPaywallProductID = productID
                            FirebaseAnalyticsService.shared.log(
                                .paywallPlanSelected,
                                parameters: [
                                    "product_id": .string(productID)
                                ]
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
                            Task {
                                await appState.restorePaywallPurchases()
                            }
                        },
                        onRetry: {
                            Task {
                                await appState.loadPaywallProducts(force: true)
                            }
                        },
                        onClose: {
                            appState.dismissPaywall()
                        },
                        onHostWindowChanged: { window in
                            appState.updatePurchaseConfirmWindow(window)
                        }
                    )
                    .frame(width: 390)
                    .transition(
                        .scale(scale: 0.95).combined(with: .opacity)
                    )
                    .zIndex(2)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isReplySheetPresented)
        .animation(
            .easeInOut(duration: 0.2),
            value: appState.isPaywallPresented
        )
        .task {
            await appState.runStartupSyncIfNeeded()
        }
        .onChange(of: appState.authState) { _, newValue in
            guard newValue == .signedIn else { return }
            Task {
                await appState.runStartupSyncIfNeeded()
            }
        }
    }

    private func presentReplySheet(for message: EmailMessage) {
        replySheetMessage = message
        withAnimation(.easeInOut(duration: 0.2)) {
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Reply to \(message.sender)")
                .font(.headline)
            ReplyComposerView(
                onSend: { text in
                    await onSend(text)
                    onSent()
                },
                onCancel: {
                    onCancel()
                }
            )
        }
        .padding()
        .frame(width: 360, height: 220)
        .accessibilityIdentifier("reply-sheet")
    }
}

private struct SignedOutView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isErrorExpanded = false

    var body: some View {
        VStack(spacing: 14) {
          Spacer()
            Image(systemName: "tray.full")
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    Color.accentColor,
                    Color.stateInfo
                )
                .padding(12)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.26),
                                    Color.stateInfo.opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(
                    color: Color.stateInfo.opacity(0.25),
                    radius: 10,
                    x: 0,
                    y: 6
                )
            Text("Postmark")
                .font(.title2.bold())
            Text("Sign in with Gmail to read and reply quickly.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Continue with Google") {
                Task { await signIn() }
            }
            .buttonStyle(.borderedProminent)
            
            if let errorMessage = appState.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.caption)
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

                        Button("Dismiss") {
                            appState.errorMessage = nil
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.stateDestructive.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
          Spacer()
        }
        .padding(20)
        .onChange(of: appState.errorMessage) { _, _ in
            isErrorExpanded = false
        }
    }

    private func signIn() async {
        do {
            _ = try await appState.connectNewGoogleAccount()
        } catch {
            FirebaseAnalyticsService.shared.log(
                .authSignInFailed,
                parameters: [
                    "error_category": .string(
                        FirebaseAnalyticsService.shared.errorCategory(
                            for: error
                        )
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
