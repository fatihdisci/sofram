//
//  DaySummaryBuilderTests.swift
//  CalpTests — scan and quick-add macro aggregation coverage.
//

import XCTest
@testable import Calp

final class DaySummaryBuilderTests: XCTestCase {
    func testTodayTotalsIncludeScanAndQuickAddMacros() throws {
        let scan = ScanEntry(
            timestamp: Date(),
            items: [
                LoggedItem(
                    name: "öğün",
                    calories: 300,
                    protein: 20,
                    carbs: 30,
                    fat: 10
                )
            ]
        )
        let quickItem = QuickAddItem(
            name: "Ayran",
            caloriesPerUnit: 60,
            proteinPerUnit: 3,
            carbsPerUnit: 5,
            fatPerUnit: 3
        )
        let count = QuickAddCount(
            itemID: quickItem.id,
            date: Calendar.current.startOfDay(for: Date()),
            count: 2
        )

        let today = try XCTUnwrap(
            DaySummaryBuilder.lastSevenDays(
                scans: [scan],
                items: [quickItem],
                counts: [count]
            ).first
        )

        XCTAssertEqual(today.calories, 420, accuracy: 0.001)
        XCTAssertEqual(today.protein, 26, accuracy: 0.001)
        XCTAssertEqual(today.carbs, 40, accuracy: 0.001)
        XCTAssertEqual(today.fat, 16, accuracy: 0.001)
        XCTAssertEqual(today.quickAddTally, 2)
    }
}
