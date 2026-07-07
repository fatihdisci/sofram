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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.usedScans = defaults.integer(forKey: Keys.used)
        #if DEBUG
        // Always pro in debug builds — no scan limits during testing.
        self.isSubscribed = true
        #else
        self.isSubscribed = defaults.bool(forKey: Keys.subscribed)
        #endif
    }

    /// Free scans still available (0 once the cap is hit).
    var remainingFreeScans: Int { max(0, maxFreeScans - usedScans) }

    /// The gate the scan flow checks before starting a scan.
    var canScanForFree: Bool { isSubscribed || usedScans < maxFreeScans }

    /// Call once after a successful scan completes.
    func recordScan() {
        guard !isSubscribed else { return } // subscribers don't consume the free cap
        usedScans += 1
    }

    #if DEBUG
    /// Test/debug helper — resets the lifetime counter.
    func resetForTesting() { usedScans = 0 }
    #endif
}
