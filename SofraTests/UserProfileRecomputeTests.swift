//
//  UserProfileRecomputeTests.swift
//  SofraTests — settings profile target recomputation coverage.
//


import XCTest
@testable import Sofra

final class UserProfileRecomputeTests: XCTestCase {
    func testWeightChangeRecomputesCaloriesAndAllMacros() {
        let profile = makeProfile()
        profile.recomputeDailyTarget()
        let previousCalories = profile.dailyCalorieTarget
        let previousProtein = profile.proteinTargetG

        profile.weightKg = 70
        profile.recomputeDailyTarget()

        XCTAssertNotEqual(profile.dailyCalorieTarget, previousCalories)
        XCTAssertNotEqual(profile.proteinTargetG, previousProtein)
        XCTAssertGreaterThan(profile.carbsTargetG, 0)
        XCTAssertGreaterThan(profile.fatTargetG, 0)
    }

    func testLegacyAgeZeroKeepsExistingTargets() {
        let profile = makeProfile(age: 0)
        profile.dailyCalorieTarget = 2_000
        profile.proteinTargetG = 100
        profile.carbsTargetG = 200
        profile.fatTargetG = 70

        profile.weightKg = 70
        profile.recomputeDailyTarget()

        XCTAssertEqual(profile.dailyCalorieTarget, 2_000)
        XCTAssertEqual(profile.proteinTargetG, 100)
        XCTAssertEqual(profile.carbsTargetG, 200)
        XCTAssertEqual(profile.fatTargetG, 70)
    }

    func testAgeAndSexChangesAffectRecomputedTarget() {
        let profile = makeProfile()
        profile.recomputeDailyTarget()
        let maleTarget = profile.dailyCalorieTarget

        profile.age = 45
        profile.biologicalSex = .female
        profile.recomputeDailyTarget()

        XCTAssertNotEqual(profile.dailyCalorieTarget, maleTarget)
    }

    private func makeProfile(age: Int = 30) -> UserProfile {
        UserProfile(
            goal: .maintain,
            heightCm: 175,
            weightKg: 90,
            activityLevel: .moderate,
            age: age,
            biologicalSex: .male
        )
    }
}
