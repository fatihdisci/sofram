//
//  PortionRecalculationTests.swift
//  CalpTests — household-unit nutrition recalculation coverage.
//


import XCTest
@testable import Calp

final class PortionRecalculationTests: XCTestCase {
    func testChangingFromLadleToTeaGlassRecalculatesFromGramDensity() {
        let editable = EditableVisionItem(from: makeSoupItem())

        editable.householdUnit = .cayBardagi

        XCTAssertEqual(editable.estimatedGrams, 200, accuracy: 0.001)
        XCTAssertEqual(editable.calories, 166.67, accuracy: 0.01)
        XCTAssertEqual(editable.proteinG, 8.33, accuracy: 0.01)
    }

    func testAdetKeepsLegacyQuantityScalingWhenNoReferencePortionExists() {
        let editable = EditableVisionItem(from: makeSoupItem())

        editable.householdUnit = .adet
        XCTAssertEqual(editable.estimatedGrams, 240, accuracy: 0.001)
        XCTAssertEqual(editable.calories, 200, accuracy: 0.001)

        editable.householdQuantity = 3
        XCTAssertEqual(editable.estimatedGrams, 360, accuracy: 0.001)
        XCTAssertEqual(editable.calories, 300, accuracy: 0.001)
    }

    func testReferencePortionTakesPriorityOverDefaultUnitGrams() {
        let reference = FoodReference(
            name: "test çorbası",
            nameEn: "test soup",
            category: "corba",
            typicalPortion: RefPortion(
                grams: 240,
                householdUnit: "kepçe",
                householdQuantity: 2,
                description: nil
            ),
            alternatePortions: [
                RefPortion(
                    grams: 180,
                    householdUnit: "çay bardağı",
                    householdQuantity: 2,
                    description: nil
                ),
            ],
            nutritionPer100g: RefNutrition(calories: 83.333, proteinG: 4.166, carbsG: 8, fatG: 2),
            nutritionPerPortion: RefNutrition(calories: 200, proteinG: 10, carbsG: 19.2, fatG: 4.8),
            confidenceNote: "well-established",
            sourceContext: "test fixture"
        )
        let editable = EditableVisionItem(from: makeSoupItem(name: "test çorbası"), references: [reference])

        editable.householdUnit = .cayBardagi

        XCTAssertEqual(editable.estimatedGrams, 180, accuracy: 0.001)
        XCTAssertEqual(editable.calories, 150, accuracy: 0.01)
    }

    private func makeSoupItem(name: String = "bilinmeyen çorba") -> VisionItem {
        VisionItem(
            name: name,
            nameEn: "",
            estimatedGrams: 240,
            householdUnit: "kepçe",
            householdQuantity: 2,
            calories: 200,
            proteinG: 10,
            carbsG: 20,
            fatG: 5,
            confidence: 0.9,
            note: nil
        )
    }
}
