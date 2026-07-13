//
//  FreeScanCounterTests.swift
//  SofraTests — successful-request consumption and debug bypass coverage.
//


import XCTest
@testable import Sofra

@MainActor
final class FreeScanCounterTests: XCTestCase {
    func testThreeSuccessfulScansCloseReleaseGateWithoutSaving() {
        let (counter, defaults) = makeCounter()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        counter.debugForcePro = false

        XCTAssertTrue(counter.canScanForFree)
        for _ in 0..<3 {
            counter.recordScan()
        }

        XCTAssertEqual(counter.usedScans, 3)
        XCTAssertEqual(counter.remainingFreeScans, 0)
        XCTAssertFalse(counter.canScanForFree)
    }

    func testDebugForceProNeverConsumesCounter() {
        let (counter, defaults) = makeCounter()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        counter.debugForcePro = true

        counter.recordScan()

        XCTAssertTrue(counter.canScanForFree)
        XCTAssertEqual(counter.usedScans, 0)
    }

    func testSubscriptionNeverConsumesCounter() {
        let (counter, defaults) = makeCounter()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        counter.debugForcePro = false
        counter.isSubscribed = true

        counter.recordScan()

        XCTAssertTrue(counter.canScanForFree)
        XCTAssertEqual(counter.usedScans, 0)
    }

    func testWeeklyQuotaRefillsInTheNextWeek() {
        let suite = "FreeScanCounterTests.weekly"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // Fixed starting instant so weekly rollover is deterministic.
        let clock = MutableClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        let counter = FreeScanCounter(defaults: defaults, now: { clock.date })
        counter.debugForcePro = false

        // Exhaust this week's quota.
        for _ in 0..<3 { counter.recordScan() }
        XCTAssertEqual(counter.remainingFreeScans, 0)
        XCTAssertFalse(counter.canScanForFree)

        // Jump into the next week — the quota refills.
        clock.date = clock.date.addingTimeInterval(8 * 24 * 3600)
        XCTAssertTrue(counter.canScanForFree)
        XCTAssertEqual(counter.remainingFreeScans, 3)

        // A scan in the new week starts a fresh tally.
        counter.recordScan()
        XCTAssertEqual(counter.remainingFreeScans, 2)
    }

    private var suiteName: String { "FreeScanCounterTests" }

    private func makeCounter() -> (FreeScanCounter, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FreeScanCounter(defaults: defaults), defaults)
    }
}

/// A mutable clock the counter reads through its injectable `now` closure.
private final class MutableClock {
    var date: Date
    init(date: Date) { self.date = date }
}
