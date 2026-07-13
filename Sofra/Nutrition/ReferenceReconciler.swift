//
//  ReferenceReconciler.swift
//  Sofra — deterministic reference/AI nutrition reconciliation.
//
//  The AI stays responsible for recognition + portion sizing. For simple,
//  well-established foods that exist in the bundled Türkiye reference DB, we
//  replace only calorie/macro values with deterministic per-100g math.
//  Approximate or unmatched foods keep the AI's original values.
//

import Foundation

enum ReferenceReconciler {
    enum Source: String {
        case reference
        case ai
    }

    struct ReconciledNutrition: Equatable {
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var source: Source
        var confidenceNote: String?
        var referenceName: String?
    }

    static func reconcile(item: VisionItem, in references: [FoodReference]) -> ReconciledNutrition {
        guard let reference = match(item: item, in: references) else {
            return aiNutrition(from: item, matched: nil)
        }

        guard reference.isWellEstablished else {
            return aiNutrition(from: item, matched: reference)
        }

        let factor = item.estimatedGrams / 100
        let per100g = reference.nutritionPer100g

        return ReconciledNutrition(
            calories: per100g.calories * factor,
            protein: per100g.proteinG * factor,
            carbs: per100g.carbsG * factor,
            fat: per100g.fatG * factor,
            source: .reference,
            confidenceNote: reference.confidenceNote,
            referenceName: reference.name
        )
    }
}

private extension ReferenceReconciler {
    struct ReferenceKey {
        let key: String
        let food: FoodReference
    }

    static func aiNutrition(from item: VisionItem, matched reference: FoodReference?) -> ReconciledNutrition {
        ReconciledNutrition(
            calories: item.calories,
            protein: item.proteinG,
            carbs: item.carbsG,
            fat: item.fatG,
            source: .ai,
            confidenceNote: reference?.confidenceNote,
            referenceName: reference?.name
        )
    }

    static func match(item: VisionItem, in references: [FoodReference]) -> FoodReference? {
        let candidates = candidateKeys(for: item)
        guard !candidates.isEmpty, !references.isEmpty else { return nil }

        let referenceKeys = references.flatMap(keys(for:))

        var exactIndex: [String: FoodReference] = [:]
        exactIndex.reserveCapacity(referenceKeys.count)
        for referenceKey in referenceKeys where exactIndex[referenceKey.key] == nil {
            exactIndex[referenceKey.key] = referenceKey.food
        }

        for candidate in candidates {
            if let exact = exactIndex[candidate] {
                return exact
            }
        }

        let aliases = uniqueKeys(candidates.flatMap(String.Turkish.aliases(for:)))
        for alias in aliases {
            if let exact = exactIndex[alias] {
                return exact
            }
        }

        for candidate in candidates {
            let candidateTokens = tokenSet(for: candidate)
            if let tokenSetMatch = referenceKeys.first(where: {
                !candidateTokens.isEmpty && candidateTokens == tokenSet(for: $0.key)
            }) {
                return tokenSetMatch.food
            }
        }

        return nil
    }

    static func candidateKeys(for item: VisionItem) -> [String] {
        uniqueKeys([
            String.Turkish.foodKey(item.name),
            String.Turkish.foodKey(item.nameEn),
        ])
    }

    static func keys(for food: FoodReference) -> [ReferenceKey] {
        uniqueKeys([
            String.Turkish.foodKey(food.name),
            String.Turkish.foodKey(food.nameEn),
        ]).map { ReferenceKey(key: $0, food: food) }
    }

    static func uniqueKeys(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for key in keys where !key.isEmpty && seen.insert(key).inserted {
            out.append(key)
        }
        return out
    }

    static func tokenSet(for key: String) -> Set<String> {
        Set(key.split(separator: " ").map(String.init))
    }
}
