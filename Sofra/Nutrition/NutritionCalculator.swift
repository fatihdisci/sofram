//
//  NutritionCalculator.swift
//  Sofra — pure calorie/macro/BMI engine.
//
//  This is the single source of truth for all numeric computation behind the
//  user-facing calorie target. OnboardingModel and (later) Ayarlar delegate to
//  here so the math is testable in isolation and any policy change (e.g. the
//  sex-aware floors added in Phase A4) only needs to land in one place.
//
//  Pure functions: no SwiftUI/SwiftData dependencies, no @MainActor.
//

import Foundation

// MARK: - Result types

/// Detailed output of `dailyCalorieTargetResult`. Carries enough metadata for
/// the UI to render a "taban devreye girdi" hint when the raw target would
/// otherwise fall below a clinical minimum.
struct DailyTargetResult: Equatable {
    /// The user-facing target — already rounded to whole kcal and floored.
    let target: Double
    /// TDEE passed in (unrounded, useful for showing the user the "neutral" line).
    let tdee: Double
    /// TDEE + goal delta, BEFORE the floor. Useful for the UI to explain what
    /// the user "would have" gotten without the safety floor.
    let rawTarget: Double
    /// True iff the sex-aware floor actually clipped `rawTarget` upward.
    let floorApplied: Bool
    /// The floor that applied (or would have applied if `floorApplied` is false).
    let minCalories: Double
}

// MARK: - Calculator

enum NutritionCalculator {

    // MARK: Core formulas

    /// Mifflin-St Jeor BMR. Returns kcal/day.
    static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: BiologicalSex) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male:   return base + 5
        case .female: return base - 161
        }
    }

    /// TDEE = BMR × activity multiplier (NutritionConstants single source).
    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * NutritionConstants.activityMultiplier(activity)
    }

    /// Daily calorie target — rounded to whole kcal. Convenience wrapper over
    /// `dailyCalorieTargetResult` for callers that only need the number.
    ///
    /// Floor policy (Phase A4): `raw = tdee + goalDelta(goal)` is clipped UP to
    /// `NutritionConstants.minCalories(for: sex)` (female 1200 / male 1500).
    /// Applied to **every** goal — losing, maintaining, gaining, muscle —
    /// because the floor represents the clinical minimum daily intake, not
    /// a weight-loss-specific limit.
    static func dailyCalorieTarget(tdee: Double, goal: Goal, sex: BiologicalSex) -> Double {
        dailyCalorieTargetResult(tdee: tdee, goal: goal, sex: sex).target
    }

    /// Daily calorie target with floor-applied metadata.
    ///
    /// Floor policy: `raw = tdee + goalDelta(goal)` is clipped UP to
    /// `NutritionConstants.minCalories(for: sex)` (female 1200 / male 1500).
    /// Applied to **every** goal — losing, maintaining, gaining, muscle —
    /// because the floor represents the clinical minimum daily intake, not
    /// a weight-loss-specific limit.
    static func dailyCalorieTargetResult(tdee: Double, goal: Goal, sex: BiologicalSex) -> DailyTargetResult {
        let min = NutritionConstants.minCalories(for: sex)
        let raw = tdee + NutritionConstants.goalDelta(goal)
        let floorApplied = raw < min
        let target = max(min, raw).rounded()
        return DailyTargetResult(
            target: target,
            tdee: tdee,
            rawTarget: raw,
            floorApplied: floorApplied,
            minCalories: min
        )
    }

    /// Daily macro grams from a (rounded) calorie target. Returns
    /// `(protein, carbs, fat)` — each already rounded to whole grams.
    ///
    /// Phase A3 uses a fixed balanced split (P25 · K45 · Y30) to match the
    /// pre-refactor `OnboardingModel` exactly. Phase A5 replaces this with
    /// `NutritionConstants.macroSplit(goal)` so e.g. `.gainMuscle` gets
    /// higher protein.
    static func macros(calories: Double, goal: Goal) -> (protein: Double, carbs: Double, fat: Double) {
        _ = goal // accepted for forward-compat with Phase A5
        let p = (calories * 0.25 / 4).rounded()
        let c = (calories * 0.45 / 4).rounded()
        let f = (calories * 0.30 / 9).rounded()
        return (p, c, f)
    }

    // MARK: BMI / healthy weight (infrastructure; UI to come)

    /// BMI in kg/m². Returns 0 if height is non-positive (defensive — caller
    /// is expected to validate inputs upstream).
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let h = heightCm / 100.0
        guard h > 0 else { return 0 }
        return weightKg / (h * h)
    }

    /// Healthy weight range for a given height, derived from WHO 1995 BMI 18.5–24.9.
    /// Returns kilograms. Returns `(0, 0)` for non-positive heights.
    static func healthyWeightRange(heightCm: Double) -> (minKg: Double, maxKg: Double) {
        let h = heightCm / 100.0
        let h2 = h * h
        guard h > 0 else { return (0, 0) }
        let minKg = NutritionConstants.bmiHealthyMin * h2
        let maxKg = NutritionConstants.bmiHealthyMax * h2
        return (minKg, maxKg)
    }

    /// Clamp a target weight so it never drops below the healthy BMI floor.
    /// Returns the effective weight and whether the input was clipped upward.
    /// Intended for the future "target weight" Ayarlar input.
    static func safeTargetWeight(goalWeightKg: Double, heightCm: Double) -> (weight: Double, wasClamped: Bool) {
        let range = healthyWeightRange(heightCm: heightCm)
        if range.minKg == 0 { return (goalWeightKg, false) }
        if goalWeightKg < range.minKg {
            return (range.minKg, true)
        }
        return (goalWeightKg, false)
    }

    // MARK: Weekly rate (infrastructure)

    /// Convert a daily kcal delta into a weekly weight change in kg.
    /// Negative delta → loss. Uses Wishnofsky's kcal/kg-of-fat rule.
    static func weeklyKgFromKcalDelta(_ dailyKcalDelta: Double) -> Double {
        (dailyKcalDelta * 7) / NutritionConstants.kcalPerKgFat
    }

    /// Clamp a weekly rate to the CDC safety band for the goal direction.
    /// `maintain` is a no-op (no rate). Returns `(clampedKg, wasClamped)`.
    static func clampWeeklyRate(_ kg: Double, goal: Goal) -> (kg: Double, wasClamped: Bool) {
        let lo: Double
        let hi: Double
        switch goal {
        case .lose:
            lo = NutritionConstants.weeklyLossMinKg
            hi = NutritionConstants.weeklyLossMaxKg
        case .gain, .gainMuscle:
            lo = NutritionConstants.weeklyGainMinKg
            hi = NutritionConstants.weeklyGainMaxKg
        case .maintain:
            return (kg, false)
        }
        if kg < lo { return (lo, true) }
        if kg > hi { return (hi, true) }
        return (kg, false)
    }
}