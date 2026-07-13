//
//  CalorieRingViewTests.swift
//  SofraTests — ring display-state and overshoot math coverage.
//

import XCTest
@testable import Sofra

final class CalorieRingViewTests: XCTestCase {
    func testDisplayModesCycleBackToRemaining() {
        XCTAssertEqual(RingDisplayMode.remaining.next, .consumed)
        XCTAssertEqual(RingDisplayMode.consumed.next, .target)
        XCTAssertEqual(RingDisplayMode.target.next, .remaining)
    }

    func testOvershootIsTwentyPercentAtTwentyFourHundredOfTwoThousand() {
        XCTAssertEqual(
            CalorieRingMetrics.overshootProgress(consumed: 2400, target: 2000),
            0.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(CalorieRingMetrics.overshootProgress(consumed: 1900, target: 2000), 0)
        XCTAssertEqual(CalorieRingMetrics.overshootProgress(consumed: 5000, target: 2000), 1)
    }
}
