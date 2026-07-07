//
//  AIProxyClient.swift
//  Sofra — networking client for the AI vision proxy.
//
//  MODEL-AGNOSTIC BY DESIGN. This client POSTs an image to a configurable endpoint
//  and gets back the typed `VisionResponse`. It never names a model. The endpoint is
//  a black box (a Vercel Edge Function). On the backend — out of scope here — the
//  proxy runs a primary/fallback model chain (see MODEL_RESEARCH.md: primary
//  Gemini Flash-Lite, automatic fallback to GPT-4.1 mini on error/refusal) and
//  caches by image hash via Upstash. The client only ever sees a valid response or
//  a generic failure, so the backend can swap models with zero client changes.
//
//  Transport: JSON body with a base64-encoded JPEG (documented in PHASE_1_NOTES.md).
//

import Foundation

enum AIProxyError: LocalizedError {
    /// Endpoint URL missing/malformed in configuration.
    case invalidConfiguration
    /// Anything the user should just retry: transport error, non-2xx, or unparseable body.
    /// Deliberately generic — the client does not distinguish which model failed.
    case scanFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Yapılandırma hatası."
        case .scanFailed:
            return "Tarama başarısız oldu, lütfen tekrar deneyin."
        }
    }
}

/// Request body sent to the proxy.
struct AIProxyRequest: Encodable {
    /// Base64-encoded JPEG bytes.
    let imageBase64: String
    /// "photo" for image scans. Reserved for a future "text" logging mode
    /// ("2 kepçe mercimek, 1 dilim ekmek") that shares this proxy contract.
    let mode: String
    /// BCP-47 locale so the backend can bias dish naming (e.g. "tr-TR").
    let locale: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mode
        case locale
    }
}

final class AIProxyClient {

    struct Configuration {
        /// The Vercel Edge Function endpoint. Placeholder for this phase — the real
        /// deployment is out of scope. Overridable via the Info.plist key
        /// `AIProxyEndpointURL`.
        var endpointURL: URL
        /// Optional shared secret sent as `x-sofra-key` (device-level, not a user account).
        var apiKey: String?
        var timeout: TimeInterval

        static let placeholderEndpoint = URL(string: "https://REPLACE-ME.vercel.app/api/scan")!

        /// Reads configuration from the app bundle, falling back to the placeholder.
        static func fromBundle(_ bundle: Bundle = .main) -> Configuration {
            let url = (bundle.object(forInfoDictionaryKey: "AIProxyEndpointURL") as? String)
                .flatMap(URL.init(string:)) ?? placeholderEndpoint
            let key = bundle.object(forInfoDictionaryKey: "AIProxyAPIKey") as? String
            return Configuration(endpointURL: url,
                                 apiKey: (key?.isEmpty == false) ? key : nil,
                                 timeout: 30)
        }
    }

    private let configuration: Configuration
    private let session: URLSession

    init(configuration: Configuration = .fromBundle(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Sends an image to the proxy and returns the typed result.
    /// Throws `AIProxyError.scanFailed` for any failure the user should retry.
    ///
    /// - Parameters:
    ///   - imageData: JPEG-encoded image bytes.
    ///   - source: how the scan was initiated (photo/text) — recorded on the result.
    func scan(imageData: Data, source: ScanSource = .photo) async throws -> VisionResponse {
        let request = try makeURLRequest(imageData: imageData)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw AIProxyError.scanFailed
            }
            return try JSONDecoder().decode(VisionResponse.self, from: data)
        } catch let error as AIProxyError {
            throw error
        } catch is DecodingError {
            throw AIProxyError.scanFailed
        } catch {
            // URLError / transport / cancellation — all surface as a generic retry.
            throw AIProxyError.scanFailed
        }
    }

    // MARK: - Private

    private func makeURLRequest(imageData: Data) throws -> URLRequest {
        let body = AIProxyRequest(
            imageBase64: imageData.base64EncodedString(),
            mode: "photo",
            locale: Locale.current.identifier
        )
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = configuration.apiKey {
            request.setValue(key, forHTTPHeaderField: "x-sofra-key")
        }
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw AIProxyError.invalidConfiguration
        }
        return request
    }
}
