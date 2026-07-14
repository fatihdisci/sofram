//
//  AIProxyRequestTests.swift
//  CalorisorTests — proxy request metadata contract coverage.
//


import XCTest
@testable import Calorisor

final class AIProxyRequestTests: XCTestCase {
    private func encoded(_ request: AIProxyRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRequestBodyContainsSchemaAndAppVersions() throws {
        let json = try encoded(AIProxyRequest.text(
            description: "çorba",
            locale: "tr_TR",
            tier: "free",
            appVersion: "1.2.3"
        ))

        XCTAssertEqual(json["schema_version"] as? Int, 1)
        XCTAssertEqual(json["app_version"] as? String, "1.2.3")
        XCTAssertEqual(json["mode"] as? String, "text")
        XCTAssertEqual(json["locale"] as? String, "tr_TR")
        XCTAssertEqual(json["tier"] as? String, "free")
    }

    func testTypedTextRequestCarriesInputSourceAndClaimedTier() throws {
        let json = try encoded(AIProxyRequest.text(
            description: "çorba",
            locale: "tr_TR",
            tier: "pro"
        ))

        // Default text input is typed; claimed_tier mirrors the legacy tier so
        // the transitional server contract (scope doc §9) has both.
        XCTAssertEqual(json["input_source"] as? String, "typed_text")
        XCTAssertEqual(json["claimed_tier"] as? String, "pro")
        XCTAssertEqual(json["tier"] as? String, "pro")
    }

    func testVoiceTranscriptRequestUsesTextModeWithVoiceSource() throws {
        let json = try encoded(AIProxyRequest.text(
            description: "iki kepçe mercimek",
            locale: "tr_TR",
            tier: "free",
            inputSource: .voiceTranscript
        ))

        // A dictated meal is analysed through the text prompt (mode "text") but
        // reported as voice so the proxy can attribute it correctly.
        XCTAssertEqual(json["mode"] as? String, "text")
        XCTAssertEqual(json["input_source"] as? String, "voice_transcript")
    }

    func testPhotoRequestCarriesPhotoInputSource() throws {
        let json = try encoded(AIProxyRequest.photo(
            imageData: Data([0x01, 0x02, 0x03]),
            locale: "en_US",
            tier: "pro",
            appVersion: "2.0.0"
        ))

        XCTAssertEqual(json["mode"] as? String, "photo")
        XCTAssertEqual(json["input_source"] as? String, "photo")
        XCTAssertEqual(json["claimed_tier"] as? String, "pro")
        XCTAssertNotNil(json["image_base64"] as? String)
        XCTAssertNil(json["text"])
    }

    func testInstallationIDIsNeverInRequestBody() throws {
        let json = try encoded(AIProxyRequest.photo(
            imageData: Data([0x01]),
            locale: "tr_TR",
            tier: "free"
        ))
        // The raw installation UUID must ride in a header only (scope doc §8.2).
        XCTAssertNil(json["installation_id"])
        XCTAssertNil(json["x-calorisor-installation-id"])
    }
}
