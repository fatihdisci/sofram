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
            appVersion: "1.2.3"
        ))

        XCTAssertEqual(json["schema_version"] as? Int, 1)
        XCTAssertEqual(json["app_version"] as? String, "1.2.3")
        XCTAssertEqual(json["mode"] as? String, "text")
        XCTAssertEqual(json["locale"] as? String, "tr_TR")
        XCTAssertNil(json["tier"])
    }

    func testTypedTextRequestCarriesInputSourceWithoutClientTier() throws {
        let json = try encoded(AIProxyRequest.text(
            description: "çorba",
            locale: "tr_TR"
        ))

        // The server decides tier from the signed transaction, never this body.
        XCTAssertEqual(json["input_source"] as? String, "typed_text")
        XCTAssertNil(json["signed_transaction_info"])
    }

    func testVoiceTranscriptRequestUsesTextModeWithVoiceSource() throws {
        let json = try encoded(AIProxyRequest.text(
            description: "iki kepçe mercimek",
            locale: "tr_TR",
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
            appVersion: "2.0.0"
        ))

        XCTAssertEqual(json["mode"] as? String, "photo")
        XCTAssertEqual(json["input_source"] as? String, "photo")
        XCTAssertNotNil(json["image_base64"] as? String)
        XCTAssertNil(json["text"])
    }

    func testInstallationIDIsNeverInRequestBody() throws {
        let json = try encoded(AIProxyRequest.photo(
            imageData: Data([0x01]),
            locale: "tr_TR",
        ))
        // The raw installation UUID must ride in a header only (scope doc §8.2).
        XCTAssertNil(json["installation_id"])
        XCTAssertNil(json["x-calorisor-installation-id"])
    }

    func testSignedTransactionIsSentOnlyWhenProvided() throws {
        let json = try encoded(AIProxyRequest.text(
            description: "çorba",
            locale: "tr_TR",
            signedTransactionInfo: "eyJhbGciOiJFUzI1NiJ9.test.signature"
        ))

        XCTAssertEqual(json["signed_transaction_info"] as? String, "eyJhbGciOiJFUzI1NiJ9.test.signature")
    }
}
