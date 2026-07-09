//
//  UserProfile.swift
//  Sofra — single-row local profile (no auth), created during onboarding.
//

import Foundation
import SwiftData

enum Goal: String, Codable, CaseIterable {
    case lose
    case maintain
    case gain
    case gainMuscle = "gain_muscle"

    var displayName: String {
        switch self {
        case .lose:       return "Kilo vermek"
        case .maintain:   return "Korumak"
        case .gain:       return "Kilo almak"
        case .gainMuscle: return "Kas yapmak"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive

    var displayName: String {
        switch self {
        case .sedentary:  return "Hareketsiz"
        case .light:      return "Hafif aktif"
        case .moderate:   return "Orta aktif"
        case .active:     return "Aktif"
        case .veryActive: return "Çok aktif"
        }
    }

    var description: String {
        switch self {
        case .sedentary:  return "Masa başı çalışma, az hareket"
        case .light:      return "Haftada 1-2 gün hafif egzersiz"
        case .moderate:   return "Haftada 3-5 gün egzersiz"
        case .active:     return "Haftada 6-7 gün egzersiz"
        case .veryActive: return "Yoğun antrenman / fiziksel iş"
        }
    }
}

@Model
final class UserProfile {
    var goal: Goal = Goal.maintain
    var heightCm: Double = 0
    var weightKg: Double = 0
    var activityLevel: ActivityLevel = ActivityLevel.moderate

    // Onboarding inputs that previously weren't persisted. Needed so we can
    // recompute calorie/macro targets when the user updates weight (or any
    // other input) from Ayarlar later.
    var age: Int = 0
    var biologicalSexRaw: String = BiologicalSex.male.rawValue
    var biologicalSex: BiologicalSex {
        get { BiologicalSex(rawValue: biologicalSexRaw) ?? .male }
        set { biologicalSexRaw = newValue.rawValue }
    }

    /// Targets (dailyMacroTargets broken into the three macros for storage).
    var dailyCalorieTarget: Double = 0
    var proteinTargetG: Double = 0
    var carbsTargetG: Double = 0
    var fatTargetG: Double = 0

    var createdAt: Date = Date()

    init(
        goal: Goal = .maintain,
        heightCm: Double = 0,
        weightKg: Double = 0,
        activityLevel: ActivityLevel = .moderate,
        age: Int = 0,
        biologicalSex: BiologicalSex = .male,
        dailyCalorieTarget: Double = 0,
        proteinTargetG: Double = 0,
        carbsTargetG: Double = 0,
        fatTargetG: Double = 0,
        createdAt: Date = Date()
    ) {
        self.goal = goal
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
        self.age = age
        self.biologicalSex = biologicalSex
        self.dailyCalorieTarget = dailyCalorieTarget
        self.proteinTargetG = proteinTargetG
        self.carbsTargetG = carbsTargetG
        self.fatTargetG = fatTargetG
        self.createdAt = createdAt
    }
}
