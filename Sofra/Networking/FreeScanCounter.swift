//
//  FreeScanCounter.swift
//  Sofra — device-level lifetime free-scan counter (no accounts, no server).
//
//  Enforces a lifetime cap of 3 free scans before paywall gating. The paywall UI
//  and StoreKit 2 subscription wiring are later phases; `isSubscribed` is a stub
//  flag here that a later phase will drive from `Transaction.currentEntitlements`.
//
//  Backed by UserDefaults (device-local). Note: this is best-effort abuse
//  prevention on the client; the proxy also enforces IP/device rate limiting
//  server-side (out of scope here).
//

import Foundation
import Observation

@MainActor
@Observable
final class FreeScanCounter {

    static let shared = FreeScanCounter()

    /// Lifetime free scans allowed before the paywall.
    let maxFreeScans = 3

    private let defaults: UserDefaults
    private enum Keys {
        static let used = "sofra.freeScansUsed"
        static let subscribed = "sofra.isSubscribed"
    }

    /// Lifetime count of scans consumed.
    private(set) var usedScans: Int {
        didSet { defaults.set(usedScans, forKey: Keys.used) }
    }

    /// STUB — wired to StoreKit 2 in a later phase. Persisted so the app can boot
    /// with a known state before entitlements are re-checked.
    var isSubscribed: Bool {
        didSet { defaults.set(isSubscribed, forKey: Keys.subscribed) }
    }

    #if DEBUG
    /// Keeps development flows unlocked without pretending StoreKit granted an
    /// entitlement. Tests can disable this to exercise release counter logic.
    var debugForcePro = true
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.usedScans = defaults.integer(forKey: Keys.used)
        self.isSubscribed = defaults.bool(forKey: Keys.subscribed)
    }

    /// Free scans still available (0 once the cap is hit).
    var remainingFreeScans: Int { max(0, maxFreeScans - usedScans) }

    /// The gate the scan flow checks before starting a scan.
    var canScanForFree: Bool { hasUnlimitedScans || usedScans < maxFreeScans }

    /// Call once after a successful scan completes.
    func recordScan() {
        guard !hasUnlimitedScans else { return }
        usedScans += 1
    }

    private var hasUnlimitedScans: Bool {
        #if DEBUG
        return isSubscribed || debugForcePro
        #else
        return isSubscribed
        #endif
    }

    #if DEBUG
    /// Test/debug helper — resets the lifetime counter.
    func resetForTesting() { usedScans = 0 }
    #endif
}
