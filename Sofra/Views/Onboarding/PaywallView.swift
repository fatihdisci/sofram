//
//  PaywallView.swift
//  Sofra — "Dürüst Paywall" (Honest Paywall).
//
//  Core brand differentiator vs Cal AI:
//  • Price shown on the FIRST screen — never hidden behind steps.
//  • Plain-language trial explanation: what happens, when billing starts, how to cancel.
//  • No dark patterns: no pre-checked upsells, no countdown-timer urgency.
//  • One-tap restore purchases.
//  • Cancel path clearly signposted (system subscription management).
//
//  LAYOUT CONTRACT (App Store 3.1.2 + brand promise): every required element —
//  subscription name, price, duration, trial terms, feature list, plan choice,
//  CTA, restore, manage, and the Privacy Policy / Terms links — must be visible
//  on the FIRST screen without scrolling on a modern iPhone. The whole page is a
//  single fixed (non-scrolling) composition sized to fit ~688pt; `ViewThatFits`
//  only falls back to a ScrollView on very small devices (SE) or large Dynamic
//  Type, where clipping would otherwise occur. Do not add sections that push the
//  natural height past the safe-area budget without re-compressing.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var store = StoreKitManager.shared

    let onComplete: () -> Void

    /// Label of the no-purchase escape hatch. Onboarding offers the free tier;
    /// the free-scan-limit / settings sheets override this with a plain "close".
    /// Kept to a single line so the fixed layout stays within its height budget.
    var skipTitle: String = "3 ücretsiz tarama ile devam et"

    @State private var selectedProductID = SofraProductID.annual
    @State private var isRestoring = false

    /// The currently selected product.
    private var selectedProduct: Product? {
        selectedProductID == SofraProductID.monthly
            ? store.monthlyProduct
            : store.annualProduct
    }

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            // Non-scrolling when it fits (every modern iPhone); scrolls only as a
            // safety net on SE-class screens or accessibility text sizes.
            ViewThatFits(in: .vertical) {
                content
                ScrollView(showsIndicators: false) { content }
            }
        }
        .task {
            await store.loadProducts()
        }
    }

    // MARK: - Content composition

    private var content: some View {
        VStack(spacing: Layout.Spacing.lg) {
            heroSection
            planPickerSection
            ctaSection
            footerSection
        }
        .padding(.horizontal, Layout.Spacing.xl)
        .padding(.top, Layout.Spacing.xl)
        .padding(.bottom, Layout.Spacing.lg)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: Layout.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.surfaceRaised)
                    .frame(width: 60, height: 60)
                    .raisedSurface(cornerRadius: 30)
                SofraIconView(icon: .sofra, size: 28)
                    .foregroundStyle(Color.accentFill)
            }

            Text("Sofra Premium")
                .font(.sofraTitle)
                .foregroundStyle(Color.textPrimary)

            priceSummary

            featureCard
        }
    }

    // MARK: - Trial state (driven by the selected product's real intro offer)

    /// Does the currently selected plan offer a free trial the user can start?
    private var selectedHasTrial: Bool { store.hasFreeTrial(selectedProduct) }

    /// Turkish trial length for the selected plan (e.g. "7 gün"), or nil.
    private var selectedTrialText: String? { store.trialPeriodText(for: selectedProduct) }

    /// Trial-vs-price headline, collapsed to two lines so the fold stays intact.
    @ViewBuilder
    private var priceSummary: some View {
        VStack(spacing: 2) {
            if selectedHasTrial, let trial = selectedTrialText {
                Text("\(trial) ücretsiz deneme")
                    .font(.sofraHeading)
                    .foregroundStyle(Color.accentText)
                Text("Sonra \(priceString) · istediğin an iptal")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text(priceString)
                    .font(.sofraHeading)
                    .foregroundStyle(Color.textPrimary)
                Text("İstediğin an iptal edebilirsin")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .multilineTextAlignment(.center)
    }

    // Genuinely Pro-only value — every line is gated behind a subscription:
    //  • scans (photo + text) are capped at 3 lifetime on the free tier;
    //  • Pro requests use the stronger vision model (gpt-5-mini vs -nano),
    //    so recognition is measurably more accurate (see AIProxyClient tiering).
    private var featureCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            featureRow(icon: "infinity", text: "Sınırsız fotoğrafla kalori takibi")
            featureRow(icon: "text.alignleft", text: "Sınırsız yazarak öğün ekleme")
            featureRow(icon: "sparkles", text: "Daha akıllı AI ile daha isabetli tanıma")
            featureRow(icon: "star.fill", text: "Yeni Pro özelliklerine ilk erişim")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.Spacing.md)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Layout.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentFill)
                .frame(width: 20)
            Text(text)
                .font(.sofraLabel)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Plan picker (side-by-side to preserve vertical budget)

    private var planPickerSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("PLAN SEÇ")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)
                .padding(.leading, Layout.Spacing.xs)

            HStack(spacing: Layout.Spacing.sm) {
                planCard(
                    product: store.annualProduct,
                    productID: SofraProductID.annual,
                    badge: "En Uygun",
                    period: "yıl",
                    monthlyEquivalent: store.annualMonthlyPrice
                )
                planCard(
                    product: store.monthlyProduct,
                    productID: SofraProductID.monthly,
                    badge: nil,
                    period: "ay",
                    monthlyEquivalent: nil
                )
            }
        }
    }

    private func planCard(product: Product?, productID: String, badge: String?, period: String, monthlyEquivalent: String?) -> some View {
        let isSelected = selectedProductID == productID
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedProductID = productID
            }
        } label: {
            VStack(spacing: 3) {
                // Reserved badge line keeps both cards the same height.
                Text(badge ?? " ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(badge == nil ? Color.clear : Color.onAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        badge == nil ? Color.clear : Color.accentFill,
                        in: Capsule()
                    )

                Text(periodLabel(for: productID))
                    .font(.sofraLabel)
                    .foregroundStyle(Color.textPrimary)

                Text(product?.displayPrice ?? "…")
                    .font(.sofraNumericSmall)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Reserved sub line: a free trial (annual) takes priority as the
                // strongest conversion cue; otherwise the monthly equivalent /
                // per-period label. Fixed to one line so both cards stay equal height.
                if let trial = store.trialPeriodText(for: product), store.hasFreeTrial(product) {
                    Text("\(trial) ücretsiz")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.accentText)
                } else {
                    Text(monthlyEquivalent.map { "~\($0)/ay" } ?? "/\(period)")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Layout.Spacing.md)
            .padding(.horizontal, Layout.Spacing.sm)
            .background(
                isSelected ? Color.accentTintBg : Color.surfaceRaised,
                in: RoundedRectangle(cornerRadius: Layout.Radius.card)
            )
            .raisedSurface(cornerRadius: Layout.Radius.card)
            .overlay(
                isSelected
                    ? RoundedRectangle(cornerRadius: Layout.Radius.card)
                        .strokeBorder(Color.accentFill, lineWidth: 1.5)
                    : nil
            )
        }
        .buttonStyle(SofraPressButtonStyle(cornerRadius: Layout.Radius.card))
    }

    private func periodLabel(for productID: String) -> String {
        productID == SofraProductID.annual ? "Yıllık" : "Aylık"
    }

    private var periodLabel: String {
        selectedProductID == SofraProductID.annual ? "yıl" : "ay"
    }

    private var priceString: String {
        "\(selectedProduct?.displayPrice ?? "…")/\(periodLabel)"
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: Layout.Spacing.sm) {
            // Purchase / start trial button
            Button {
                guard let product = selectedProduct else { return }
                Task {
                    let success = await store.purchase(product)
                    if success { onComplete() }
                }
            } label: {
                HStack(spacing: Layout.Spacing.sm) {
                    if store.isPurchasing {
                        ProgressView()
                            .tint(Color.onAccent)
                    }
                    Text(ctaLabel)
                        .font(.sofraLabel)
                }
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Layout.Spacing.md)
                .background(
                    selectedProduct != nil && !store.isPurchasing
                        ? Color.accentFill : Color.accentFill.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: Layout.Radius.control)
                )
            }
            .disabled(selectedProduct == nil || store.isPurchasing)

            // Error message (rare/transient; ViewThatFits scrolls if it overflows)
            if let error = store.purchaseError {
                Text(error)
                    .font(.sofraCaption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Free tier skip
            Button {
                onComplete()
            } label: {
                Text(skipTitle)
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }
            .disabled(store.isPurchasing)
        }
    }

    private var ctaLabel: String {
        if store.isPurchasing { return "İşlem yapılıyor..." }
        if selectedHasTrial, let trial = selectedTrialText { return "\(trial) Ücretsiz Dene" }
        return "Abone Ol"
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: Layout.Spacing.sm) {
            // Restore + manage on one row to save vertical space.
            HStack(spacing: Layout.Spacing.sm) {
                Button {
                    Task {
                        isRestoring = true
                        let restored = await store.restorePurchases()
                        isRestoring = false
                        if restored { onComplete() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRestoring {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text("Satın Alımları Geri Yükle")
                            .font(.sofraCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Text("·")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)

                Button {
                    store.openManageSubscriptions()
                } label: {
                    Text("Abonelik Yönetimi")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // Legal — App Store 3.1.2 requires both links on the paywall.
            HStack(spacing: Layout.Spacing.lg) {
                Link("Gizlilik Politikası", destination: LegalLinks.privacyPolicy)
                Link("Kullanım Koşulları", destination: LegalLinks.termsOfUse)
            }
            .font(.sofraCaption)
            .foregroundStyle(Color.accentText)

            // Auto-renewal disclosure (condensed to two lines).
            Text(termsText)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var termsText: String {
        let renewal = "\(priceString) olarak otomatik yenilenir. "
            + "App Store hesabından dilediğin an iptal edebilirsin."
        if selectedHasTrial, let trial = selectedTrialText {
            return "\(trial) ücretsiz deneme sonunda " + renewal
        }
        return "Abonelik " + renewal
    }
}
