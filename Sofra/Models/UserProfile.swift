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
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive
}

@Model
final class UserProfile {
    var goal: Goal = Goal.maintain
    var heightCm: Double = 0
    var weightKg: Double = 0
    var activityLevel: ActivityLevel = ActivityLevel.moderate

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
        self.dailyCalorieTarget = dailyCalorieTarget
        self.proteinTargetG = proteinTargetG
        self.carbsTargetG = carbsTargetG
        self.fatTargetG = fatTargetG
        self.createdAt = createdAt
    }
}
