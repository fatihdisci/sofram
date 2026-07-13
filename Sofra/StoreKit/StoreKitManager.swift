//
//  StoreKitManager.swift
//  Sofra — native StoreKit 2 subscription management.
//
//  No RevenueCat, no third-party SDK. Direct Product/Transaction/Transaction.updates
//  API usage, following the pattern shipped in the developer's "Arvia" app.
//
//  Responsibilities:
//   • Fetch products (monthly/annual with 3-day intro trials)
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

enum SofraProductID {
    static let monthly = "com.fatih.sofra.monthly"
    static let annual  = "com.fatih.sofra.annual"
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

    /// Whether the user is eligible for the 3-day intro trial.
    private(set) var isEligibleForTrial = true

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
            let products = try await Product.products(for: SofraProductID.all)
            for product in products {
                switch product.id {
                case SofraProductID.monthly: monthlyProduct = product
                case SofraProductID.annual:  annualProduct  = product
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
        // Check if eligible for intro offer on either product.
        if let monthly = monthlyProduct,
           let info = monthly.subscription,
           await info.isEligibleForIntroOffer {
            isEligibleForTrial = true
            return
        }
        if let annual = annualProduct,
           let info = annual.subscription,
           await info.isEligibleForIntroOffer {
            isEligibleForTrial = true
            return
        }
        isEligibleForTrial = false
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
            identifier: "sofra.trialEnd.\(transaction.id)",
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
            .removePendingNotificationRequests(withIdentifiers: ["sofra.trialEnd.\(transactionID)"])
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
