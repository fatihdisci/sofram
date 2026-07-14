//
//  FreeScanCounter.swift
//  Calorisor — device-level display of the server-enforced free scan quota.
//
//  Free users have two independent UTC-day pools: one photo scan and two
//  text/voice scans. The proxy is authoritative when it returns quota headers;
//  UserDefaults is only an offline display/prediction fallback.
//
//  Manual meal entry and quick counters never consume either AI quota.
//

import Foundation
import Observation

enum FreeScanPool: String, Codable, Equatable {
    case photo
    case text
}

/// Quota headers returned by the proxy after a successful scan (or a daily
/// limit response). Keeping this separate from the counter makes the network
/// response testable without coupling the proxy client to SwiftData/UI.
struct ScanQuotaSnapshot: Equatable {
    let tier: String
    let photoRemaining: Int
    let photoLimit: Int
    let textRemaining: Int
    let textLimit: Int
}

@MainActor
@Observable
final class FreeScanCounter {

    static let shared = FreeScanCounter()

    let maxFreePhotoScans = 1
    let maxFreeTextScans = 2

    private let defaults: UserDefaults
    /// Injectable clock so tests can exercise the UTC-day rollover deterministically.
    private let now: () -> Date

    private enum Keys {
        static let photoUsed = "calorisor.freePhotoScansUsed"
        static let textUsed = "calorisor.freeTextScansUsed"
        static let subscribed = "calorisor.isSubscribed"
        static let dayStart = "calorisor.freeScanDayStart"
    }

    private(set) var usedPhotoScans: Int {
        didSet { defaults.set(usedPhotoScans, forKey: Keys.photoUsed) }
    }

    private(set) var usedTextScans: Int {
        didSet { defaults.set(usedTextScans, forKey: Keys.textUsed) }
    }

    /// Start of the UTC day that the local display counters belong to.
    private var dayStart: Date {
        didSet { defaults.set(dayStart, forKey: Keys.dayStart) }
    }

    /// StoreKit keeps this entitlement mirror current.
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
        self.usedPhotoScans = defaults.integer(forKey: Keys.photoUsed)
        self.usedTextScans = defaults.integer(forKey: Keys.textUsed)
        self.isSubscribed = defaults.bool(forKey: Keys.subscribed)
        self.dayStart = (defaults.object(forKey: Keys.dayStart) as? Date) ?? .distantPast
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func utcDayStart(for date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    private var currentDayStart: Date {
        utcDayStart(for: now())
    }

    private func rolloverIfNeeded() {
        let currentDay = currentDayStart
        guard currentDay > dayStart else { return }
        dayStart = currentDay
        usedPhotoScans = 0
        usedTextScans = 0
    }

    private var effectiveUsedPhotoScans: Int {
        currentDayStart > dayStart ? 0 : usedPhotoScans
    }

    private var effectiveUsedTextScans: Int {
        currentDayStart > dayStart ? 0 : usedTextScans
    }

    var remainingPhotoScans: Int {
        max(0, maxFreePhotoScans - effectiveUsedPhotoScans)
    }

    var remainingTextScans: Int {
        max(0, maxFreeTextScans - effectiveUsedTextScans)
    }

    func remaining(for pool: FreeScanPool) -> Int {
        switch pool {
        case .photo: return remainingPhotoScans
        case .text: return remainingTextScans
        }
    }

    func canScan(for pool: FreeScanPool) -> Bool {
        hasUnlimitedScans || remaining(for: pool) > 0
    }

    /// When the current daily quota next refills (UTC midnight).
    var nextResetDate: Date {
        utcCalendar.date(byAdding: .day, value: 1, to: currentDayStart) ?? now()
    }

    /// Record a successful AI scan. If the proxy supplied quota headers, they
    /// replace the local estimate; otherwise only the relevant local pool moves.
    func recordScan(pool: FreeScanPool, serverQuota: ScanQuotaSnapshot? = nil) {
        guard !hasUnlimitedScans else { return }
        rolloverIfNeeded()

        if let serverQuota, serverQuota.tier == "free" {
            applyServerQuota(serverQuota)
            return
        }

        switch pool {
        case .photo:
            usedPhotoScans = min(maxFreePhotoScans, usedPhotoScans + 1)
        case .text:
            usedTextScans = min(maxFreeTextScans, usedTextScans + 1)
        }
    }

    /// Synchronize the local display with server-authoritative counters. This
    /// is also called when a daily-limit error carries the remaining headers.
    func applyServerQuota(_ quota: ScanQuotaSnapshot) {
        guard quota.tier == "free" else { return }
        rolloverIfNeeded()
        usedPhotoScans = max(0, quota.photoLimit - quota.photoRemaining)
        usedTextScans = max(0, quota.textLimit - quota.textRemaining)
    }

    private var hasUnlimitedScans: Bool {
        #if DEBUG
        return isSubscribed || debugForcePro
        #else
        return isSubscribed
        #endif
    }

    #if DEBUG
    /// Test/debug helper — resets both pools to a fresh UTC day.
    func resetForTesting() {
        usedPhotoScans = 0
        usedTextScans = 0
        dayStart = .distantPast
    }
    #endif
}
