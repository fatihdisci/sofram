//
//  FreeScanCounter.swift
//  Sofra — device-level free-scan quota (no accounts, no server).
//
//  Grants a fixed number of free AI scans per rolling weekly period, then gates
//  behind the paywall until the quota refills at the start of the next calendar
//  week. This keeps the app usable without Pro (unlike a one-time lifetime cap)
//  while still steering heavy users to a subscription.
//
//  Manual entry (Hızlı Ekle counters + the one-off manual meal entry) does NOT
//  consume this quota — only successful AI recognitions do.
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

    /// Free scans granted per weekly period before the paywall.
    let maxFreeScans = 3

    private let defaults: UserDefaults
    /// Injectable clock so tests can exercise weekly rollover deterministically.
    private let now: () -> Date

    private enum Keys {
        static let used = "calorisor.freeScansUsed"
        static let subscribed = "calorisor.isSubscribed"
        static let periodStart = "calorisor.freeScanPeriodStart"
    }

    /// Scans consumed within the current weekly period.
    private(set) var usedScans: Int {
        didSet { defaults.set(usedScans, forKey: Keys.used) }
    }

    /// Start of the week that `usedScans` is counted against. Persisted so a
    /// rollover survives relaunches.
    private var periodStart: Date {
        didSet { defaults.set(periodStart, forKey: Keys.periodStart) }
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

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        self.usedScans = defaults.integer(forKey: Keys.used)
        self.isSubscribed = defaults.bool(forKey: Keys.subscribed)
        self.periodStart = (defaults.object(forKey: Keys.periodStart) as? Date) ?? .distantPast
    }

    /// Start of the calendar week containing `date` (locale first-weekday).
    private func weekStart(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start
            ?? Calendar.current.startOfDay(for: date)
    }

    /// `usedScans` as it applies right now: zero once the stored period elapsed.
    /// Read-only — the actual persisted rollover happens in `recordScan()`.
    private var effectiveUsedScans: Int {
        weekStart(for: now()) > periodStart ? 0 : usedScans
    }

    /// Free scans still available this period (0 once the cap is hit).
    var remainingFreeScans: Int { max(0, maxFreeScans - effectiveUsedScans) }

    /// The gate the scan flow checks before starting a scan.
    var canScanForFree: Bool { hasUnlimitedScans || effectiveUsedScans < maxFreeScans }

    /// When the current free-scan quota next refills (start of next week).
    var nextResetDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStart(for: now()))
            ?? now()
    }

    /// Call once after a successful scan completes.
    func recordScan() {
        guard !hasUnlimitedScans else { return }
        let currentWeek = weekStart(for: now())
        if currentWeek > periodStart {
            // New weekly period — reset the tally before counting this scan.
            periodStart = currentWeek
            usedScans = 0
        }
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
    /// Test/debug helper — resets the quota to a fresh, full period.
    func resetForTesting() {
        usedScans = 0
        periodStart = .distantPast
    }
    #endif
}
