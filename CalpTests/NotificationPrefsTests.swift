//
//  NotificationPrefsTests.swift
//  CalpTests — meal-slot windows + notification preference gating
//  (SF-EX06/07/08). The scheduling itself talks to UNUserNotificationCenter and
//  needs a device, but the pure logic (slot windows, default times, the master
//  gate) is deterministic and worth pinning.
//

import XCTest
@testable import Calp

final class NotificationPrefsTests: XCTestCase {

    // MARK: Meal-slot windows

    func testMealSlotWindowsDoNotOverlapAndCoverMealHours() {
        // No hour belongs to two slots.
        for hour in 0..<24 {
            let matching = MealSlot.allCases.filter { $0.windowHours.contains(hour) }
            XCTAssertLessThanOrEqual(matching.count, 1, "hour \(hour) is in \(matching.count) slots")
        }
        XCTAssertTrue(MealSlot.breakfast.windowHours.contains(8))
        XCTAssertTrue(MealSlot.lunch.windowHours.contains(13))
        XCTAssertTrue(MealSlot.snack.windowHours.contains(16))
        XCTAssertTrue(MealSlot.dinner.windowHours.contains(20))
    }

    func testDefaultMealTimesAreSensible() {
        XCTAssertEqual(MealSlot.breakfast.defaultHour, 9)
        XCTAssertEqual(MealSlot.lunch.defaultHour, 13)
        XCTAssertEqual(MealSlot.snack.defaultHour, 16)
        XCTAssertEqual(MealSlot.dinner.defaultHour, 20)
    }

    // MARK: Preference gating

    func testAnyEnabledRequiresMasterSwitch() {
        let keys = [
            NotificationPrefs.masterKey,
            MealSlot.breakfast.enabledKey,
            NotificationPrefs.noLogEnabledKey,
            NotificationPrefs.summaryEnabledKey,
        ]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }

        // Master off → never enabled, even if a kind is on.
        UserDefaults.standard.set(false, forKey: NotificationPrefs.masterKey)
        UserDefaults.standard.set(true, forKey: MealSlot.breakfast.enabledKey)
        XCTAssertFalse(NotificationPrefs.anyEnabled)

        // Master on but every kind off → still not enabled.
        UserDefaults.standard.set(true, forKey: NotificationPrefs.masterKey)
        UserDefaults.standard.set(false, forKey: MealSlot.breakfast.enabledKey)
        UserDefaults.standard.set(false, forKey: NotificationPrefs.noLogEnabledKey)
        UserDefaults.standard.set(false, forKey: NotificationPrefs.summaryEnabledKey)
        XCTAssertFalse(NotificationPrefs.anyEnabled)

        // Master on + one kind on → enabled.
        UserDefaults.standard.set(true, forKey: NotificationPrefs.summaryEnabledKey)
        XCTAssertTrue(NotificationPrefs.anyEnabled)
    }
}
