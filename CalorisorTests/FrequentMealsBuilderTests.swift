import SwiftData
import XCTest
@testable import Calorisor

final class FrequentMealsBuilderTests: XCTestCase {
    private func item(
        _ name: String,
        unit: PortionUnit = .kase,
        quantity: Double = 1,
        calories: Double = 300
    ) -> LoggedItem {
        LoggedItem(name: name, portionUnit: unit, quantity: quantity, calories: calories, protein: 10, carbs: 20, fat: 8)
    }

    func testSameMealWithDifferentItemOrderSharesIdentity() {
        let first = [
            FrequentMealItem(id: UUID(), name: "Mercimek", nameEn: "Lentil", portionUnit: .kase, quantity: 1, estimatedGrams: 250, calories: 200, protein: 10, carbs: 25, fat: 5, confidence: 1, note: nil, valueSource: nil),
            FrequentMealItem(id: UUID(), name: "Ekmek", nameEn: "Bread", portionUnit: .dilim, quantity: 2, estimatedGrams: 60, calories: 160, protein: 5, carbs: 30, fat: 2, confidence: 1, note: nil, valueSource: nil),
        ]
        let second = [first[1], first[0]]

        XCTAssertEqual(FrequentMealsBuilder.mealIdentity(items: first), FrequentMealsBuilder.mealIdentity(items: second))
    }

    func testBuilderUsesLastThirtyDaysAndReturnsMostUsedFive() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = ScanEntry(timestamp: now.addingTimeInterval(-86_400), items: [item("Yoğurt")])
        let repeated = ScanEntry(timestamp: now.addingTimeInterval(-2 * 86_400), items: [item("Elma")])
        let repeatedAgain = ScanEntry(timestamp: now.addingTimeInterval(-3 * 86_400), items: [item("Elma")])
        let old = ScanEntry(timestamp: now.addingTimeInterval(-31 * 86_400), items: [item("Elma")])

        let meals = FrequentMealsBuilder.build(scans: [recent, repeated, repeatedAgain, old], now: now)

        XCTAssertEqual(meals.count, 2)
        XCTAssertEqual(meals.first?.name, "Elma")
        XCTAssertEqual(meals.first?.usageCount, 2)
    }

    func testDeepCopyCreatesIndependentManualEntry() throws {
        let source = ScanEntry(timestamp: .now, items: [item("Çorba", quantity: 2, calories: 220)])
        let meal = try XCTUnwrap(FrequentMealsBuilder.build(scans: [source]).first)
        let container = try ModelContainer(
            for: ScanEntry.self, LoggedItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let copy = FrequentMealsBuilder.deepCopy(meal, into: context)
        try context.save()

        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.source, .manual)
        XCTAssertEqual(copy.itemsOrEmpty.first?.quantity, 2)
        XCTAssertFalse(copy.itemsOrEmpty.first === source.itemsOrEmpty.first)
    }
}
