//
//  AIProxyRequestTests.swift
//  CalpTests — proxy request metadata contract coverage.
//


import XCTest
@testable import Calp

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
        XCTAssertNil(json["x-calp-installation-id"])
    }

    func testSignedTransactionIsSentOnlyWhenProvided() throws {
        let json = try encoded(AIProxyRequest.text(
            description: "çorba",
            locale: "tr_TR",
            signedTransactionInfo: "eyJhbGciOiJFUzI1NiJ9.test.signature"
        ))

        XCTAssertEqual(json["signed_transaction_info"] as? String, "eyJhbGciOiJFUzI1NiJ9.test.signature")
    }

    func testWeeklyReportRequestContainsOnlyDerivedSummaryMetrics() throws {
        let summary = WeeklySummary(
            days: [],
            previousDays: [],
            dailyCalorieTarget: 2_000,
            loggedDayCount: 4,
            averageCalories: 1_800,
            averageProtein: 82,
            targetMetDayCount: 3,
            highestCalorieDay: nil,
            lowestCalorieDay: nil,
            nightMealCount: 1,
            previousAverageCalories: 1_950,
            calorieChangeFromPreviousWeek: -150,
            calorieChangePercentFromPreviousWeek: -7.69,
            activeEnergyKcal: 3_100,
            weightChangeKg: -0.3
        )
        let request = WeeklyReportRequest(
            summary: WeeklyReportSummary(summary: summary),
            week: "2026-W29",
            locale: "tr_TR",
            signedTransactionInfo: "test-jws",
            appVersion: "1.0",
            forceRefresh: true
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let summaryJSON = try XCTUnwrap(json["summary"] as? [String: Any])

        XCTAssertEqual(json["week"] as? String, "2026-W29")
        XCTAssertEqual(json["signed_transaction_info"] as? String, "test-jws")
        XCTAssertEqual(json["force_refresh"] as? Bool, true)
        XCTAssertEqual(summaryJSON["registered_days"] as? Int, 4)
        XCTAssertEqual(summaryJSON["average_calories"] as? Double, 1_800)
        XCTAssertNil(json["raw_meals"])
        XCTAssertNil(json["scan_entries"])
        XCTAssertNil(json["healthkit_samples"])
    }
}
