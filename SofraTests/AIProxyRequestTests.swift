//
//  AIProxyRequestTests.swift
//  SofraTests — proxy request metadata contract coverage.
//


import XCTest
@testable import Sofra

final class AIProxyRequestTests: XCTestCase {
    func testRequestBodyContainsSchemaAndAppVersions() throws {
        let request = AIProxyRequest.text(
            description: "çorba",
            locale: "tr_TR",
            tier: "free",
            appVersion: "1.2.3"
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["schema_version"] as? Int, 1)
        XCTAssertEqual(json["app_version"] as? String, "1.2.3")
        XCTAssertEqual(json["mode"] as? String, "text")
        XCTAssertEqual(json["locale"] as? String, "tr_TR")
        XCTAssertEqual(json["tier"] as? String, "free")
    }
}
