import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isConnecting = false
    @State private var isConnected = false
    @State private var errorMessage: String?
    var onConnected: ((Account) -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            if isConnected {
                successState
            } else {
                providerContent
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.stateWarning)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(20)
    }

    private var providerContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Choose a provider")
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    "Your credentials are handled directly by the " +
                    "provider - Postmark never sees your password."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            googleButton
            placeholderProviders
        }
        .frame(maxWidth: 320)
    }

    private var googleButton: some View {
        Button {
            Task {
                await connectGoogle()
            }
        } label: {
            HStack(spacing: 10) {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image("GoogleGMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
                Text(isConnecting ? "Connecting..." : "Sign in with Google")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color.borderSubtle.opacity(0.8),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
    }

    private var placeholderProviders: some View {
        VStack(spacing: 8) {
            ForEach(["Outlook / Microsoft 365", "iCloud Mail"], id: \.self) {
                name in
                HStack {
                    Text(name)
                    Spacer()
                    Text("SOON")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    Color.surfacePrimary,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            Color.borderSubtle.opacity(0.75),
                            lineWidth: 1.5
                        )
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private var successState: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Color.stateSuccess)
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .shadow(
                    color: Color.stateSuccess.opacity(0.35),
                    radius: 16
                )
            VStack(spacing: 4) {
                Text("Account connected")
                    .font(.system(size: 15, weight: .semibold))
                Text("Loading your inbox...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func connectGoogle() async {
        guard !isConnecting else { return }
        guard appState.requestAddAccountAccess() else { return }
        errorMessage = nil
        isConnecting = true
        do {
            let account = try await appState.connectNewGoogleAccount()
            isConnecting = false
            isConnected = true
            try await Task.sleep(for: .seconds(1))
            onConnected?(account)
        } catch {
            isConnecting = false
            errorMessage = error.localizedDescription
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
        }
    }
}

#Preview("Add Account") {
    AddAccountView()
        .environmentObject(AppState.previewSignedOut())
        .frame(width: 420, height: 560)
}
