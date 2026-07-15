//
//  LoggedItem.swift
//  Calp — one recognized/logged food item belonging to a ScanEntry.
//

import Foundation
import SwiftData

@Model
final class LoggedItem {
    var name: String = ""            // Turkish dish name, e.g. "mercimek çorbası"
    var nameEn: String = ""          // English equivalent (internal logging/debug)

    var portionUnit: PortionUnit = PortionUnit.gram
    var quantity: Double = 0         // household-unit quantity (e.g. 2 kepçe)
    var estimatedGrams: Double = 0   // raw gram estimate behind the household unit

    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    var confidence: Double = 0       // 0…1 from the model
    var note: String?                // e.g. shared-pot ("tencere") note

    /// Phase B4: where the calorie/macro numbers came from. Optional for
    /// CloudKit compatibility. Set by `VisionItem.makeLoggedItem(references:)`:
    ///   • "reference" — a well-established row matched; numbers are deterministic.
    ///   • "ai"        — AI numbers were kept (no match, or match was approximate).
    /// nil means "pre-B4" — legacy scan rows written before this column existed.
    var valueSource: String? = nil

    /// Parent scan (inverse of ScanEntry.items). Optional for CloudKit.
    var scanEntry: ScanEntry?

    init(
        name: String = "",
        nameEn: String = "",
        portionUnit: PortionUnit = .gram,
        quantity: Double = 0,
        estimatedGrams: Double = 0,
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        confidence: Double = 0,
        note: String? = nil,
        valueSource: String? = nil
    ) {
        self.name = name
        self.nameEn = nameEn
        self.portionUnit = portionUnit
        self.quantity = quantity
        self.estimatedGrams = estimatedGrams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.confidence = confidence
        self.note = note
        self.valueSource = valueSource
    }
}
