//
//  AIProxyClientTests.swift
//  CalorisorTests — end-to-end URLProtocol coverage without network access.
//

import XCTest
@testable import Calorisor

@MainActor
final class AIProxyClientTests: XCTestCase {
    override func tearDown() {
        AIClientMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testProxy200DecodesVisionResponse() async throws {
        stub(statusCode: 200, body: validVisionJSON)

        let result = try await makeProxyClient().scanText("bir kase çorba")

        XCTAssertEqual(result.response.items.first?.name, "mercimek çorbası")
        XCTAssertFalse(result.response.noFoodDetected)
    }

    func testProxy429MapsToRateLimited() async {
        stub(statusCode: 429, body: #"{"error":"rate_limited"}"#)
        await assertError(.rateLimited) { try await self.makeProxyClient().scanText("çorba") }
    }

    func testProxy500MapsToServerError() async {
        stub(statusCode: 500, body: #"{"error":"upstream_error"}"#)
        await assertError(.serverError) { try await self.makeProxyClient().scanText("çorba") }
    }

    func testMalformedSuccessJSONMapsToScanFailed() async {
        stub(statusCode: 200, body: "not-json")
        await assertError(.scanFailed) { try await self.makeProxyClient().scanText("çorba") }
    }

    func testProxyResponseIsSanitized() async throws {
        let unsafeJSON = """
        {"items":[{"name":"yoğurt","name_en":"yogurt","estimated_grams":-20,
        "household_unit":"kase","household_quantity":-2,"calories":-100,
        "protein_g":-4,"carbs_g":-5,"fat_g":-2,"confidence":2,"note":null}],
        "no_food_detected":false}
        """
        stub(statusCode: 200, body: unsafeJSON)

        let result = try await makeProxyClient().scanText("yoğurt")
        let item = try XCTUnwrap(result.response.items.first)

        XCTAssertEqual(item.calories, 0)
        XCTAssertEqual(item.proteinG, 0)
        XCTAssertEqual(item.carbsG, 0)
        XCTAssertEqual(item.fatG, 0)
        XCTAssertEqual(item.estimatedGrams, 1)
        XCTAssertEqual(item.householdQuantity, 1)
        XCTAssertEqual(item.confidence, 1)
    }

    func testProDirectRequestFallsBackFromMiniToNano() async throws {
        let previousSubscription = FreeScanCounter.shared.isSubscribed
        FreeScanCounter.shared.isSubscribed = true
        defer { FreeScanCounter.shared.isSubscribed = previousSubscription }

        let openAIData = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": validVisionJSON]]]
        ])
        var requestedModels: [String] = []
        AIClientMockURLProtocol.handler = { request in
            let body = try requestBodyData(request)
            let json = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let model = try XCTUnwrap(json["model"] as? String)
            requestedModels.append(model)
            let statusCode = model == "gpt-5-mini" ? 500 : 200
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, statusCode == 200 ? openAIData : Data(#"{"error":"temporary"}"#.utf8))
        }

        let configuration = AIProxyClient.Configuration(
            endpointURL: .init(string: "https://REPLACE-ME.vercel.app/api/scan")!,
            apiKey: nil,
            timeout: 1,
            openAIKey: "test-openai-key"
        )
        let result = try await AIProxyClient(
            configuration: configuration,
            session: makeSession()
        ).scanText("çorba")

        XCTAssertEqual(requestedModels, ["gpt-5-mini", "gpt-5-nano"])
        XCTAssertEqual(result.response.items.first?.name, "mercimek çorbası")
    }

    private var validVisionJSON: String {
        """
        {"items":[{"name":"mercimek çorbası","name_en":"lentil soup",
        "estimated_grams":250,"household_unit":"kase","household_quantity":1,
        "calories":180,"protein_g":10,"carbs_g":25,"fat_g":4,
        "confidence":0.9,"note":null}],"no_food_detected":false}
        """
    }

    private func makeProxyClient() -> AIProxyClient {
        AIProxyClient(
            configuration: .init(
                endpointURL: .init(string: "https://proxy.test/api/scan")!,
                apiKey: "test-key",
                timeout: 1
            ),
            session: makeSession()
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIClientMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func stub(statusCode: Int, body: String) {
        AIClientMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
    }

    private func assertError(
        _ expected: AIProxyError,
        operation: () async throws -> ScanResult
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? AIProxyError, expected)
        }
    }
}

private func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private final class AIClientMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
