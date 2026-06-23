import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct PaywallView: View {
    let products: [BillingProduct]
    let state: PaywallState
    let selectedProductID: String?
    let onSelected: (String) -> Void
    let onPurchase: (NSWindow?) -> Void
    let onRestore: () -> Void
    let onRetry: () -> Void
    let onClose: () -> Void
    let onHostWindowChanged: (NSWindow?) -> Void
    @State private var hostWindow: NSWindow?

    private let featureHighlights = [
        "Add unlimited accounts",
        "Family Sharing"
    ]

    var body: some View {
        VStack(spacing: 14) {
            header
            plansSection
            featuresSection
            if let error = state.errorMessage {
                errorSection(error)
            }
            actionSection
            footerSection
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.surfacePrimary.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            Color.borderSubtle.opacity(0.7),
                            lineWidth: 1
                        )
                )
        )
        .background(
            PaywallPurchaseHostBridge { window in
                if hostWindow !== window {
                    hostWindow = window
                }
                onHostWindowChanged(window)
            }
            .frame(width: 0, height: 0)
        )
        .accessibilityIdentifier("paywall-view")
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.3),
                                Color.stateInfo.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text("Unlock Postmark Pro")
                .font(PMFont.display(26, weight: .bold))
            Text("Add more than one account and unlock future Pro features.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if hasTrialOffer {
                Text("7-day free trial included")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.stateSuccess.opacity(0.16))
                    )
                    .foregroundStyle(Color.stateSuccess)
            }
        }
    }

    private var plansSection: some View {
        VStack(spacing: 8) {
            ForEach(products) { product in
                PaywallPlanCard(
                    product: product,
                    isSelected: selectedProductID == product.id
                ) {
                    onSelected(product.id)
                }
            }
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is included")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(featureHighlights, id: \.self) { line in
                    PaywallFeatureRow(text: line)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceSecondary.opacity(0.45))
        )
    }

    private func errorSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.stateWarning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.plain)
            .font(.caption.bold())
            .foregroundStyle(Color.accentColor)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.stateWarning.opacity(0.11))
        )
    }

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button(primaryButtonTitle) {
                onPurchase(hostWindow)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canPurchase)
            .accessibilityIdentifier("paywall-purchase-button")

            Button("Restore purchases") {
                onRestore()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .disabled(isWorking)
        }
    }

    private var footerSection: some View {
        HStack {
            Button("Not now") {
                onClose()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Text("Auto-renewing subscription.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var isWorking: Bool {
        if case .loading = state { return true }
        if case .restoring = state { return true }
        if case .purchasing = state { return true }
        return false
    }

    private var canPurchase: Bool {
        selectedProductID != nil && !isWorking
    }

    private var primaryButtonTitle: String {
        switch state {
        case .loading:
            return "Loading plans..."
        case .purchasing:
            return "Purchasing..."
        case .restoring:
            return "Restoring..."
        default:
          return hasTrialOffer ? "Start free trial" : "Purchase"
        }
    }

    private var hasTrialOffer: Bool {
        guard let selectedProductID else {
            return products.first?.hasIntroOffer == true
        }
        return products.first(where: { $0.id == selectedProductID })?
            .hasIntroOffer == true
    }
}

struct PaywallPlanCard: View {
    let product: BillingProduct
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.period.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(product.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        isSelected ? Color.accentColor : Color.primary
                    )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.14)
                            : Color.surfacePrimary
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? Color.accentColor.opacity(0.45)
                                    : Color.borderSubtle.opacity(0.65),
                                lineWidth: 1.3
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct PaywallFeatureRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.stateSuccess)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

private struct PaywallPurchaseHostBridge: NSViewRepresentable {
    let onWindowChanged: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onWindowChanged(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onWindowChanged(nsView.window)
        }
    }
}

#Preview("Paywall Loaded") {
    ZStack {
        Color.appBackgroundNeutral.opacity(0.3).ignoresSafeArea()
        PaywallView(
            products: [
                BillingProduct(
                    id: PaywallProductID.annual,
                    displayName: "Best value",
                    displayPrice: "100 kr",
                    period: .year,
                    hasIntroOffer: false
                ),
                BillingProduct(
                    id: PaywallProductID.monthly,
                    displayName: "Flexible",
                    displayPrice: "9 kr",
                    period: .month,
                    hasIntroOffer: true
                )
            ],
            state: .loaded,
            selectedProductID: PaywallProductID.annual,
            onSelected: { _ in },
            onPurchase: { _ in },
            onRestore: {},
            onRetry: {},
            onClose: {},
            onHostWindowChanged: { _ in }
        )
        .frame(width: 390)
    }
    .frame(width: 420, height: 560)
}

#Preview("Paywall Error") {
    ZStack {
        Color.appBackgroundNeutral.opacity(0.3).ignoresSafeArea()
        PaywallView(
            products: [],
            state: .error("Could not load plans. Check connection."),
            selectedProductID: nil,
            onSelected: { _ in },
            onPurchase: { _ in },
            onRestore: {},
            onRetry: {},
            onClose: {},
            onHostWindowChanged: { _ in }
        )
        .frame(width: 390)
    }
    .frame(width: 420, height: 560)
}

#Preview("Plan Card") {
    PaywallPlanCard(
        product: BillingProduct(
            id: PaywallProductID.monthly,
            displayName: "Flexible billing",
            displayPrice: "9 kr",
            period: .month,
            hasIntroOffer: true
        ),
        isSelected: true,
        onTap: {}
    )
    .padding()
    .frame(width: 320)
}

#Preview("Feature Row") {
    PaywallFeatureRow(text: "Add unlimited accounts")
        .padding()
        .frame(width: 320)
}
