//
//  VisionResponse.swift
//  Sofra — typed response from the AI proxy.
//
//  This is the AUTHORITATIVE Swift mirror of the JSON schema in vision-prompt-schema.md.
//  Do not change the shape without changing that file — the backend proxy adapts
//  whichever model it uses to this exact contract, so the client stays model-agnostic.
//
//  Response shape:
//  {
//    "items": [ { name, name_en, estimated_grams, household_unit, household_quantity,
//                 calories, protein_g, carbs_g, fat_g, confidence, note? }, ... ],
//    "no_food_detected": Bool
//  }
//

import Foundation

struct VisionResponse: Codable, Equatable {
    let items: [VisionItem]
    let noFoodDetected: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case noFoodDetected = "no_food_detected"
    }
}

struct VisionItem: Codable, Equatable {
    let name: String
    let nameEn: String
    let estimatedGrams: Double
    let householdUnit: String        // mapped to PortionUnit (unknown → .gram)
    let householdQuantity: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let confidence: Double
    let note: String?

    enum CodingKeys: String, CodingKey {
        case name
        case nameEn = "name_en"
        case estimatedGrams = "estimated_grams"
        case householdUnit = "household_unit"
        case householdQuantity = "household_quantity"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case confidence
        case note
    }
}

// MARK: - Mapping into the persistence layer

extension VisionItem {
    /// The household unit as a strongly-typed `PortionUnit` (falls back to `.gram`).
    var portionUnit: PortionUnit { PortionUnit(apiValue: householdUnit) }

    /// Builds a `LoggedItem` (unattached — caller inserts it into a ScanEntry).
    func makeLoggedItem() -> LoggedItem {
        LoggedItem(
            name: name,
            nameEn: nameEn,
            portionUnit: portionUnit,
            quantity: householdQuantity,
            estimatedGrams: estimatedGrams,
            calories: calories,
            protein: proteinG,
            carbs: carbsG,
            fat: fatG,
            confidence: confidence,
            note: note
        )
    }
}

extension VisionResponse {
    /// Convenience: build a persisted `ScanEntry` from this response.
    /// `rawJSON` should be the exact bytes returned by the proxy (kept for debugging).
    func makeScanEntry(source: ScanSource, rawJSON: String) -> ScanEntry {
        let entry = ScanEntry(source: source, rawAIResponse: rawJSON)
        let logged = items.map { $0.makeLoggedItem() }
        logged.forEach { $0.scanEntry = entry }
        entry.items = logged
        return entry
    }
}
