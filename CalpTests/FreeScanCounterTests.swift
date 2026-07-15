//
//  FreeScanCounterTests.swift
//  CalpTests — daily photo/text quota and server-sync coverage.
//

import XCTest
@testable import Calp

@MainActor
final class FreeScanCounterTests: XCTestCase {
    func testPhotoAndTextPoolsAreIndependent() {
        let (counter, defaults) = makeCounter()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        counter.debugForcePro = false

        counter.recordScan(pool: .photo)
        XCTAssertEqual(counter.remainingPhotoScans, 0)
        XCTAssertEqual(counter.remainingTextScans, 2)
        XCTAssertFalse(counter.canScan(for: .photo))
        XCTAssertTrue(counter.canScan(for: .text))

        counter.recordScan(pool: .text)
        counter.recordScan(pool: .text)
        XCTAssertEqual(counter.remainingTextScans, 0)
        XCTAssertFalse(counter.canScan(for: .text))
    }

    func testDebugForceProAndSubscriptionNeverConsumeCounters() {
        let (counter, defaults) = makeCounter()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        counter.debugForcePro = true
        counter.recordScan(pool: .photo)
        counter.recordScan(pool: .text)
        XCTAssertEqual(counter.remainingPhotoScans, 1)
        XCTAssertEqual(counter.remainingTextScans, 2)

        counter.debugForcePro = false
        counter.isSubscribed = true
        counter.recordScan(pool: .photo)
        XCTAssertEqual(counter.remainingPhotoScans, 1)
    }

    func testQuotaRefillsAtNextUtcDay() {
        let suite = "FreeScanCounterTests.utcRollover"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let clock = MutableClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        let counter = FreeScanCounter(defaults: defaults, now: { clock.date })
        counter.debugForcePro = false
        counter.recordScan(pool: .photo)
        counter.recordScan(pool: .text)

        XCTAssertEqual(counter.remainingPhotoScans, 0)
        XCTAssertEqual(counter.remainingTextScans, 1)

        // Cross the next UTC midnight without relying on the device timezone.
        clock.date = counter.nextResetDate.addingTimeInterval(1)
        XCTAssertEqual(counter.remainingPhotoScans, 1)
        XCTAssertEqual(counter.remainingTextScans, 2)
        XCTAssertTrue(counter.canScan(for: .photo))
    }

    func testServerQuotaReplacesLocalEstimate() {
        let (counter, defaults) = makeCounter()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        counter.debugForcePro = false
        counter.recordScan(pool: .photo)

        counter.applyServerQuota(ScanQuotaSnapshot(
            tier: "free",
            photoRemaining: 1,
            photoLimit: 1,
            textRemaining: 0,
            textLimit: 2
        ))

        XCTAssertEqual(counter.remainingPhotoScans, 1)
        XCTAssertEqual(counter.remainingTextScans, 0)
        XCTAssertTrue(counter.canScan(for: .photo))
        XCTAssertFalse(counter.canScan(for: .text))
    }

    func testProServerQuotaDoesNotChangeFreeDisplay() {
        let (counter, defaults) = makeCounter()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        counter.debugForcePro = false
        counter.recordScan(pool: .photo)

        counter.applyServerQuota(ScanQuotaSnapshot(
            tier: "pro",
            photoRemaining: 49,
            photoLimit: 50,
            textRemaining: 100,
            textLimit: 100
        ))

        XCTAssertEqual(counter.remainingPhotoScans, 0)
        XCTAssertEqual(counter.remainingTextScans, 2)
    }

    private var suiteName: String { "FreeScanCounterTests" }

    private func makeCounter() -> (FreeScanCounter, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FreeScanCounter(defaults: defaults), defaults)
    }
}

private final class MutableClock {
    var date: Date
    init(date: Date) { self.date = date }
}
