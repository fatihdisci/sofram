import XCTest
@testable import Calp

final class HealthKitWeightTrendBuilderTests: XCTestCase {
    func testDailyLatestKeepsOnlyTheLastReadingPerDay() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14))!
        let morning = day.addingTimeInterval(8 * 60 * 60)
        let evening = day.addingTimeInterval(20 * 60 * 60)
        let nextDay = day.addingTimeInterval(86_400 + 9 * 60 * 60)

        let result = HealthKitWeightTrendBuilder.dailyLatest(
            from: [
                HealthKitWeightPoint(date: evening, kilograms: 70.4),
                HealthKitWeightPoint(date: morning, kilograms: 70.8),
                HealthKitWeightPoint(date: nextDay, kilograms: 70.1),
            ],
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.kilograms), [70.4, 70.1])
        XCTAssertEqual(result.map(\.date), [evening, nextDay])
    }

    func testDailyLatestReturnsChronologicalPoints() {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        let second = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))!

        let result = HealthKitWeightTrendBuilder.dailyLatest(
            from: [
                HealthKitWeightPoint(date: second, kilograms: 69.8),
                HealthKitWeightPoint(date: first, kilograms: 70.2),
            ],
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.date), [first, second])
    }
}
