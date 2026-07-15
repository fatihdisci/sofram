//
//  VisionResponseValidator.swift
//  Calp — semantic validation for schema-valid AI nutrition responses.
//


import Foundation

extension VisionResponse {
    func sanitized() -> VisionResponse {
        let sanitizedItems = items.compactMap { item -> VisionItem? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            let protein = item.proteinG.clamped(to: 0...1_000)
            let carbs = item.carbsG.clamped(to: 0...1_000)
            let fat = item.fatG.clamped(to: 0...1_000)
            let macroCalories = 4 * protein + 4 * carbs + 9 * fat
            let clampedCalories = item.calories.clamped(to: 0...5_000)
            let deviation = abs(clampedCalories - macroCalories) / max(clampedCalories, 1)
            let calories = (deviation > 0.40 ? macroCalories : clampedCalories)
                .clamped(to: 0...5_000)
            let quantity = item.householdQuantity <= 0
                ? 1
                : item.householdQuantity.clamped(to: 0.25...50)

            return VisionItem(
                name: name,
                nameEn: item.nameEn,
                estimatedGrams: item.estimatedGrams.clamped(to: 1...3_000),
                householdUnit: item.householdUnit,
                householdQuantity: quantity,
                calories: calories,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                confidence: item.confidence.clamped(to: 0...1),
                note: item.note
            )
        }

        return VisionResponse(
            items: sanitizedItems,
            noFoodDetected: sanitizedItems.isEmpty ? true : noFoodDetected
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
