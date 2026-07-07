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
    /// Base64-encoded JPEG bytes (nil for text scans).
    let imageBase64: String?
    /// Free-text meal description (nil for photo scans).
    let text: String?
    /// "photo" for image scans, "text" for free-text logging.
    let mode: String
    /// BCP-47 locale so the backend can bias dish naming (e.g. "tr-TR").
    let locale: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case text
        case mode
        case locale
    }

    /// Photo-scan request.
    static func photo(imageData: Data, locale: String) -> AIProxyRequest {
        AIProxyRequest(
            imageBase64: imageData.base64EncodedString(),
            text: nil,
            mode: "photo",
            locale: locale
        )
    }

    /// Text-scan request.
    static func text(description: String, locale: String) -> AIProxyRequest {
        AIProxyRequest(
            imageBase64: nil,
            text: description,
            mode: "text",
            locale: locale
        )
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
    func scan(imageData: Data) async throws -> VisionResponse {
        let locale = Locale.current.identifier
        let body = AIProxyRequest.photo(imageData: imageData, locale: locale)
        return try await performRequest(body: body)
    }

    /// Sends free-text description to the proxy and returns the typed result.
    func scanText(_ description: String) async throws -> VisionResponse {
        let locale = Locale.current.identifier
        let body = AIProxyRequest.text(description: description, locale: locale)
        return try await performRequest(body: body)
    }

    // MARK: - Private

    private func performRequest(body: AIProxyRequest) async throws -> VisionResponse {
        let urlRequest = try makeURLRequest(body: body)
        do {
            let (data, response) = try await session.data(for: urlRequest)
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
            throw AIProxyError.scanFailed
        }
    }

    private func makeURLRequest(body: AIProxyRequest) throws -> URLRequest {
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
