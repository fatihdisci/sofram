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

    func testMealMarkersUseCumulativeCaloriePositions() {
        let markers = CalorieRingMetrics.markerProgresses(
            segments: [400, 600, 250],
            target: 2000
        )

        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(markers[0], 0.20, accuracy: 0.0001)
        XCTAssertEqual(markers[1], 0.50, accuracy: 0.0001)
        XCTAssertEqual(markers[2], 0.625, accuracy: 0.0001)
    }

    func testMealMarkersIgnoreInvalidValuesAndFinalCap() {
        let markers = CalorieRingMetrics.markerProgresses(
            segments: [-100, .infinity, 1000, 1000, 300],
            target: 2000
        )

        XCTAssertEqual(markers, [0.5])
    }

    func testDenseMealMarkersAreEvenlyLimited() {
        let markers = CalorieRingMetrics.markerProgresses(
            segments: Array(repeating: 100, count: 12),
            target: 2000,
            maximumCount: 5
        )

        XCTAssertEqual(markers.count, 5)
        XCTAssertEqual(markers.first, 0.05)
        XCTAssertEqual(markers.last, 0.60)
    }
}
