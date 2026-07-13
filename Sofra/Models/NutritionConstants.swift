//
//  NutritionConstants.swift
//  Sofra — evidence-based constants for the calorie/macro engine.
//
//  Source: deep-research report (WHO 1995 BMI; FAO/WHO/UNU 2004 BMR/TDEE;
//  CDC weight-change rates; TÜBER 2022 macro ranges; WHO sugar/salt limits).
//  These are population-level defaults, NOT medical advice. Do not tune numbers
//  here without updating that report + the disclaimer copy.
//
//  This file is pure data. Behaviour (validation, clamping, the hard floors)
//  lives in NutritionCalculator — see the implementation spec.
//

import Foundation

enum LegalLinks {
    // TODO(fatih): gerçek URL
    static let privacyPolicy = URL(string: "https://calorisor.app/privacy")!
    // TODO(fatih): gerçek URL
    static let termsOfUse = URL(string: "https://calorisor.app/terms")!
}

enum NutritionConstants {

    // MARK: - Household portion defaults

    /// Typical grams represented by one household unit when the food reference
    /// database does not provide a dish-specific portion. Counted pieces and
    /// pots intentionally have no global weight because their size varies too
    /// much by food.
    static func defaultGrams(for unit: PortionUnit) -> Double? {
        switch unit {
        case .kepce:       return 120
        case .yemekKasigi: return 15
        case .suBardagi:   return 200
        case .cayBardagi:  return 100
        case .dilim:       return 25
        case .avuc:        return 30
        case .kase:        return 250
        case .tencere:     return nil
        case .adet:        return nil
        case .gram:        return 1
        }
    }

    // MARK: - BMI (WHO 1995)

    /// Healthy BMI band. Used for weight-range and target-weight sanity checks.
    static let bmiHealthyMin: Double = 18.5
    static let bmiHealthyMax: Double = 24.9
    static let bmiOverweight: Double = 25.0
    static let bmiObese: Double = 30.0

    // MARK: - Activity multipliers (FAO/WHO/UNU 2004)
    // NOTE: these already exist in OnboardingModel.activityMultiplier and MUST
    // stay in sync. The calculator should read from here as the single source.

    static func activityMultiplier(_ level: ActivityLevel) -> Double {
        switch level {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }

    // MARK: - Goal adjustment (kcal applied to TDEE)
    // Matches the current OnboardingModel behaviour so targets don't shift on refactor.

    static func goalDelta(_ goal: Goal) -> Double {
        switch goal {
        case .lose:       return -500   // ≈ 0.45 kg/week (CDC safe range)
        case .maintain:   return 0
        case .gain:       return +300   // controlled surplus
        case .gainMuscle: return +200
        }
    }

    // MARK: - Weekly weight-change safety (CDC)

    static let weeklyLossMinKg: Double = 0.25
    static let weeklyLossMaxKg: Double = 1.0
    static let weeklyGainMinKg: Double = 0.25
    static let weeklyGainMaxKg: Double = 0.5
    /// Wishnofsky rule: energy equivalent of 1 kg of body fat.
    static let kcalPerKgFat: Double = 7700

    // MARK: - Hard floors (clinical minimum daily intake) — NEVER produce below these
    // Report specifies sex-specific floors. Current code only floors .lose at 1200
    // for both sexes; this must become sex-aware.

    static let minCaloriesFemale: Double = 1200
    static let minCaloriesMale: Double = 1500

    static func minCalories(for sex: BiologicalSex) -> Double {
        switch sex {
        case .female: return minCaloriesFemale
        case .male:   return minCaloriesMale
        }
    }

    // MARK: - Macro split by goal (fraction of daily calories)
    // Current code hardcodes 25/45/30 for every goal. Report supports
    // goal-specific splits; gainMuscle in particular needs more protein.
    // protein & carbs are ÷4 kcal/g, fat ÷9 kcal/g.

    struct MacroSplit { let protein: Double; let carbs: Double; let fat: Double }

    static func macroSplit(_ goal: Goal) -> MacroSplit {
        switch goal {
        case .lose:       return MacroSplit(protein: 0.30, carbs: 0.40, fat: 0.30)
        case .maintain:   return MacroSplit(protein: 0.25, carbs: 0.45, fat: 0.30)
        case .gain:       return MacroSplit(protein: 0.25, carbs: 0.50, fat: 0.25)
        case .gainMuscle: return MacroSplit(protein: 0.30, carbs: 0.45, fat: 0.25)
        }
    }

    // TÜBER 2022 acceptable ranges (validation guards, not the split itself):
    // carbs 45–60%, fat 20–35%, protein 10–20% of energy. Protein g/kg:
    // 0.8 (sedentary) … 1.2–2.0 (active). Keep splits inside these bands.

    // MARK: - Daily reference limits (WHO / TÜBER) — for tips & guards

    static let fiberMinG: Double = 25            // WHO
    static let addedSugarMaxEnergyFraction = 0.10 // WHO 2015
    static let saltMaxG: Double = 5              // WHO 2012
    static let waterLitersMin: Double = 2.0
    static let waterLitersMax: Double = 2.5

    // MARK: - Disclaimer (show alongside every computed target)

    static let medicalDisclaimerTR =
        "Bu değerler genel rehberlik içindir, tıbbi tavsiye değildir. " +
        "Hamilelik, kronik hastalık veya yeme bozukluğu gibi özel durumlarda " +
        "bir hekime veya diyetisyene danışın."
}
