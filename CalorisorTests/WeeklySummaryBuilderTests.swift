import XCTest
@testable import Calorisor

final class WeeklySummaryBuilderTests: XCTestCase {
    func testBuildsFreeMetricsAndPreviousWeekChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))
        )

        let scans = [
            scan(calendar, year: 2026, month: 7, day: 14, hour: 10, calories: 1_800, protein: 90),
            scan(calendar, year: 2026, month: 7, day: 13, hour: 23, calories: 2_200, protein: 70),
            scan(calendar, year: 2026, month: 7, day: 12, hour: 12, calories: 1_600, protein: 80),
            scan(calendar, year: 2026, month: 7, day: 11, hour: 12, calories: 2_000, protein: 100),
            scan(calendar, year: 2026, month: 7, day: 7, hour: 12, calories: 1_000, protein: 40),
            scan(calendar, year: 2026, month: 7, day: 6, hour: 12, calories: 1_200, protein: 50),
        ]

        let summary = WeeklySummaryBuilder.build(
            scans: scans,
            items: [],
            counts: [],
            dailyCalorieTarget: 2_000,
            now: now,
            activeEnergyKcal: 3_500,
            weightChangeKg: -0.8,
            calendar: calendar
        )

        XCTAssertEqual(summary.loggedDayCount, 4)
        XCTAssertEqual(summary.averageCalories, 1_900, accuracy: 0.001)
        XCTAssertEqual(summary.averageProtein, 85, accuracy: 0.001)
        XCTAssertEqual(summary.targetMetDayCount, 3)
        XCTAssertEqual(try XCTUnwrap(summary.highestCalorieDay).calories, 2_200, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.lowestCalorieDay).calories, 1_600, accuracy: 0.001)
        XCTAssertEqual(summary.nightMealCount, 1)
        XCTAssertEqual(try XCTUnwrap(summary.previousAverageCalories), 1_100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.calorieChangeFromPreviousWeek), 800, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.calorieChangePercentFromPreviousWeek), 800 / 1_100 * 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.activeEnergyKcal), 3_500, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.weightChangeKg), -0.8, accuracy: 0.001)
    }

    func testQuickAddOnlyDayCountsAsRegisteredAndContributesToAverage() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))
        )
        let item = QuickAddItem(name: "Ayran", caloriesPerUnit: 60, proteinPerUnit: 3)
        let countDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))
        )

        let summary = WeeklySummaryBuilder.build(
            scans: [],
            items: [item],
            counts: [QuickAddCount(itemID: item.id, date: countDate, count: 2)],
            dailyCalorieTarget: 2_000,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.loggedDayCount, 1)
        XCTAssertEqual(summary.averageCalories, 120, accuracy: 0.001)
        XCTAssertEqual(summary.averageProtein, 6, accuracy: 0.001)
        XCTAssertEqual(summary.targetMetDayCount, 1)
    }

    func testEmptyWeekHasNoExtremesOrPreviousWeekDelta() {
        let summary = WeeklySummaryBuilder.build(
            scans: [],
            items: [],
            counts: [],
            dailyCalorieTarget: 2_000
        )

        XCTAssertEqual(summary.loggedDayCount, 0)
        XCTAssertEqual(summary.averageCalories, 0)
        XCTAssertNil(summary.highestCalorieDay)
        XCTAssertNil(summary.lowestCalorieDay)
        XCTAssertNil(summary.previousAverageCalories)
        XCTAssertNil(summary.calorieChangeFromPreviousWeek)
        XCTAssertEqual(summary.nightMealCount, 0)
    }

    private func scan(
        _ calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calories: Double,
        protein: Double
    ) -> ScanEntry {
        ScanEntry(
            timestamp: calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour)
            )!,
            items: [LoggedItem(name: "öğün", calories: calories, protein: protein)]
        )
    }
}
