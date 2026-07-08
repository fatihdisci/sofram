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
        case .goal:     "Hedefin ne?"
        case .height:   "Boyun kaç cm?"
        case .weight:   "Kilon kaç kg?"
        case .activity: "Günlük aktivite seviyen?"
        case .age:      "Yaşın kaç?"
        case .sex:      "Biyolojik cinsiyetin?"
        case .result:   "Günlük Hedefin"
        case .paywall:  "Sofra'ya Başla"
        }
    }

    var subtitle: String {
        switch self {
        case .goal:     "Sana özel bir plan oluşturacağız"
        case .height:   "Boyunu santimetre cinsinden gir"
        case .weight:   "Kilonu kilogram cinsinden gir"
        case .activity: "Ortalama bir gününü düşün"
        case .age:      "Yaşını tam sayı olarak gir"
        case .sex:      "Kalori hesaplaması için gerekli"
        case .result:   ""
        case .paywall:  ""
        }
    }
}

// MARK: - Sex enum

enum BiologicalSex: String, Codable, CaseIterable {
    case male   = "Erkek"
    case female = "Kadın"
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
        static let completed = "sofra.onboardingCompleted"
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

    // MARK: - Calculator

    /// Mifflin-St Jeor BMR.
    var bmr: Double {
        let w = weightKg
        let h = heightCm
        let a = Double(age)
        let base = 10 * w + 6.25 * h - 5 * a
        switch biologicalSex {
        case .male:   return base + 5
        case .female: return base - 161
        }
    }

    /// Activity multiplier.
    var activityMultiplier: Double {
        switch activityLevel {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }

    /// Total Daily Energy Expenditure = BMR × activity.
    var tdee: Double { bmr * activityMultiplier }

    /// Daily calorie target after goal adjustment. Rounded to a whole calorie —
    /// nothing downstream (ring, Ayarlar fields) needs fractional precision, and
    /// leaving it unrounded produced long decimal tails that overflowed the
    /// Ayarlar text fields (e.g. "2507.142857...").
    var dailyCalorieTarget: Double {
        let t = tdee
        let raw: Double
        switch goal {
        case .lose:       raw = max(1200, t - 500)
        case .maintain:   raw = t
        case .gain:       raw = t + 300
        case .gainMuscle: raw = t + 200
        }
        return raw.rounded()
    }

    /// Macro targets (grams), rounded for the same reason as the calorie target.
    var proteinTargetG: Double { ((dailyCalorieTarget * 0.25) / 4).rounded() }
    var carbsTargetG: Double   { ((dailyCalorieTarget * 0.45) / 4).rounded() }
    var fatTargetG: Double     { ((dailyCalorieTarget * 0.30) / 9).rounded() }

    /// Build a UserProfile from the answers.
    func makeUserProfile() -> UserProfile {
        UserProfile(
            goal: goal,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel,
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
        UserDefaults.standard.set(dailyCalorieTarget, forKey: "sofra.dailyCalorieTarget")
        UserDefaults.standard.set(proteinTargetG, forKey: "sofra.proteinTarget")
        UserDefaults.standard.set(carbsTargetG, forKey: "sofra.carbsTarget")
        UserDefaults.standard.set(fatTargetG, forKey: "sofra.fatTarget")

        completeOnboarding()
    }
}
