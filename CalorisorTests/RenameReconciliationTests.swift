//
//  RenameReconciliationTests.swift
//  CalorisorTests — editable result name reconciliation coverage.
//

import XCTest
@testable import Calorisor

final class RenameReconciliationTests: XCTestCase {
    func testRenameMatchesReferenceThenReturnsToOriginalAIValues() throws {
        let original = VisionItem(
            name: "muzlu kek",
            nameEn: "banana cake",
            estimatedGrams: 100,
            householdUnit: "dilim",
            householdQuantity: 2,
            calories: 350,
            proteinG: 6,
            carbsG: 52,
            fatG: 14,
            confidence: 0.7,
            note: nil
        )
        let editable = EditableVisionItem(
            from: original,
            references: TurkishFoodReference.foods()
        )

        XCTAssertEqual(editable.valueSource, "ai")
        XCTAssertEqual(editable.calories, 350, accuracy: 0.001)

        editable.rename(to: "muz")

        XCTAssertEqual(editable.householdQuantity, 2)
        XCTAssertEqual(editable.valueSource, "reference")
        XCTAssertEqual(editable.referenceName, "Muz")
        XCTAssertNotEqual(editable.calories, 350, accuracy: 0.001)

        editable.rename(to: "muzlu kek")

        XCTAssertEqual(editable.householdQuantity, 2)
        XCTAssertEqual(editable.valueSource, "ai")
        XCTAssertNil(editable.referenceName)
        XCTAssertEqual(editable.calories, 350, accuracy: 0.001)
        XCTAssertEqual(editable.proteinG, 6, accuracy: 0.001)
        XCTAssertEqual(editable.carbsG, 52, accuracy: 0.001)
        XCTAssertEqual(editable.fatG, 14, accuracy: 0.001)
    }
}
