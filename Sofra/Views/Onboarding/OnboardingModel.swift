//
//  OnboardingModel.swift
//  Sofra — onboarding flow state + Mifflin-St Jeor calorie calculator.
//
//  Formula: Mifflin-St Jeor BMR (1919, validated across diverse populations)
//  chosen because it is the most widely cited standard for resting metabolic rate
//  and does not require body-fat % (which we don't collect).
//
//  BMR:
//    Male:   10 × weight(kg) + 6.25 × height(cm) − 5 × age + 5
//    Female: 10 × weight(kg) + 6.25 × height(cm) − 5 × age − 161
//
//  TDEE = BMR × activity multiplier (standard WHO/FAO factors):
//    sedentary=1.2, light=1.375, moderate=1.55, active=1.725, veryActive=1.9
//
//  Goal adjustment (applied to TDEE):
//    lose:      −500 kcal
//    maintain:     ±0
//    gain:       +300 kcal
//    gainMuscle: +200 kcal
//
//  Macro split (daily calorie target → grams):
//    Protein: 25% (÷4), Carbs: 45% (÷4), Fat: 30% (÷9)
//    This is a balanced Mediterranean/Turkish-diet split — not medical advice,
//    a sensible default that leaves room for personal adjustment later.
//

import Foundation
import SwiftUI
import SwiftData
import Observation

// MARK: - Onboarding step

enum OnboardingStep: Int, CaseIterable {
    case goal
    case height
    case weight
    case activity
    case age
    case sex
    case result
    case paywall

    var title: String {
        switch self {
        case .goal:     return String(localized: "Hedefin ne?")
        case .height:   return String(localized: "Boyun kaç cm?")
        case .weight:   return String(localized: "Kilon kaç kg?")
        case .activity: return String(localized: "Günlük aktivite seviyen?")
        case .age:      return String(localized: "Yaşın kaç?")
        case .sex:      return String(localized: "Biyolojik cinsiyetin?")
        case .result:   return String(localized: "Günlük Hedefin")
        case .paywall:  return String(localized: "Calorisor'a Başla")
        }
    }

    var subtitle: String {
        switch self {
        case .goal:     return String(localized: "Sana özel bir plan oluşturacağız")
        case .height:   return String(localized: "Boyunu santimetre cinsinden gir")
        case .weight:   return String(localized: "Kilonu kilogram cinsinden gir")
        case .activity: return String(localized: "Ortalama bir gününü düşün")
        case .age:      return String(localized: "Yaşını tam sayı olarak gir")
        case .sex:      return String(localized: "Kalori hesaplaması için gerekli")
        case .result:   return ""
        case .paywall:  return ""
        }
    }
}

// MARK: - Sex enum

enum BiologicalSex: String, Codable, CaseIterable {
    case male   = "Erkek"
    case female = "Kadın"

    var displayName: String {
        switch self {
        case .male:   return String(localized: "Erkek")
        case .female: return String(localized: "Kadın")
        }
    }
}

// MARK: - Onboarding model

@MainActor
@Observable
final class OnboardingModel {

    // MARK: Answers

    var goal: Goal = .maintain
    var heightCm: Double = 170
    var weightKg: Double = 70
    var activityLevel: ActivityLevel = .moderate
    var age: Int = 30
    var biologicalSex: BiologicalSex = .male

    // MARK: Flow state

    var currentStep: OnboardingStep = .goal
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.completed)
        }
    }

    /// Whether the onboarding should be shown (first launch).
    var shouldShowOnboarding: Bool { !hasCompletedOnboarding }

    // Formatted input strings for text fields
    var heightText: String = ""
    var weightText: String = ""
    var ageText: String = ""

    private enum Keys {
        static let completed = "calorisor.onboardingCompleted"
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.completed)
    }

    // MARK: - Navigation

    func goToNext() {
        let steps = OnboardingStep.allCases
        guard let idx = steps.firstIndex(of: currentStep),
              idx + 1 < steps.count else { return }
        currentStep = steps[idx + 1]
    }

    func goToPrevious() {
        let steps = OnboardingStep.allCases
        guard let idx = steps.firstIndex(of: currentStep),
              idx - 1 >= 0 else { return }
        currentStep = steps[idx - 1]
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    // MARK: - Calculator (delegates to NutritionCalculator — Phase A3)

    /// Mifflin-St Jeor BMR. See `NutritionCalculator.bmr` for the formula.
    var bmr: Double {
        NutritionCalculator.bmr(
            weightKg: weightKg,
            heightCm: heightCm,
            age: age,
            sex: biologicalSex
        )
    }

    /// Activity multiplier (NutritionConstants single source).
    var activityMultiplier: Double {
        NutritionConstants.activityMultiplier(activityLevel)
    }

    /// Total Daily Energy Expenditure = BMR × activity.
    var tdee: Double {
        NutritionCalculator.tdee(bmr: bmr, activity: activityLevel)
    }

    /// Daily calorie target after goal adjustment. Rounded to a whole calorie —
    /// nothing downstream (ring, Ayarlar fields) needs fractional precision, and
    /// leaving it unrounded produced long decimal tails that overflowed the
    /// Ayarlar text fields (e.g. "2507.142857...").
    ///
    /// Floor policy: only `.lose` floors, and at 1200 for both sexes — matches
    /// the pre-refactor behaviour exactly (Phase A3 parity). Phase A4 introduces
    /// the sex-aware floor; the UI calls `dailyTargetResult.floorApplied` to
    /// show a "taban devreye girdi" hint.
    var dailyCalorieTarget: Double {
        NutritionCalculator.dailyCalorieTarget(
            tdee: tdee,
            goal: goal,
            sex: biologicalSex
        )
    }

    /// Same target as `dailyCalorieTarget` plus the floor-applied flag — UI
    /// uses this on the onboarding result screen to render the "klinik alt
    /// sınır" hint. Phase A4.
    var dailyTargetResult: DailyTargetResult {
        NutritionCalculator.dailyCalorieTargetResult(
            tdee: tdee,
            goal: goal,
            sex: biologicalSex
        )
    }

    /// Macro targets (grams), rounded for the same reason as the calorie target.
    var proteinTargetG: Double { NutritionCalculator.macros(calories: dailyCalorieTarget, goal: goal).protein }
    var carbsTargetG: Double   { NutritionCalculator.macros(calories: dailyCalorieTarget, goal: goal).carbs }
    var fatTargetG: Double     { NutritionCalculator.macros(calories: dailyCalorieTarget, goal: goal).fat }

    /// Build a UserProfile from the answers.
    func makeUserProfile() -> UserProfile {
        UserProfile(
            goal: goal,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel,
            age: age,
            biologicalSex: biologicalSex,
            dailyCalorieTarget: dailyCalorieTarget,
            proteinTargetG: proteinTargetG,
            carbsTargetG: carbsTargetG,
            fatTargetG: fatTargetG
        )
    }

    // MARK: - Persist

    func saveProfile(to context: ModelContext) {
        let profile = makeUserProfile()
        context.insert(profile)
        try? context.save()

        // Also store the calorie + macro targets that DailyView and Ayarlar read.
        UserDefaults.standard.set(dailyCalorieTarget, forKey: "calorisor.dailyCalorieTarget")
        UserDefaults.standard.set(proteinTargetG, forKey: "calorisor.proteinTarget")
        UserDefaults.standard.set(carbsTargetG, forKey: "calorisor.carbsTarget")
        UserDefaults.standard.set(fatTargetG, forKey: "calorisor.fatTarget")

        completeOnboarding()
    }
}
