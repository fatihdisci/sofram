//
//  VisionResponseValidatorTests.swift
//  CalpTests — semantic clamp and consistency rules for AI responses.
//


import XCTest
@testable import Calp

final class VisionResponseValidatorTests: XCTestCase {
    func testConfidenceIsClampedToUnitRange() {
        XCTAssertEqual(sanitize(item(confidence: 7)).confidence, 1)
        XCTAssertEqual(sanitize(item(confidence: -2)).confidence, 0)
    }

    func testQuantityUsesFallbackAndAllowedRange() {
        XCTAssertEqual(sanitize(item(quantity: 0)).householdQuantity, 1)
        XCTAssertEqual(sanitize(item(quantity: 0.1)).householdQuantity, 0.25)
        XCTAssertEqual(sanitize(item(quantity: 80)).householdQuantity, 50)
    }

    func testEstimatedGramsAreClamped() {
        XCTAssertEqual(sanitize(item(grams: -20)).estimatedGrams, 1)
        XCTAssertEqual(sanitize(item(grams: 5_000)).estimatedGrams, 3_000)
    }

    func testCaloriesAndMacrosAreClamped() {
        let sanitized = sanitize(item(
            calories: -100,
            protein: -4,
            carbs: 2_000,
            fat: -8
        ))

        XCTAssertEqual(sanitized.proteinG, 0)
        XCTAssertEqual(sanitized.carbsG, 1_000)
        XCTAssertEqual(sanitized.fatG, 0)
        XCTAssertEqual(sanitized.calories, 4_000)
    }

    func testCaloriesAreDerivedFromMacrosWhenDeviationExceedsFortyPercent() {
        let sanitized = sanitize(item(
            calories: 1_000,
            protein: 10,
            carbs: 10,
            fat: 10,
            note: "not değişmemeli"
        ))

        XCTAssertEqual(sanitized.calories, 170)
        XCTAssertEqual(sanitized.note, "not değişmemeli")
    }

    func testCaloriesStayWhenWithinFortyPercentOfMacros() {
        let sanitized = sanitize(item(calories: 200, protein: 10, carbs: 20, fat: 8))

        XCTAssertEqual(sanitized.calories, 200)
    }

    func testEmptyNamesAreDroppedAndNoFoodBecomesTrue() {
        let response = VisionResponse(
            items: [item(name: "   ")],
            noFoodDetected: false
        ).sanitized()

        XCTAssertTrue(response.items.isEmpty)
        XCTAssertTrue(response.noFoodDetected)
    }

    private func sanitize(_ item: VisionItem) -> VisionItem {
        VisionResponse(items: [item], noFoodDetected: false).sanitized().items[0]
    }

    private func item(
        name: String = "çorba",
        grams: Double = 200,
        quantity: Double = 1,
        calories: Double = 200,
        protein: Double = 10,
        carbs: Double = 20,
        fat: Double = 8,
        confidence: Double = 0.8,
        note: String? = nil
    ) -> VisionItem {
        VisionItem(
            name: name,
            nameEn: "soup",
            estimatedGrams: grams,
            householdUnit: "kase",
            householdQuantity: quantity,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            confidence: confidence,
            note: note
        )
    }
}
