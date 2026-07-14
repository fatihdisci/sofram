//
//  DataExporterTests.swift
//  CalorisorTests — CSV encoding and spreadsheet compatibility coverage.
//

import XCTest
@testable import Calorisor

final class DataExporterTests: XCTestCase {
    func testCSVUsesBOMTurkishHeaderAndEscapesText() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let timestamp = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 9, minute: 5))
        )
        let item = LoggedItem(
            name: "Pilav, \"tereyağlı\"",
            portionUnit: .kase,
            quantity: 1.5,
            estimatedGrams: 250,
            calories: 320,
            protein: 6.25,
            carbs: 55,
            fat: 8,
            valueSource: "reference"
        )
        let scan = ScanEntry(timestamp: timestamp, source: .text, items: [item])

        let data = DataExporter.csvData(scans: [scan])
        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertTrue(csv.hasPrefix("\(DataExporter.header)\r\n"))
        XCTAssertTrue(csv.contains("2026-07-13,12:05,text"))
        XCTAssertTrue(csv.contains("\"Pilav, \"\"tereyağlı\"\"\""))
        XCTAssertTrue(csv.contains(",kase,1.5,250,320,6.25,55,8,reference"))
    }
}
