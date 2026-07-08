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

import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var store = StoreKitManager.shared

    let onComplete: () -> Void

    /// Label of the no-purchase escape hatch. Onboarding offers the free tier;
    /// the free-scan-limit screen overrides this with a plain "close".
    var skipTitle: String = "Ücretsiz denemek istemiyorum, 3 tarama ile devam et"

    @State private var selectedProductID = SofraProductID.annual
    @State private var isRestoring = false
    @State private var showManageSheet = false

    /// The currently selected product.
    private var selectedProduct: Product? {
        selectedProductID == SofraProductID.monthly
            ? store.monthlyProduct
            : store.annualProduct
    }

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Layout.Spacing.xl) {
                    // Hero
                    heroSection

                    // Plan picker
                    planPickerSection

                    // CTA
                    ctaSection

                    // Restore + cancel
                    footerSection
                }
                .padding(.horizontal, Layout.Spacing.xl)
                .padding(.top, 80)
                .padding(.bottom, 50)
            }
        }
        .task {
            await store.loadProducts()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: Layout.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.surfaceRaised)
                    .frame(width: 92, height: 92)
                    .raisedSurface(cornerRadius: 46)
                SofraIconView(icon: .sofra, size: 42)
                    .foregroundStyle(Color.accentFill)
            }

            Text("Sofra Premium")
                .font(.sofraTitle)
                .foregroundStyle(Color.textPrimary)

            if store.isEligibleForTrial {
                VStack(spacing: Layout.Spacing.xs) {
                    Text("3 gün ücretsiz deneme")
                        .font(.sofraHeading)
                        .foregroundStyle(Color.accentText)

                    Text("Sonrasında \(selectedProduct?.displayPrice ?? "...") / \(periodLabel)")
                        .font(.sofraBody)
                        .foregroundStyle(Color.textSecondary)

                    Text("Dilediğiniz zaman iptal edebilirsiniz.\nDeneme süresi bitmeden 24 saat önce hatırlatırız.")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("\(selectedProduct?.displayPrice ?? "...") / \(periodLabel)")
                    .font(.sofraHeading)
                    .foregroundStyle(Color.textPrimary)

                Text("Dilediğiniz zaman iptal edebilirsiniz.")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }

            // Feature list
            VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                featureRow(icon: "camera.fill", text: "Sınırsız fotoğrafla kalori takibi")
                featureRow(icon: "text.alignleft", text: "Yazarak kalori ekleme")
                featureRow(icon: "chart.pie.fill", text: "Detaylı günlük ve haftalık raporlar")
                featureRow(icon: "bell.fill", text: "Deneme süresi bitiş hatırlatması")
            }
            .padding(Layout.Spacing.lg)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Layout.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentFill)
                .frame(width: 22)
            Text(text)
                .font(.sofraBody)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Plan picker

    private var planPickerSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("PLAN SEÇ")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)
                .padding(.leading, Layout.Spacing.xs)

            // Annual (recommended)
            planCard(
                product: store.annualProduct,
                productID: SofraProductID.annual,
                badge: "En Uygun",
                period: "yıl",
                monthlyEquivalent: store.annualMonthlyPrice
            )

            // Monthly
            planCard(
                product: store.monthlyProduct,
                productID: SofraProductID.monthly,
                badge: nil,
                period: "ay",
                monthlyEquivalent: nil
            )
        }
    }

    private func planCard(product: Product?, productID: String, badge: String?, period: String, monthlyEquivalent: String?) -> some View {
        let isSelected = selectedProductID == productID
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedProductID = productID
            }
        } label: {
            HStack(spacing: Layout.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Layout.Spacing.xs) {
                        Text(periodLabel(for: productID))
                            .font(.sofraLabel)
                            .foregroundStyle(Color.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.onAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentFill, in: Capsule())
                        }
                    }
                    if let monthlyEquivalent {
                        Text("~\(monthlyEquivalent)/ay")
                            .font(.sofraCaption)
                            .foregroundStyle(Color.textMuted)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product?.displayPrice ?? "...")
                        .font(.sofraNumericSmall)
                        .foregroundStyle(Color.textPrimary)
                    Text("/\(period)")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentFill)
                } else {
                    Circle()
                        .strokeBorder(Color.borderHairline, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(Layout.Spacing.lg)
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
        .buttonStyle(.plain)
    }

    private func periodLabel(for productID: String) -> String {
        productID == SofraProductID.annual ? "Yıllık" : "Aylık"
    }

    private var periodLabel: String {
        selectedProductID == SofraProductID.annual ? "yıl" : "ay"
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

            // Error message
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
            }
            .disabled(store.isPurchasing)
        }
    }

    private var ctaLabel: String {
        if store.isPurchasing { return "İşlem yapılıyor..." }
        if store.isEligibleForTrial { return "3 Gün Ücretsiz Dene" }
        return "Abone Ol"
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: Layout.Spacing.md) {
            // Restore
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
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text("Aboneliği Geri Yükle")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // Cancel / manage
            Button {
                store.openManageSubscriptions()
            } label: {
                Text("Abonelik Yönetimi")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }

            // Terms
            Text(termsText)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var termsText: String {
        """
        Deneme süresi sonunda \(selectedProduct?.displayPrice ?? "...") karşılığında otomatik olarak yenilenir.
        Aboneliğiniz, satın alma onayı ile Apple Kimliğinize yansıtılır.
        Aboneliğinizi App Store hesap ayarlarınızdan istediğiniz zaman iptal edebilirsiniz.
        İptal durumunda mevcut dönemin kalan kısmı için geri ödeme yapılmaz.
        """
    }
}
