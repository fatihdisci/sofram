//
//  UserDataDeletionTests.swift
//  SofraTests — destructive account-data reset coverage.
//

import SwiftData
import XCTest
@testable import Sofra

final class UserDataDeletionTests: XCTestCase {
    @MainActor
    func testDeleteModelsEmptiesEverySwiftDataModelType() throws {
        let configuration = ModelConfiguration(
            schema: SofraModelContainer.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: SofraModelContainer.schema,
            configurations: [configuration]
        )
        let context = container.mainContext

        let scan = ScanEntry(items: [LoggedItem(name: "Mercimek çorbası", calories: 150)])
        let quickItem = QuickAddItem(name: "Ekmek", caloriesPerUnit: 80)
        context.insert(scan)
        context.insert(QuickAddCount(itemID: quickItem.id, count: 2))
        context.insert(quickItem)
        context.insert(DailyQuickCounter(breadSlices: 1))
        context.insert(UserProfile())
        try context.save()

        try UserDataDeletion.deleteModels(in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ScanEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LoggedItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<QuickAddCount>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<QuickAddItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DailyQuickCounter>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
    }
}
