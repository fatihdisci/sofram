//
//  ReferenceReconcilerTests.swift
//  CalorisorTests — focused matching coverage for the reference reconciler.
//

import XCTest
@testable import Calorisor

final class ReferenceReconcilerTests: XCTestCase {

    func testKirmiziMercimekSynonymMatchesMercimekCorbasi() {
        let item = VisionItem(
            name: "kırmızı mercimek çorbası",
            nameEn: "red lentil soup",
            estimatedGrams: 175,
            householdUnit: "kepçe",
            householdQuantity: 1,
            calories: 999,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            confidence: 0.9,
            note: nil
        )

        let reconciled = ReferenceReconciler.reconcile(item: item, in: [Self.mercimekCorbasi])

        XCTAssertEqual(reconciled.source, .reference)
        XCTAssertEqual(reconciled.referenceName, "mercimek çorbası")
        XCTAssertEqual(reconciled.calories, 110.25, accuracy: 0.001)
    }

    func testFetaSynonymMatchesBeyazPeynir() {
        let item = VisionItem(
            name: "feta peyniri",
            nameEn: "feta cheese",
            estimatedGrams: 50,
            householdUnit: "dilim",
            householdQuantity: 1,
            calories: 999,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            confidence: 0.9,
            note: nil
        )

        let reconciled = ReferenceReconciler.reconcile(item: item, in: [Self.beyazPeynir])

        XCTAssertEqual(reconciled.source, .reference)
        XCTAssertEqual(reconciled.referenceName, "beyaz peynir")
        XCTAssertEqual(reconciled.calories, 130, accuracy: 0.001)
    }

    private static let mercimekCorbasi = FoodReference(
        name: "mercimek çorbası",
        nameEn: "red lentil soup",
        category: "corba",
        typicalPortion: RefPortion(grams: 175, householdUnit: "kepçe", householdQuantity: 1, description: nil),
        alternatePortions: [],
        nutritionPer100g: RefNutrition(calories: 63, proteinG: 3.4, carbsG: 8.6, fatG: 1.8),
        nutritionPerPortion: RefNutrition(calories: 110, proteinG: 6, carbsG: 15, fatG: 3.2),
        confidenceNote: "well-established",
        sourceContext: "test fixture"
    )

    private static let beyazPeynir = FoodReference(
        name: "beyaz peynir",
        nameEn: "white cheese (feta)",
        category: "sut-urunu",
        typicalPortion: RefPortion(grams: 50, householdUnit: "dilim", householdQuantity: 1, description: nil),
        alternatePortions: [],
        nutritionPer100g: RefNutrition(calories: 260, proteinG: 18, carbsG: 3, fatG: 20),
        nutritionPerPortion: RefNutrition(calories: 130, proteinG: 9, carbsG: 1.5, fatG: 10),
        confidenceNote: "well-established",
        sourceContext: "test fixture"
    )
}
