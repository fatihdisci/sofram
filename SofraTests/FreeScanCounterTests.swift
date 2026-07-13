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

    private var suiteName: String { "FreeScanCounterTests" }

    private func makeCounter() -> (FreeScanCounter, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FreeScanCounter(defaults: defaults), defaults)
    }
}
