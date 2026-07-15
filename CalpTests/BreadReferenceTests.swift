//
//  BreadReferenceTests.swift
//  CalpTests — core bread reference data and matching coverage.
//


import XCTest
@testable import Calp

final class BreadReferenceTests: XCTestCase {
    func testCoreBreadReferencesHaveConsistentPortionNutrition() throws {
        let references = try TurkishFoodReference.load()
        let expectedNames = [
            "beyaz ekmek",
            "tam buğday ekmeği",
            "lavaş",
            "bazlama",
            "tandır/köy ekmeği",
        ]

        for name in expectedNames {
            let reference = try XCTUnwrap(references.first { $0.name == name })
            XCTAssertEqual(reference.confidenceNote, "well-established")

            let factor = reference.typicalPortion.grams / 100
            XCTAssertEqual(
                reference.nutritionPerPortion.calories,
                reference.nutritionPer100g.calories * factor,
                accuracy: reference.nutritionPer100g.calories * factor * 0.05
            )
            XCTAssertEqual(
                reference.nutritionPerPortion.proteinG,
                reference.nutritionPer100g.proteinG * factor,
                accuracy: max(reference.nutritionPer100g.proteinG * factor * 0.05, 0.05)
            )
            XCTAssertEqual(
                reference.nutritionPerPortion.carbsG,
                reference.nutritionPer100g.carbsG * factor,
                accuracy: max(reference.nutritionPer100g.carbsG * factor * 0.05, 0.05)
            )
            XCTAssertEqual(
                reference.nutritionPerPortion.fatG,
                reference.nutritionPer100g.fatG * factor,
                accuracy: max(reference.nutritionPer100g.fatG * factor * 0.05, 0.05)
            )
        }
    }

    func testEkmekNamesMatchWhiteBreadReference() throws {
        let references = try TurkishFoodReference.load()

        for name in ["ekmek", "1 dilim ekmek"] {
            let result = ReferenceReconciler.reconcile(item: makeItem(name: name), in: references)

            XCTAssertEqual(result.source, .reference)
            XCTAssertEqual(result.referenceName, "beyaz ekmek")
        }
    }

    private func makeItem(name: String) -> VisionItem {
        VisionItem(
            name: name,
            nameEn: "",
            estimatedGrams: 25,
            householdUnit: "dilim",
            householdQuantity: 1,
            calories: 999,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            confidence: 0.9,
            note: nil
        )
    }
}
