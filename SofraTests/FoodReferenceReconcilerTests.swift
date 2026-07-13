//
//  FoodReferenceReconcilerTests.swift
//  SofraTests — Phase B3/B4 reference DB loader + reconcile coverage.
//

import XCTest
@testable import Sofra

final class FoodReferenceReconcilerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TurkishFoodReference.reset()
    }

    override func tearDown() {
        TurkishFoodReference.reset()
        super.tearDown()
    }

    func testTurkishFoodReferenceLoad_countAndCategoryDistribution() throws {
        let foods = try TurkishFoodReference.load()

        XCTAssertEqual(foods.count, 150)

        let counts = Dictionary(grouping: foods, by: \.category).mapValues(\.count)
        XCTAssertEqual(Set(counts.keys), [
            "corba", "kahvalti", "sut-urunu", "ekmek", "ana-yemek", "pilav-makarna",
            "meyve", "sebze", "atistirmalik", "tatli", "icecek", "fast-food",
        ])
        XCTAssertEqual(counts["corba"], 10)
        XCTAssertEqual(counts["kahvalti"], 16)
        XCTAssertEqual(counts["sut-urunu"], 6)
        XCTAssertEqual(counts["ekmek"], 6)
        XCTAssertEqual(counts["ana-yemek"], 14)
        XCTAssertEqual(counts["pilav-makarna"], 15)
        XCTAssertEqual(counts["meyve"], 14)
        XCTAssertEqual(counts["sebze"], 14)
        XCTAssertEqual(counts["atistirmalik"], 14)
        XCTAssertEqual(counts["tatli"], 14)
        XCTAssertEqual(counts["icecek"], 14)
        XCTAssertEqual(counts["fast-food"], 13)
    }

    func testBeyazPeynirWellEstablishedUsesReferenceValues() throws {
        let foods = try TurkishFoodReference.load()
        let reference = try XCTUnwrap(foods.first { $0.name == "beyaz peynir" })
        let item = makeVisionItem(
            name: "Beyaz peynir",
            nameEn: "white cheese",
            estimatedGrams: 75,
            calories: 999,
            proteinG: 1,
            carbsG: 2,
            fatG: 3
        )

        let reconciled = ReferenceReconciler.reconcile(item: item, in: foods)

        XCTAssertEqual(reconciled.source, .reference)
        XCTAssertEqual(reconciled.referenceName, reference.name)
        XCTAssertEqual(reconciled.confidenceNote, "well-established")
        XCTAssertEqual(reconciled.calories, 75 * reference.nutritionPer100g.calories / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.protein, 75 * reference.nutritionPer100g.proteinG / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.carbs, 75 * reference.nutritionPer100g.carbsG / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.fat, 75 * reference.nutritionPer100g.fatG / 100, accuracy: 0.001)
    }

    func testTonBaligiWellEstablishedUsesReferenceValues() throws {
        let foods = try TurkishFoodReference.load()
        let reference = try XCTUnwrap(foods.first { $0.name == "ton balığı (konserve)" })
        let item = makeVisionItem(
            name: "Ton balığı",
            nameEn: "canned tuna",
            estimatedGrams: 80,
            calories: 999,
            proteinG: 1,
            carbsG: 2,
            fatG: 3
        )

        let reconciled = ReferenceReconciler.reconcile(item: item, in: foods)

        XCTAssertEqual(reconciled.source, .reference)
        XCTAssertEqual(reconciled.referenceName, reference.name)
        XCTAssertEqual(reconciled.confidenceNote, "well-established")
        XCTAssertEqual(reconciled.calories, 80 * reference.nutritionPer100g.calories / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.protein, 80 * reference.nutritionPer100g.proteinG / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.carbs, 80 * reference.nutritionPer100g.carbsG / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.fat, 80 * reference.nutritionPer100g.fatG / 100, accuracy: 0.001)
    }

    func testKremaliMakarnaWellEstablishedUsesReferenceValues() throws {
        let foods = try TurkishFoodReference.load()
        let reference = try XCTUnwrap(foods.first { $0.name == "Kremalı makarna" })
        let item = makeVisionItem(
            name: "Kremalı makarna",
            nameEn: "Creamy pasta",
            estimatedGrams: 250,
            calories: 999,
            proteinG: 1,
            carbsG: 2,
            fatG: 3
        )

        let reconciled = ReferenceReconciler.reconcile(item: item, in: foods)

        XCTAssertEqual(reconciled.source, .reference)
        XCTAssertEqual(reconciled.referenceName, reference.name)
        XCTAssertEqual(reconciled.confidenceNote, "well-established")
        XCTAssertEqual(reconciled.calories, 250 * reference.nutritionPer100g.calories / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.protein, 250 * reference.nutritionPer100g.proteinG / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.carbs, 250 * reference.nutritionPer100g.carbsG / 100, accuracy: 0.001)
        XCTAssertEqual(reconciled.fat, 250 * reference.nutritionPer100g.fatG / 100, accuracy: 0.001)
    }

    func testReconcileIsDeterministicForSameInput() throws {
        let foods = try TurkishFoodReference.load()
        let item = makeVisionItem(
            name: "Beyaz peynir",
            nameEn: "white cheese",
            estimatedGrams: 75,
            calories: 999,
            proteinG: 1,
            carbsG: 2,
            fatG: 3
        )

        let first = ReferenceReconciler.reconcile(item: item, in: foods)
        let second = ReferenceReconciler.reconcile(item: item, in: foods)

        XCTAssertEqual(first, second)
    }

    func testApproximateReferenceKeepsAIValues() throws {
        let foods = try TurkishFoodReference.load()
        let item = makeVisionItem(
            name: "Ezogelin çorbası",
            nameEn: "ezogelin soup",
            estimatedGrams: 250,
            calories: 222,
            proteinG: 11,
            carbsG: 33,
            fatG: 4
        )

        let reconciled = ReferenceReconciler.reconcile(item: item, in: foods)

        XCTAssertEqual(reconciled.source, .ai)
        XCTAssertEqual(reconciled.referenceName, "ezogelin çorbası")
        XCTAssertEqual(reconciled.confidenceNote, "approximate")
        XCTAssertEqual(reconciled.calories, 222)
        XCTAssertEqual(reconciled.protein, 11)
        XCTAssertEqual(reconciled.carbs, 33)
        XCTAssertEqual(reconciled.fat, 4)
    }

    func testApproximateMercimekFixtureKeepsAIValues() {
        let approximateMercimek = FoodReference(
            name: "mercimek çorbası",
            nameEn: "red lentil soup",
            category: "corba",
            typicalPortion: RefPortion(grams: 175, householdUnit: "kepçe", householdQuantity: 1, description: nil),
            alternatePortions: [],
            nutritionPer100g: RefNutrition(calories: 63, proteinG: 3.4, carbsG: 8.6, fatG: 1.8),
            nutritionPerPortion: RefNutrition(calories: 110, proteinG: 6, carbsG: 15, fatG: 3.2),
            confidenceNote: "approximate",
            sourceContext: "test fixture"
        )
        let item = makeVisionItem(
            name: "mercimek çorbası",
            nameEn: "red lentil soup",
            estimatedGrams: 175,
            calories: 180,
            proteinG: 9,
            carbsG: 24,
            fatG: 5
        )

        let reconciled = ReferenceReconciler.reconcile(item: item, in: [approximateMercimek])

        XCTAssertEqual(reconciled.source, .ai)
        XCTAssertEqual(reconciled.referenceName, "mercimek çorbası")
        XCTAssertEqual(reconciled.calories, 180)
        XCTAssertEqual(reconciled.protein, 9)
        XCTAssertEqual(reconciled.carbs, 24)
        XCTAssertEqual(reconciled.fat, 5)
    }

    func testUnknownFoodKeepsAIValues() throws {
        let foods = try TurkishFoodReference.load()
        let item = makeVisionItem(
            name: "plüton pilavı",
            nameEn: "pluto rice",
            estimatedGrams: 200,
            calories: 321,
            proteinG: 7,
            carbsG: 60,
            fatG: 8
        )

        let reconciled = ReferenceReconciler.reconcile(item: item, in: foods)

        XCTAssertEqual(reconciled.source, .ai)
        XCTAssertNil(reconciled.referenceName)
        XCTAssertNil(reconciled.confidenceNote)
        XCTAssertEqual(reconciled.calories, 321)
        XCTAssertEqual(reconciled.protein, 7)
        XCTAssertEqual(reconciled.carbs, 60)
        XCTAssertEqual(reconciled.fat, 8)
    }

    func testMakeLoggedItemStoresValueSource() throws {
        let foods = try TurkishFoodReference.load()
        let referenceItem = makeVisionItem(
            name: "Beyaz peynir",
            nameEn: "white cheese",
            estimatedGrams: 50,
            calories: 999,
            proteinG: 1,
            carbsG: 1,
            fatG: 1
        )
        let aiItem = makeVisionItem(
            name: "plüton pilavı",
            nameEn: "pluto rice",
            estimatedGrams: 200,
            calories: 321,
            proteinG: 7,
            carbsG: 60,
            fatG: 8
        )

        XCTAssertEqual(referenceItem.makeLoggedItem(references: foods).valueSource, "reference")
        XCTAssertEqual(aiItem.makeLoggedItem(references: foods).valueSource, "ai")
    }

    func testAllHouseholdUnitsMapToPortionUnit() throws {
        let foods = try TurkishFoodReference.load()
        let units = Set(foods.flatMap { food in
            [food.typicalPortion.householdUnit] + food.alternatePortions.map(\.householdUnit)
        })
        let portionUnitRawValues = Set(PortionUnit.allCases.map(\.rawValue))
        let unmapped = units.subtracting(portionUnitRawValues)

        XCTAssertTrue(unmapped.isEmpty, "Unmapped household_unit values: \(unmapped.sorted())")
    }

    func testCategoryDisplayNames() throws {
        let foods = try TurkishFoodReference.load()
        let displayNames = foods.reduce(into: [String: String]()) { out, food in
            out[food.category] = food.categoryDisplayName
        }

        XCTAssertEqual(displayNames["corba"], "Çorba")
        XCTAssertEqual(displayNames["kahvalti"], "Kahvaltılık")
        XCTAssertEqual(displayNames["sut-urunu"], "Süt Ürünü")
        XCTAssertEqual(displayNames["ekmek"], "Ekmek")
    }

    private func makeVisionItem(
        name: String,
        nameEn: String,
        estimatedGrams: Double,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        householdUnit: String = "gram",
        householdQuantity: Double = 1,
        confidence: Double = 0.9,
        note: String? = nil
    ) -> VisionItem {
        VisionItem(
            name: name,
            nameEn: nameEn,
            estimatedGrams: estimatedGrams,
            householdUnit: householdUnit,
            householdQuantity: householdQuantity,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            confidence: confidence,
            note: note
        )
    }
}
