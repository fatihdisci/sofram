//
//  AIProxyClientErrorTests.swift
//  CalorisorTests — proxy HTTP and transport error mapping coverage.
//


import XCTest
@testable import Calorisor

@MainActor
final class AIProxyClientErrorTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testHTTP429MapsToRateLimited() async {
        await assertError(statusCode: 429, equals: .rateLimited)
    }

    func testHTTP500MapsToServerError() async {
        await assertError(statusCode: 500, equals: .serverError)
    }

    func testProxyRateLimitedBodyMapsToRateLimited() async {
        await assertError(
            statusCode: 400,
            body: #"{"error":"rate_limited"}"#,
            equals: .rateLimited
        )
    }

    func testProxyUpstreamErrorBodyMapsToServerError() async {
        await assertError(
            statusCode: 400,
            body: #"{"error":"upstream_error"}"#,
            equals: .serverError
        )
    }

    func testNotConnectedMapsToOffline() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        await assertClientError(equals: .offline)
    }

    func testTimeoutMapsToOffline() async {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }

        await assertClientError(equals: .offline)
    }

    private func assertError(
        statusCode: Int,
        body: String = "{}",
        equals expected: AIProxyError
    ) async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }

        await assertClientError(equals: expected)
    }

    private func assertClientError(equals expected: AIProxyError) async {
        do {
            _ = try await makeClient().scanText("çorba")
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? AIProxyError, expected)
        }
    }

    private func makeClient() -> AIProxyClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let clientConfiguration = AIProxyClient.Configuration(
            endpointURL: URL(string: "https://proxy.test/api/scan")!,
            apiKey: "test-key",
            timeout: 1
        )
        return AIProxyClient(configuration: clientConfiguration, session: session)
    }
}

private final class MockURLProtocol: URLProtocol {
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
