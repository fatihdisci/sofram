//
//  WidgetDailySummaryTests.swift
//  CalpTests — widget contract backward compatibility coverage.
//

import XCTest
@testable import Calp

final class WidgetDailySummaryTests: XCTestCase {
    func testLegacyJSONDecodesWithoutTopQuickAdds() throws {
        let legacyJSON = """
        {
          "calories": 500,
          "target": 2000,
          "protein": 20,
          "carbs": 50,
          "fat": 10,
          "breadSlices": 2,
          "teaGlasses": 3,
          "lastUpdated": 0,
          "progress": 0.25,
          "remaining": 1500
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let summary = try decoder.decode(WidgetDailySummary.self, from: Data(legacyJSON.utf8))

        XCTAssertTrue(summary.topQuickAdds.isEmpty)
        XCTAssertEqual(summary.breadSlices, 2)
        XCTAssertEqual(summary.teaGlasses, 3)
    }

    func testTopQuickAddsSurviveJSONRoundTrip() throws {
        let summary = WidgetDailySummary(
            topQuickAdds: [
                QuickAddSnapshot(name: "Ekmek", unit: "dilim", count: 3, iconName: "ekmekDilimi")
            ]
        )

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(WidgetDailySummary.self, from: data)

        XCTAssertEqual(decoded.topQuickAdds, summary.topQuickAdds)
    }
}
