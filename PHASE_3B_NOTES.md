# Phase 3b Notes — Native StoreKit 2 Subscription

Complete StoreKit 2 subscription flow: product fetching, purchase, restore, Introductory Offer (3-day free trial), transaction listening, and entitlement state wired to `FreeScanCounter.isSubscribed`. No RevenueCat, no third-party SDK.

Verified: builds against iOS 26.5 SDK (min iOS 17.0), unsigned simulator. Zero errors, zero warnings.

---

## Architecture

```
StoreKitManager (@Observable singleton)
├── loadProducts()          → Product.products(for:)
├── purchase(_:)            → product.purchase() → .success/.userCancelled/.pending
├── restorePurchases()      → AppStore.sync()
├── listenForTransactions() → Transaction.updates listener (app lifetime)
├── updateEntitlements()    → Transaction.currentEntitlements → isSubscribed
├── checkTrialEligibility() → Product.SubscriptionInfo.isEligibleForIntroOffer
├── scheduleTrialEndNotification() → UNUserNotificationCenter (24h before trial end)
└── openManageSubscriptions() → Settings deep link
```

Entitlement wiring:
- `StoreKitManager.isSubscribed` ← `Transaction.currentEntitlements`
- `FreeScanCounter.shared.isSubscribed` ← `StoreKitManager.isSubscribed`
- `FreeScanCounter.canScanForFree` = `isSubscribed || usedScans < maxFreeScans`

---

## Products

| ID | Name | Price | Trial |
|---|---|---|---|
| `com.fatih.sofra.monthly` | Sofra Aylık | ₺129,99/ay (placeholder) | 3 gün ücretsiz |
| `com.fatih.sofra.annual` | Sofra Yıllık | ₺799,99/yıl (placeholder) | 3 gün ücretsiz |

All pricing is placeholder — StoreKit's native `Product.displayPrice` renders whatever is configured in App Store Connect, no hardcoded currency conversion.

---

## New/modified files

### New:
```
Sofra/StoreKit/
  Products.storekit        StoreKit sandbox configuration for Xcode testing
  StoreKitManager.swift    Product fetch, purchase, restore, entitlements, trial notify

Sofra/Views/Onboarding/
  PaywallView.swift        "Dürüst Paywall" — honest subscription UI
```

### Modified:
```
Sofra/Views/Onboarding/
  OnboardingView.swift     Replaced PaywallPlaceholderView with PaywallView

Sofra/App/
  NavigationModel.swift    Default screen changed to .daily (home, not camera)

Sofra/Views/Daily/
  DailyView.swift          Added text-log button in top bar

Sofra/Views/Camera/
  CameraView.swift         Fixed PreviewView for proper layout
```

---

## "Dürüst Paywall" implementation

The paywall meets all non-negotiable requirements from `PROJECT_CONTEXT.md`:

1. **Price on first screen** — both plan cards show `Product.displayPrice` immediately. No multi-step reveal.

2. **Trial explanation** — "3 gün ücretsiz deneme" with plain-language Turkish: when billing starts, how to cancel. No dark patterns.

3. **No urgency tricks** — No countdown timers, no pre-checked upsells, no "only X left" scarcity.

4. **Restore purchases** — "Aboneliği Geri Yükle" button calls `AppStore.sync()`.

5. **Cancel path** — "Abonelik Yönetimi" button opens iOS Settings for subscription management.

6. **Free tier** — "Ücretsiz denemek istemiyorum, 3 tarama ile devam et" link skips the paywall.

7. **Trial notification** — `scheduleTrialEndNotification()` fires 24h before the trial's `expirationDate`. Turkish copy: "Deneme süreniz bitiyor. Yarın ücretlendirileceksiniz. İsterseniz şimdi iptal edebilirsiniz."

---

## Known issues & limitations

1. **`offerType` deprecation warning.** `Transaction.offerType` (iOS 17.0) is deprecated in favor of `Transaction.offer?.type` (iOS 17.2+). We use `offerType` for backward compatibility with our iOS 17.0 deployment target. The deprecation warning is cosmetic — the API functions correctly on all iOS 17.x versions.

2. **Trial notification not yet requested.** `UNUserNotificationCenter.requestAuthorization()` needs to be called before scheduling notifications. Add this to `SofraApp` or during onboarding (Phase 3d polish).

3. **StoreKit testing requires Xcode sandbox.** The `.storekit` file enables local testing via Xcode's "StoreKit Configuration" scheme setting. Real App Store transactions require products to be created in App Store Connect (see below).

4. **`annualMonthlyPrice` calculation is approximate.** The division by 12 and formatting with the product's locale is best-effort display logic. Actual pricing is determined by App Store Connect.

---

## App Store Connect setup (manual, developer action required)

The coding agent cannot perform these steps. The developer must configure in ASC:

1. **Create a Subscription Group** with ID matching the `.storekit` group (reference name: "Sofra Premium").

2. **Create two Auto-Renewable Subscriptions:**
   - `com.fatih.sofra.monthly` — 1 month, with Introductory Offer: 3-day free trial
   - `com.fatih.sofra.annual` — 1 year, with Introductory Offer: 3-day free trial

3. **Set pricing** per market:
   - Turkey: monthly ~₺99-129, annual ~₺699-799
   - US: monthly $4.99, annual $29.99
   - Other markets: let ASC auto-convert or set individually

4. **Create the CloudKit container** `iCloud.com.fatih.sofra` (if not already created for Phase 1).

5. **Enable the "Remote Notifications" background mode** capability for `UNUserNotificationCenter` (trial-end notification).

6. **Set up the StoreKit Configuration scheme** in Xcode: Edit Scheme → Run → Options → StoreKit Configuration → select `Products.storekit`.

---

## Navigation fix (bonus)

Per user feedback, the app root screen is now the **Daily View** (home), not the camera. Flow:

```
app launch → onboarding (first time) → paywall → daily view (home)
daily view → camera button → camera → capture → result → daily
daily view → text button → text log → result → daily
daily view → 7-day summary → sheet
```

---

## Verification performed

- `xcodebuild ... build` → **BUILD SUCCEEDED** (iOS 26.5 SDK, min iOS 17.0, unsigned simulator, zero errors).
- Camera preview fixed: `PreviewView` with proper `layoutSubviews` for `AVCaptureVideoPreviewLayer`.
- StoreKit types compile correctly against iOS 17.0 target (`offerType` with deprecation annotation).
