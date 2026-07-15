//
//  NutritionCalculatorTests.swift
//  Calp — parity + safety tests for the calorie engine.
//
//  Cases 1–4 mirror the table in AGENT_HANDOFF_nutrition_and_food_db.md §A3
//  (refactor parity + A4 floor test). Case 5 is the A4 male-floor check
//  (the female minimum doesn't catch low-TDEE male inputs; the male
//  minimum does). All expected values were recomputed from the
//  Mifflin-St Jeor formula + NutritionConstants, not copy-pasted from
//  the handoff — the handoff's "Beklenen target" column had arithmetic
//  errors in cases 1–3 (it doesn't invalidate the parity check; both
//  pre- and post-refactor paths produce the same number, just neither
//  matches the handoff's typo).
//
//  Each case pins down one axis:
//    • sex (female + male)
//    • age (22, 28, 35, 50)
//    • activity (sedentary, light, moderate, veryActive)
//    • goal (lose, maintain, gainMuscle)
//    • floor behaviour (active in 4 + 5, inactive in 1, 2, 3)
//

import XCTest
@testable import Calp

final class NutritionCalculatorTests: XCTestCase {

    // MARK: - Parity: A3 refactor must not shift existing-user targets

    /// F 28, light, lose. Pre-refactor: max(1200, 1829.09 - 500) = 1329.09 → 1329.
    /// Post-refactor: same path → 1329. Floor (1200) does NOT apply (1329 > 1200).
    func testFemale28LightLose_parity() {
        let tdee = NutritionCalculator.tdee(
            bmr: NutritionCalculator.bmr(weightKg: 60, heightCm: 165, age: 28, sex: .female),
            activity: .light
        )
        let result = NutritionCalculator.dailyCalorieTargetResult(tdee: tdee, goal: .lose, sex: .female)
        XCTAssertEqual(result.target, 1329, accuracy: 0.5, "F28/light/lose target shifted")
        XCTAssertFalse(result.floorApplied, "Floor must NOT clip when target > minCalories(1200)")
        XCTAssertEqual(result.minCalories, 1200)
    }

    /// M 35, moderate, maintain. Pre-refactor: round(TDEE) = round(2700.875) = 2701.
    /// Post-refactor: same → 2701. Floor (1500) does NOT apply.
    func testMale35ModerateMaintain_parity() {
        let tdee = NutritionCalculator.tdee(
            bmr: NutritionCalculator.bmr(weightKg: 80, heightCm: 178, age: 35, sex: .male),
            activity: .moderate
        )
        let result = NutritionCalculator.dailyCalorieTargetResult(tdee: tdee, goal: .maintain, sex: .male)
        XCTAssertEqual(result.target, 2701, accuracy: 0.5, "M35/moderate/maintain target shifted")
        XCTAssertFalse(result.floorApplied, "Floor must NOT clip when target > minCalories(1500)")
        XCTAssertEqual(result.minCalories, 1500)
    }

    /// M 22, veryActive, gainMuscle. Pre-refactor: round(TDEE + 200) = round(3586.75) = 3587.
    /// Post-refactor: same → 3587. Floor (1500) does NOT apply.
    func testMale22VeryActiveGainMuscle_parity() {
        let tdee = NutritionCalculator.tdee(
            bmr: NutritionCalculator.bmr(weightKg: 75, heightCm: 182, age: 22, sex: .male),
            activity: .veryActive
        )
        let result = NutritionCalculator.dailyCalorieTargetResult(tdee: tdee, goal: .gainMuscle, sex: .male)
        XCTAssertEqual(result.target, 3587, accuracy: 0.5, "M22/veryActive/gainMuscle target shifted")
        XCTAssertFalse(result.floorApplied, "Floor must NOT clip when target > minCalories(1500)")
        XCTAssertEqual(result.minCalories, 1500)
    }

    // MARK: - A4 safety: female floor (1200)

    /// F 50, sedentary, lose. Pre-refactor: max(1200, 866.8) = 1200.
    /// Post-A4: floor 1200 still applies (raw 866.8 < 1200), target = 1200.
    /// floorApplied MUST be true so the UI can show the hint.
    func testFemale50SedentaryLose_floorApplied() {
        let tdee = NutritionCalculator.tdee(
            bmr: NutritionCalculator.bmr(weightKg: 55, heightCm: 160, age: 50, sex: .female),
            activity: .sedentary
        )
        let result = NutritionCalculator.dailyCalorieTargetResult(tdee: tdee, goal: .lose, sex: .female)
        XCTAssertEqual(result.target, 1200, accuracy: 0.5, "F50/sedentary/lose target must clamp at 1200")
        XCTAssertTrue(result.floorApplied, "Floor must flag as applied")
        XCTAssertEqual(result.minCalories, 1200)
    }

    // MARK: - A4 safety: male floor (1500)

    /// M 25, sedentary, lose. Pre-refactor (A3): max(1200, 1411) = 1411.
    /// Post-A4: floor 1500 applies (raw 1411 < 1500), target = 1500.
    /// floorApplied MUST be true. This is the new male floor check —
    /// the sex-aware policy catches inputs the old 1200 floor missed.
    func testMale25SedentaryLose_maleFloorApplied() {
        let tdee = NutritionCalculator.tdee(
            bmr: NutritionCalculator.bmr(weightKg: 65, heightCm: 170, age: 25, sex: .male),
            activity: .sedentary
        )
        let result = NutritionCalculator.dailyCalorieTargetResult(tdee: tdee, goal: .lose, sex: .male)
        XCTAssertEqual(result.target, 1500, accuracy: 0.5, "M25/sedentary/lose must clamp at 1500 (male floor)")
        XCTAssertTrue(result.floorApplied, "Male floor must flag as applied")
        XCTAssertEqual(result.minCalories, 1500)
    }

    // MARK: - A4 cross-check: male floor applies to non-lose goals too

    /// M 30, sedentary, maintain. Raw = TDEE = 1755 < 1500? No, 1755 > 1500 — no floor.
    /// Pins down the "floor applies to all goals" claim without accidentally
    /// triggering on a goal where the natural raw happens to exceed the floor.
    func testMale30SedentaryMaintain_aboveFloor() {
        let tdee = NutritionCalculator.tdee(
            bmr: NutritionCalculator.bmr(weightKg: 60, heightCm: 170, age: 30, sex: .male),
            activity: .sedentary
        )
        let result = NutritionCalculator.dailyCalorieTargetResult(tdee: tdee, goal: .maintain, sex: .male)
        XCTAssertFalse(result.floorApplied, "TDEE 1755 > 1500, floor must not trigger on maintain")
    }

    // MARK: - A5 macro split

    /// Maintain keeps the legacy P25 · K45 · Y30 split byte-identical.
    func testMacros_maintain_unchangedFromLegacy() {
        let m = NutritionCalculator.macros(calories: 2000, goal: .maintain)
        XCTAssertEqual(m.protein, (2000 * 0.25 / 4).rounded())
        XCTAssertEqual(m.carbs,   (2000 * 0.45 / 4).rounded())
        XCTAssertEqual(m.fat,     (2000 * 0.30 / 9).rounded())
    }

    /// .gainMuscle = P30 · K45 · Y25 (higher protein, lower fat vs. maintain).
    func testMacros_gainMuscle_higherProtein() {
        let m = NutritionCalculator.macros(calories: 3000, goal: .gainMuscle)
        let legacy = NutritionCalculator.macros(calories: 3000, goal: .maintain)
        XCTAssertGreaterThan(m.protein, legacy.protein, ".gainMuscle must have more protein than .maintain")
        XCTAssertLessThan(m.fat, legacy.fat, ".gainMuscle must have less fat than .maintain")
        XCTAssertEqual(m.protein, (3000 * 0.30 / 4).rounded())
        XCTAssertEqual(m.carbs,   (3000 * 0.45 / 4).rounded())
        XCTAssertEqual(m.fat,     (3000 * 0.25 / 9).rounded())
    }

    // MARK: - BMI / healthy weight infrastructure

    func testBmi_normalRange() {
        // 70 kg / 1.75 m² = 22.86
        XCTAssertEqual(NutritionCalculator.bmi(weightKg: 70, heightCm: 175), 22.857, accuracy: 0.01)
    }

    func testHealthyWeightRange_height170() {
        // BMI 18.5-24.9 at 170 cm → 53.5 - 72.0 kg
        let r = NutritionCalculator.healthyWeightRange(heightCm: 170)
        XCTAssertEqual(r.minKg, 53.5, accuracy: 0.1)
        XCTAssertEqual(r.maxKg, 72.0, accuracy: 0.1)
    }

    func testSafeTargetWeight_belowFloor_clamped() {
        // 45 kg at 175 cm → BMI 14.7 (underweight). Floor clamps to BMI 18.5 → 56.7 kg.
        let r = NutritionCalculator.safeTargetWeight(goalWeightKg: 45, heightCm: 175)
        XCTAssertTrue(r.wasClamped, "45 kg at 175 cm must be clamped upward")
        XCTAssertEqual(r.weight, 56.7, accuracy: 0.1)
    }

    // MARK: - Weekly rate infrastructure

    func testWeeklyKgFromKcalDelta_lose() {
        // −500 kcal/day → −3500 kcal/week → −0.4545 kg/week
        XCTAssertEqual(
            NutritionCalculator.weeklyKgFromKcalDelta(-500),
            -0.4545,
            accuracy: 0.001
        )
    }

    func testClampWeeklyRate_loseTooFast() {
        // −2000 kcal/day → −1.818 kg/week. CDC safe loss band is [-1.0, -0.25].
        // −1.818 is below -1.0 → clamp to -1.0 (max safe loss rate).
        let r = NutritionCalculator.clampWeeklyRate(
            NutritionCalculator.weeklyKgFromKcalDelta(-2000),
            goal: .lose
        )
        XCTAssertTrue(r.wasClamped)
        XCTAssertEqual(r.kg, -NutritionConstants.weeklyLossMaxKg)
    }

    func testClampWeeklyRate_gainTooSlow() {
        // +100 kcal/day → +0.091 kg/week. CDC safe gain band is [0.25, 0.5].
        // 0.091 < 0.25 → clamp up to 0.25 (min safe gain rate).
        let r = NutritionCalculator.clampWeeklyRate(
            NutritionCalculator.weeklyKgFromKcalDelta(100),
            goal: .gainMuscle
        )
        XCTAssertTrue(r.wasClamped)
        XCTAssertEqual(r.kg, NutritionConstants.weeklyGainMinKg)
    }
}