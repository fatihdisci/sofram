import HealthKit
import XCTest
@testable import Calorisor

final class HealthKitManagerTests: XCTestCase {
    func testReadDoesNotCrashWhenHealthKitIsUnavailableOrUnauthorized() async {
        let snapshot = await HealthKitManager().readToday()

        if !HealthKitManager.isAvailable {
            XCTAssertEqual(snapshot, .empty)
        } else {
            XCTAssertGreaterThanOrEqual(snapshot.activeEnergyKcal, 0)
            XCTAssertGreaterThanOrEqual(snapshot.steps, 0)
        }
    }

    func testWriteDoesNotThrowWhenPermissionIsMissing() async {
        let result = await HealthKitManager().writeMealNutrition(
            externalID: UUID(),
            date: .now,
            calories: 450,
            protein: 25,
            carbs: 50,
            fat: 12
        )

        if !HealthKitManager.isAvailable {
            XCTAssertFalse(result)
        }
    }
}
