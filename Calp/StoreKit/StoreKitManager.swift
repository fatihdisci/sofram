//
//  StoreKitManager.swift
//  Calp — native StoreKit 2 subscription management.
//
//  No RevenueCat, no third-party SDK. Direct Product/Transaction/Transaction.updates
//  API usage, following the pattern shipped in the developer's "Arvia" app.
//
//  Responsibilities:
//   • Fetch products (monthly without trial; annual with a 7-day intro trial)
//   • Purchase flow (+ userCancelled / pending handling)
//   • Restore via AppStore.sync()
//   • Transaction.updates listener (renewals, family sharing, out-of-band)
//   • Entitlement: keeps FreeScanCounter.isSubscribed in sync
//   • Trial eligibility check
//   • Trial-end notification (24h before billing)
//

import Foundation
import StoreKit
import Observation
import UIKit
import UserNotifications

// MARK: - Product identifiers

enum CalpProductID {
    static let monthly = "com.fatih.calp.monthly"
    static let annual  = "com.fatih.calp.annual"
    static let all      = [monthly, annual]
}

// MARK: - Manager

@MainActor
@Observable
final class StoreKitManager {

    static let shared = StoreKitManager()

    // MARK: State

    private(set) var monthlyProduct: Product?
    private(set) var annualProduct: Product?
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?

    /// True when the user holds an active subscription (not expired, not in grace).
    private(set) var isSubscribed = false

    /// The currently active product (if subscribed).
    private(set) var activeProductID: String?

    /// Product IDs the user is currently eligible to start a free trial on.
    /// Driven per-product (the annual plan carries the 7-day trial, the monthly
    /// plan has none), so the paywall can show trial copy only for the plan that
    /// actually offers it. Empty until `checkTrialEligibility()` runs.
    private(set) var trialEligibleProductIDs: Set<String> = []

    /// Legacy convenience: true if ANY product offers a trial the user can start.
    var isEligibleForTrial: Bool { !trialEligibleProductIDs.isEmpty }

    // MARK: - Init

    init() {
        // Start the transaction listener at init (runs for app lifetime).
        Task { await listenForTransactions() }
        // Check current entitlements.
        Task { await updateEntitlements() }
    }

    // MARK: - Product fetching

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: CalpProductID.all)
            for product in products {
                switch product.id {
                case CalpProductID.monthly: monthlyProduct = product
                case CalpProductID.annual:  annualProduct  = product
                default: break
                }
            }
            // Check trial eligibility
            await checkTrialEligibility()
        } catch {
            purchaseError = "Ürünler yüklenemedi. Lütfen tekrar deneyin."
        }
    }

    private func checkTrialEligibility() async {
        // A product qualifies only if it carries a free-trial introductory offer
        // AND the user hasn't already consumed an intro offer in its group.
        var eligible: Set<String> = []
        for product in [monthlyProduct, annualProduct].compactMap({ $0 }) {
            guard let info = product.subscription,
                  info.introductoryOffer?.paymentMode == .freeTrial,
                  await info.isEligibleForIntroOffer
            else { continue }
            eligible.insert(product.id)
        }
        trialEligibleProductIDs = eligible
    }

    /// True when this specific product offers a free trial the user can start now.
    func hasFreeTrial(_ product: Product?) -> Bool {
        guard let id = product?.id else { return false }
        return trialEligibleProductIDs.contains(id)
    }

    /// Human-readable Turkish trial length for a product's intro offer
    /// (e.g. "7 gün", "3 gün", "1 ay"), read from the real StoreKit period so
    /// the copy always matches whatever is configured in App Store Connect.
    /// Returns nil when the product has no free-trial offer.
    func trialPeriodText(for product: Product?) -> String? {
        guard let offer = product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        let value = period.value
        switch period.unit {
        case .day:   return "\(value) gün"
        case .week:  return "\(value * 7) gün"   // 1 hafta → "7 gün"
        case .month: return value == 1 ? "1 ay" : "\(value) ay"
        case .year:  return value == 1 ? "1 yıl" : "\(value) yıl"
        @unknown default: return "\(value) gün"
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await updateEntitlements()
                    if transaction.offerType == .introductory {
                        scheduleTrialEndNotification(for: transaction)
                    }
                    return true
                }
                return false

            case .userCancelled:
                return false

            case .pending:
                purchaseError = "Ödeme onay bekliyor. Onaylandığında aboneliğiniz aktif olacak."
                return false

            @unknown default:
                return false
            }
        } catch {
            purchaseError = "Satın alma başarısız. Lütfen tekrar deneyin."
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            await updateEntitlements()
            return isSubscribed
        } catch {
            purchaseError = "Geri yükleme başarısız. Lütfen tekrar deneyin."
            return false
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            guard case .verified(let transaction) = verification else { continue }
            await transaction.finish()
            await updateEntitlements()
        }
    }

    // MARK: - Entitlement check

    func updateEntitlements() async {
        var subscribed = false
        var productID: String?

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }

            // Check subscription is active (not expired, revoked, or in grace)
            if let expiration = transaction.expirationDate,
               expiration > Date(),
               transaction.revocationDate == nil {
                // Grace period: product is still considered active but the user
                // should be notified. We treat it as subscribed for access.
                subscribed = true
                productID = transaction.productID
                break
            }
        }

        isSubscribed = subscribed
        activeProductID = productID
        // Keep DEBUG's independent force-Pro gate stable when StoreKit reports
        // no entitlement. A real verified entitlement still propagates.
        #if DEBUG
        if subscribed {
            FreeScanCounter.shared.isSubscribed = true
        }
        #else
        FreeScanCounter.shared.isSubscribed = subscribed
        #endif
    }

    /// Returns the signed StoreKit transaction used by the proxy to make the
    /// authoritative Pro decision. Only a currently active, verified
    /// subscription is eligible to leave the device.
    func currentEntitlementJWS() async -> String? {
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  CalpProductID.all.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  let expiration = transaction.expirationDate,
                  expiration > Date()
            else { continue }
            return verification.jwsRepresentation
        }
        return nil
    }

    // MARK: - Trial-end notification

    /// Schedules a local notification 24 hours before the trial billing date.
    func scheduleTrialEndNotification(for transaction: Transaction) {
        guard let expiration = transaction.expirationDate else { return }
        let triggerDate = expiration.addingTimeInterval(-24 * 3600)
        guard triggerDate > Date() else { return } // trial < 24h away, don't schedule

        let content = UNMutableNotificationContent()
        content.title = "Deneme süreniz bitiyor"
        content.body = "Yarın ücretlendirileceksiniz. İsterseniz şimdi iptal edebilirsiniz."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "calp.trialEnd.\(transaction.id)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                #if DEBUG
                print("⚠️ Trial notification scheduling failed: \(error)")
                #endif
            }
        }
    }

    /// Cancels the trial-end notification (called if user cancels early).
    func cancelTrialEndNotification(for transactionID: UInt64) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["calp.trialEnd.\(transactionID)"])
    }

    // MARK: - Open subscription management

    func openManageSubscriptions() {
        Task { @MainActor in
            #if os(iOS)
            let activeScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }

            if let activeScene {
                do {
                    try await AppStore.showManageSubscriptions(in: activeScene)
                    return
                } catch {
                    // Fall through to the App Store subscriptions page.
                }
            }

            if let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions") {
                _ = await UIApplication.shared.open(subscriptionsURL)
            }
            #endif
        }
    }

    // MARK: - Helper: formatted price string

    var monthlyPrice: String { monthlyProduct?.displayPrice ?? "₺129,99" }
    var annualPrice: String  { annualProduct?.displayPrice ?? "₺799,99" }
    var annualMonthlyPrice: String {
        guard let product = annualProduct else { return "₺66,67" }
        return product.priceFormatStyle.format(product.price / 12)
    }
}
