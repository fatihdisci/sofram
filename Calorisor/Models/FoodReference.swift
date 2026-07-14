//
//  FoodReference.swift
//  Calorisor — typed mirror of the turkish_food_reference.json bundle resource.
//
//  Source: deep-research Türkiye food reference DB, normalized by handoff §B2
//  (household_unit strings matched 1:1 with PortionUnit.rawValue).
//
//  Decoding only — matching & reconciliation live in ReferenceReconciler.
//

import Foundation

// MARK: - Top-level food entry

/// One row in `turkish_food_reference.json#foods[]`.
struct FoodReference: Codable, Identifiable, Equatable, Hashable {
    /// `name` is the canonical Turkish display name and is what the reconciler
    /// matches against the AI's `VisionItem.name` after Turkish diacritic fold.
    var id: String { name }
    let name: String
    let nameEn: String
    let category: String
    let typicalPortion: RefPortion
    let alternatePortions: [RefPortion]
    let nutritionPer100g: RefNutrition
    let nutritionPerPortion: RefNutrition
    let confidenceNote: String
    let sourceContext: String

    enum CodingKeys: String, CodingKey {
        case name
        case nameEn = "name_en"
        case category
        case typicalPortion = "typical_portion"
        case alternatePortions = "alternate_portions"
        case nutritionPer100g = "nutrition_per_100g"
        case nutritionPerPortion = "nutrition_per_portion"
        case confidenceNote = "confidence_note"
        case sourceContext = "source_context"
    }

    /// Source-of-truth gate: well-established items have their per-100g values
    /// override the AI's calorie/macro estimates; approximate items keep the
    /// AI's numbers and merely surface `confidenceNote` for the UI badge.
    var isWellEstablished: Bool { confidenceNote == "well-established" }
}

// MARK: - Nested portion

struct RefPortion: Codable, Equatable, Hashable {
    let grams: Double
    let householdUnit: String
    let householdQuantity: Double
    let description: String?

    enum CodingKeys: String, CodingKey {
        case grams
        case householdUnit = "household_unit"
        case householdQuantity = "household_quantity"
        case description
    }
}

// MARK: - Nested nutrition

struct RefNutrition: Codable, Equatable, Hashable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

// MARK: - Payload wrapper (top-level JSON has a "foods" array)

/// Internal — the JSON root is `{ "foods": [...] }`.
struct FoodReferencePayload: Codable {
    let foods: [FoodReference]
}