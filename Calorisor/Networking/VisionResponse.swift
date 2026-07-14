//
//  VisionResponse.swift
//  Calorisor — typed response from the AI proxy.
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
    ///
    /// **Phase B4:** this is the legacy zero-arg form kept for any test code
    /// that builds `LoggedItem`s without a reference set. It produces
    /// `valueSource == "ai"` because no reconciliation happens.
    func makeLoggedItem() -> LoggedItem {
        makeLoggedItem(references: [])
    }

    /// Reference-aware variant. Runs the item through `ReferenceReconciler`:
    /// if a well-established DB row matches, the reference's per-100g values
    /// override the AI's calories/protein/carbs/fat; otherwise the AI's
    /// numbers are kept.
    ///
    /// Pass `TurkishFoodReference.foods()` here for the production path.
    /// Passing `[]` is the safe "AI fallback everywhere" path used by the
    /// legacy `makeLoggedItem()` overload.
    ///
    /// Also writes `valueSource` ("reference" | "ai") onto the LoggedItem.
    func makeLoggedItem(references: [FoodReference]) -> LoggedItem {
        let reconciled = ReferenceReconciler.reconcile(item: self, in: references)
        return LoggedItem(
            name: name,
            nameEn: nameEn,
            portionUnit: portionUnit,
            quantity: householdQuantity,
            estimatedGrams: estimatedGrams,
            calories: reconciled.calories,
            protein: reconciled.protein,
            carbs: reconciled.carbs,
            fat: reconciled.fat,
            confidence: confidence,
            note: note,
            valueSource: reconciled.source.rawValue
        )
    }
}

extension VisionResponse {
    /// Convenience: build a persisted `ScanEntry` from this response.
    /// `rawJSON` should be the exact bytes returned by the proxy (kept for debugging).
    ///
    /// **Phase B4:** every item goes through the reference-aware
    /// `makeLoggedItem(references:)` path. The reference index is loaded
    /// once here from `TurkishFoodReference.index()`; if the bundle JSON is
    /// missing or the decode fails, `index()` returns `[:]` and the
    /// reconciler falls back to AI values for every item (graceful
    /// degradation — no throw, no crash).
    func makeScanEntry(source: ScanSource, rawJSON: String) -> ScanEntry {
        let entry = ScanEntry(source: source, rawAIResponse: rawJSON)
        let references = TurkishFoodReference.foods()
        let logged = items.map { $0.makeLoggedItem(references: references) }
        logged.forEach { $0.scanEntry = entry }
        entry.items = logged
        return entry
    }
}
