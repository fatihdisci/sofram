//
//  HistoryDaySummaryBuilderTests.swift
//  CalorisorTests — month grouping and day aggregation coverage.
//

import XCTest
@testable import Calorisor

final class HistoryDaySummaryBuilderTests: XCTestCase {
    func testThirtyFiveDaysAreGroupedByMonthNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let newest = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 12))
        )

        let scans = (0..<35).map { offset -> ScanEntry in
            let date = calendar.date(byAdding: .day, value: -offset, to: newest)!
            return ScanEntry(
                timestamp: date,
                items: [LoggedItem(name: "öğün", calories: 100)]
            )
        }

        let sections = HistoryDaySummaryBuilder.monthSections(
            scans: scans,
            items: [],
            counts: [],
            calendar: calendar
        )

        XCTAssertEqual(sections.flatMap(\.days).count, 35)
        XCTAssertEqual(sections.first?.month, calendar.date(from: DateComponents(year: 2026, month: 7)))
        XCTAssertEqual(sections.first?.days.first?.date, calendar.startOfDay(for: newest))
        XCTAssertTrue(sections.flatMap(\.days).allSatisfy { $0.mealCount == 1 })
        XCTAssertTrue(sections.flatMap(\.days).allSatisfy { $0.calories == 100 })
    }

    func testQuickAddsCreateAHistoryDayAndContributeCalories() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))
        )
        let item = QuickAddItem(name: "Ekmek", caloriesPerUnit: 80)
        let count = QuickAddCount(itemID: item.id, date: date, count: 3)

        let sections = HistoryDaySummaryBuilder.monthSections(
            scans: [],
            items: [item],
            counts: [count],
            calendar: calendar
        )
        let day = try XCTUnwrap(sections.first?.days.first)

        XCTAssertEqual(day.mealCount, 0)
        XCTAssertEqual(day.quickAddTally, 3)
        XCTAssertEqual(day.calories, 240, accuracy: 0.001)
    }
}
