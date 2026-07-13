//
//  RawAIResponseTests.swift
//  CalorisorTests — raw AI response propagation coverage.
//


import XCTest
@testable import Calorisor

final class RawAIResponseTests: XCTestCase {
    func testDemoScanCarriesNonEmptyRawResponseIntoScanEntry() async throws {
        let configuration = AIProxyClient.Configuration(
            endpointURL: AIProxyClient.Configuration.placeholderEndpoint,
            apiKey: nil,
            timeout: 1
        )
        let result = try await AIProxyClient(configuration: configuration).scanText("1 kase çorba")
        let entry = result.response.makeScanEntry(source: .text, rawJSON: result.rawJSON)

        XCTAssertEqual(result.rawJSON, "demo")
        XCTAssertFalse(entry.rawAIResponse.isEmpty)
        XCTAssertEqual(entry.rawAIResponse, result.rawJSON)
    }
}
