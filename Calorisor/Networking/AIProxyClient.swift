//
//  AIProxyClient.swift
//  Calorisor — networking client for the AI vision proxy.
//
//  MODEL-AGNOSTIC BY DESIGN. Resolution order:
//    1. Vercel Edge Function proxy (production) — configured via Info.plist
//    2. OpenAI Chat Completions API direct (dev/testing) — key from Secrets.plist
//    3. Demo data (DEBUG only) — when neither is configured
//
//  Tier-based model selection (see MODEL_RESEARCH.md):
//    free → GPT-5-nano    ($0.05/$0.005 per 1M)
//    pro  → GPT-5-mini    ($0.25/$0.025 per 1M, fallback GPT-5-nano)
//
//  The client sends {tier: "free"|"pro"} to the proxy or picks the model directly
//  in direct OpenAI mode. The proxy can override model choice at any time.
//

import CryptoKit
import Foundation
import UIKit

// MARK: - Errors

enum AIProxyError: LocalizedError, Equatable {
    case invalidConfiguration
    case notConfigured
    case rateLimited
    case dailyLimitReached(limitType: FreeScanPool)
    case offline
    case serverError
    case scanFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return String(localized: "Yapılandırma hatası.")
        case .notConfigured:
            return String(localized: "AI sunucusu henüz bağlanmadı. Bu bir uygulama hatası değil -- sunucu adresi yapılandırılınca tarama çalışacak.")
        case .rateLimited:
            return String(localized: "Çok sık denedin -- bir dakika sonra tekrar dene.")
        case .dailyLimitReached(let limitType):
            switch limitType {
            case .photo:
                return String(localized: "Bugünkü fotoğraf analiz hakkın doldu. Öğününü elle ekleyebilirsin.")
            case .text:
                return String(localized: "Bugünkü metin ve ses analiz hakkın doldu. Öğününü elle ekleyebilirsin.")
            }
        case .offline:
            return String(localized: "İnternet bağlantısı yok görünüyor.")
        case .serverError:
            return String(localized: "Sunucuda geçici bir sorun var, birazdan düzelir.")
        case .scanFailed:
            return String(localized: "Tarama başarısız oldu, lütfen tekrar deneyin.")
        }
    }
}

// MARK: - Proxy request body

/// Where a scan's input came from. Sent as `input_source` so the proxy can
/// meter photo separately from text/voice, with voice sharing the text pool
/// (scope doc §11.2). Distinct from `mode` ("photo"/"text"), which selects the
/// prompt: a voice transcript is `mode: "text"`, `input_source: "voice_transcript"`.
enum AIProxyInputSource: String {
    case photo = "photo"
    case typedText = "typed_text"
    case voiceTranscript = "voice_transcript"
}

struct AIProxyRequest: Encodable {
    let imageBase64: String?
    let text: String?
    let mode: String
    let inputSource: String
    let locale: String
    /// Legacy tier field, kept so the currently deployed proxy keeps working.
    let tier: String
    /// Same value as `tier`, under the name the new server-side contract uses
    /// (scope doc §9). Transitional only — once the proxy verifies the signed
    /// StoreKit transaction (SF-1303) neither client-supplied field is trusted
    /// for model or limit selection.
    let claimedTier: String
    let schemaVersion: Int
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case inputSource = "input_source"
        case claimedTier = "claimed_tier"
        case schemaVersion = "schema_version"
        case appVersion = "app_version"
        case text, mode, locale, tier
    }

    static func photo(
        imageData: Data,
        locale: String,
        tier: String,
        appVersion: String? = nil
    ) -> AIProxyRequest {
        AIProxyRequest(
            imageBase64: imageData.base64EncodedString(),
            text: nil,
            mode: "photo",
            inputSource: AIProxyInputSource.photo.rawValue,
            locale: locale,
            tier: tier,
            claimedTier: tier,
            schemaVersion: 1,
            appVersion: appVersion ?? currentAppVersion()
        )
    }

    static func text(
        description: String,
        locale: String,
        tier: String,
        inputSource: AIProxyInputSource = .typedText,
        appVersion: String? = nil
    ) -> AIProxyRequest {
        AIProxyRequest(
            imageBase64: nil,
            text: description,
            mode: "text",
            inputSource: inputSource.rawValue,
            locale: locale,
            tier: tier,
            claimedTier: tier,
            schemaVersion: 1,
            appVersion: appVersion ?? currentAppVersion()
        )
    }

    private static func currentAppVersion(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}

// MARK: - OpenAI request/response types (direct API mode)

private struct OpenAIMessage: Encodable {
    let role: String
    let content: [OpenAIContentPart]
}

private struct OpenAIContentPart: Encodable {
    let type: String
    let text: String?
    let imageUrl: OpenAIImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }

    static func text(_ string: String) -> OpenAIContentPart {
        OpenAIContentPart(type: "text", text: string, imageUrl: nil)
    }

    static func image(base64: String) -> OpenAIContentPart {
        OpenAIContentPart(type: "image_url", text: nil, imageUrl: OpenAIImageURL(url: "data:image/jpeg;base64,\(base64)"))
    }
}

private struct OpenAIImageURL: Encodable {
    let url: String
}

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    /// GPT-5 family requires `max_completion_tokens` (the old `max_tokens` is rejected).
    /// The budget also covers reasoning tokens, so it must be generous or the model
    /// can spend the whole cap thinking and return empty content (finish_reason: length).
    let maxCompletionTokens: Int
    /// GPT-5 models only accept the default temperature (1). Sending a custom value
    /// returns HTTP 400, so we omit temperature entirely and steer accuracy with
    /// `reasoning_effort` instead — "minimal" keeps latency low for a structured task.
    let reasoningEffort: String
    /// Best-effort reproducibility: a stable hash of the input (text or image
    /// bytes), so identical input always sends the same seed. OpenAI doesn't
    /// guarantee bit-identical completions even with a fixed seed, but this
    /// removes one source of run-to-run variance for free.
    let seed: Int
    /// Structured Outputs (strict `json_schema`) — constrains the model to emit
    /// exactly the `VisionResponse` shape (including a closed `household_unit`
    /// enum), so parsing never depends on prose instructions being followed.
    let responseFormat: OpenAIResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, seed
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
        case responseFormat = "response_format"
    }
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Structured Outputs (strict json_schema for VisionResponse)

/// Minimal JSON-value box so a fixed, arbitrarily-nested `json_schema` payload
/// can be embedded in an `Encodable` request body without hand-writing a
/// dedicated struct per schema node — the shape never varies at runtime.
private indirect enum JSONValue: Encodable {
    case string(String)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        }
    }
}

private struct OpenAIResponseFormat: Encodable {
    let type = "json_schema"
    let jsonSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    /// Mirrors `VisionResponse`/`VisionItem` (Calorisor/Networking/VisionResponse.swift)
    /// field-for-field. `household_unit`'s enum matches the vocabulary both
    /// prompts already restrict the model to (see `textPrompt`/`visionPrompt`).
    static let visionResponse = OpenAIResponseFormat(jsonSchema: .object([
        "name": .string("vision_response"),
        "strict": .bool(true),
        "schema": .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "items": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "name": .object(["type": .string("string")]),
                            "name_en": .object(["type": .string("string")]),
                            "estimated_grams": .object(["type": .string("number")]),
                            "household_unit": .object([
                                "type": .string("string"),
                                "enum": .array([
                                    "kepçe", "yemek kaşığı", "su bardağı", "çay bardağı",
                                    "dilim", "avuç", "kase", "adet",
                                    "ladle", "tbsp", "glass", "tea glass",
                                    "slice", "handful", "bowl", "piece", "cup",
                                ].map(JSONValue.string)),
                            ]),
                            "household_quantity": .object(["type": .string("number")]),
                            "calories": .object(["type": .string("number")]),
                            "protein_g": .object(["type": .string("number")]),
                            "carbs_g": .object(["type": .string("number")]),
                            "fat_g": .object(["type": .string("number")]),
                            "confidence": .object(["type": .string("number")]),
                            "note": .object(["type": .array([.string("string"), .string("null")])]),
                        ]),
                        "required": .array([
                            "name", "name_en", "estimated_grams", "household_unit",
                            "household_quantity", "calories", "protein_g", "carbs_g",
                            "fat_g", "confidence", "note",
                        ].map(JSONValue.string)),
                    ]),
                ]),
                "no_food_detected": .object(["type": .string("boolean")]),
            ]),
            "required": .array(["items", "no_food_detected"].map(JSONValue.string)),
        ]),
    ]))
}

/// Stable (cross-launch) hash — `String`/`Data`'s own `hashValue`/`Hasher` are
/// per-process-salted in Swift and would silently stop reproducing between
/// app runs, defeating the point of a seed.
private func stableSeed(for data: Data) -> Int {
    let digest = SHA256.hash(data: data)
    let value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    return Int(value & 0x7FFF_FFFF_FFFF_FFFF)
}

// MARK: - Client

struct ScanResult: Equatable {
    let response: VisionResponse
    let rawJSON: String
    let quota: ScanQuotaSnapshot?

    init(response: VisionResponse, rawJSON: String, quota: ScanQuotaSnapshot? = nil) {
        self.response = response
        self.rawJSON = rawJSON
        self.quota = quota
    }
}

private struct ProxyErrorResponse: Decodable {
    let error: String
    let limitType: String?

    enum CodingKeys: String, CodingKey {
        case error
        case limitType = "limit_type"
    }
}

final class AIProxyClient {

    struct Configuration {
        var endpointURL: URL
        var apiKey: String?
        var timeout: TimeInterval
        /// Direct-development credentials loaded by `fromBundle`. Stored here
        /// so tests can explicitly keep direct networking disabled.
        var openAIKey: String?
        var openAIOrgID: String?

        init(
            endpointURL: URL,
            apiKey: String?,
            timeout: TimeInterval,
            openAIKey: String? = nil,
            openAIOrgID: String? = nil
        ) {
            self.endpointURL = endpointURL
            self.apiKey = apiKey
            self.timeout = timeout
            self.openAIKey = openAIKey
            self.openAIOrgID = openAIOrgID
        }

        static let placeholderEndpoint = URL(string: "https://REPLACE-ME.vercel.app/api/scan")!

        static func fromBundle(_ bundle: Bundle = .main) -> Configuration {
            let url = (bundle.object(forInfoDictionaryKey: "AIProxyEndpointURL") as? String)
                .flatMap(URL.init(string:)) ?? placeholderEndpoint
            let key = bundle.object(forInfoDictionaryKey: "AIProxyAPIKey") as? String
            let secrets = bundle.url(forResource: "Secrets", withExtension: "plist")
                .flatMap(NSDictionary.init(contentsOf:))
            let openAIKey = (secrets?["OpenAIAPIKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let openAIOrgID = (secrets?["OpenAIOrgID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Configuration(endpointURL: url,
                                 apiKey: (key?.isEmpty == false) ? key : nil,
                                 timeout: 30,
                                 openAIKey: openAIKey,
                                 openAIOrgID: openAIOrgID)
        }
    }

    private let configuration: Configuration
    private let session: URLSession

    init(configuration: Configuration = .fromBundle(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    var isConfigured: Bool {
        configuration.endpointURL.host()?.contains("REPLACE-ME") != true
    }

    /// True when we can call OpenAI directly (API key available, no proxy configured).
    var canUseDirectOpenAI: Bool {
        configuration.openAIKey != nil
    }

    var isDemoMode: Bool {
        #if DEBUG
        return !isConfigured && !canUseDirectOpenAI
        #else
        return false
        #endif
    }

    // MARK: - Public API

    func scan(imageData: Data) async throws -> ScanResult {
        if isDemoMode {
            return ScanResult(response: try await DemoVisionData.photoResponse(), rawJSON: "demo")
        }
        let tier = await FreeScanCounter.shared.isSubscribed ? "pro" : "free"
        let payload = ImageDownscaler.jpegForUpload(imageData) ?? imageData

        // 1. Try Vercel proxy (production)
        if isConfigured {
            let body = AIProxyRequest.photo(imageData: payload, locale: AppLanguage.current.effectiveLocale.identifier, tier: tier)
            return try await performProxyRequest(body: body)
        }

        // 2. Try direct OpenAI (dev/testing)
        if canUseDirectOpenAI {
            return try await callOpenAIVision(imageData: payload, tier: tier)
        }

        throw AIProxyError.notConfigured
    }

    func scanText(
        _ description: String,
        inputSource: AIProxyInputSource = .typedText
    ) async throws -> ScanResult {
        if isDemoMode {
            return ScanResult(
                response: try await DemoVisionData.textResponse(for: description),
                rawJSON: "demo"
            )
        }
        let tier = await FreeScanCounter.shared.isSubscribed ? "pro" : "free"

        if isConfigured {
            let body = AIProxyRequest.text(
                description: description,
                locale: AppLanguage.current.effectiveLocale.identifier,
                tier: tier,
                inputSource: inputSource
            )
            return try await performProxyRequest(body: body)
        }

        if canUseDirectOpenAI {
            return try await callOpenAIText(description: description, tier: tier)
        }

        throw AIProxyError.notConfigured
    }

    // MARK: - Vercel proxy

    private func performProxyRequest(body: AIProxyRequest) async throws -> ScanResult {
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = configuration.apiKey {
            request.setValue(key, forHTTPHeaderField: "x-calorisor-key")
        }
        // Anonymous per-installation identity travels in a header only — never in
        // the body. The proxy hashes the raw UUID with a server secret before any
        // log touches it (scope doc §8.2 / §9), so it is the rate-limit key
        // without ever being persisted in the clear.
        request.setValue(InstallationIdentity.shared.headerValue,
                         forHTTPHeaderField: "x-calorisor-installation-id")
        request.setValue(body.appVersion, forHTTPHeaderField: "x-calorisor-app-version")
        request.setValue("ios", forHTTPHeaderField: "x-calorisor-platform")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mappedNetworkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIProxyError.scanFailed
        }
        if let responseError = mappedProxyError(statusCode: http.statusCode, data: data) {
            // Daily-limit responses include the same authoritative headers as
            // successful responses. Sync before throwing so the next screen
            // cannot offer a scan the server will immediately reject.
            if let quota = quotaSnapshot(from: http) {
                await FreeScanCounter.shared.applyServerQuota(quota)
            }
            throw responseError
        }
        let quota = quotaSnapshot(from: http)
        if let quota {
            await FreeScanCounter.shared.applyServerQuota(quota)
        }
        guard let rawJSON = String(data: data, encoding: .utf8) else {
            throw AIProxyError.scanFailed
        }
        do {
            return ScanResult(
                response: try JSONDecoder().decode(VisionResponse.self, from: data).sanitized(),
                rawJSON: rawJSON,
                quota: quota
            )
        } catch {
            throw AIProxyError.scanFailed
        }
    }

    private func quotaSnapshot(from response: HTTPURLResponse) -> ScanQuotaSnapshot? {
        guard
            let tier = response.value(forHTTPHeaderField: "x-calorisor-tier"),
            let photoRemaining = response.value(forHTTPHeaderField: "x-calorisor-photo-remaining").flatMap(Int.init),
            let photoLimit = response.value(forHTTPHeaderField: "x-calorisor-photo-limit").flatMap(Int.init),
            let textRemaining = response.value(forHTTPHeaderField: "x-calorisor-text-remaining").flatMap(Int.init),
            let textLimit = response.value(forHTTPHeaderField: "x-calorisor-text-limit").flatMap(Int.init)
        else {
            return nil
        }
        return ScanQuotaSnapshot(
            tier: tier,
            photoRemaining: max(0, photoRemaining),
            photoLimit: max(0, photoLimit),
            textRemaining: max(0, textRemaining),
            textLimit: max(0, textLimit)
        )
    }

    // MARK: - Direct OpenAI API

    private func openAIURL() -> URL {
        URL(string: "https://api.openai.com/v1/chat/completions")!
    }

    private func openAIModel(for tier: String) -> String {
        // tier → model mapping. Models confirmed on OpenAI official pricing page (July 2026).
        // gpt-5-mini: $0.25/$0.025 | gpt-5-nano: $0.05/$0.005
        // Dated snapshots exist (gpt-5-mini-2025-08-07, gpt-5-nano-2025-08-07) but
        // rolling aliases are preferred to track improvements automatically.
        tier == "pro" ? "gpt-5-mini" : "gpt-5-nano"
    }

    private func openAIHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(configuration.openAIKey ?? "")"
        ]
        if let orgID = configuration.openAIOrgID {
            headers["OpenAI-Organization"] = orgID
        }
        return headers
    }

    /// Photo → OpenAI Chat Completions (vision).
    private func callOpenAIVision(imageData: Data, tier: String) async throws -> ScanResult {
        let model = openAIModel(for: tier)
        let base64 = imageData.base64EncodedString()
        let prompt = visionPrompt(locale: AppLanguage.current.effectiveLocale.identifier)

        let body = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "user", content: [
                    .text(prompt),
                    .image(base64: base64)
                ])
            ],
            maxCompletionTokens: 2048,
            // Photo identification needs more grounding than text parsing does —
            // "minimal" was producing confident-sounding but wrong dish names
            // (e.g. mashed potato + meat sauce misread as "mantı" from color/
            // shape alone). "low" costs a bit more but meaningfully improves
            // visual disambiguation.
            reasoningEffort: "low",
            seed: stableSeed(for: imageData),
            responseFormat: .visionResponse
        )

        return try await performOpenAIRequest(body: body, model: model, tier: tier)
    }

    /// Text → OpenAI Chat Completions.
    private func callOpenAIText(description: String, tier: String) async throws -> ScanResult {
        let model = openAIModel(for: tier)
        let prompt = textPrompt(description: description, locale: AppLanguage.current.effectiveLocale.identifier)

        let body = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "user", content: [.text(prompt)])
            ],
            maxCompletionTokens: 2048,
            reasoningEffort: "minimal",
            seed: stableSeed(for: Data(description.utf8)),
            responseFormat: .visionResponse
        )

        return try await performOpenAIRequest(body: body, model: model, tier: tier)
    }

    /// Shared: POST to OpenAI, parse JSON response into VisionResponse.
    private func performOpenAIRequest(body: OpenAIRequest, model: String, tier: String) async throws -> ScanResult {
        var request = URLRequest(url: openAIURL())
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        for (key, value) in openAIHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIProxyError.scanFailed }

            if http.statusCode == 429 {
                throw AIProxyError.rateLimited
            }

            if http.statusCode >= 400 {
                // Log the actual error for debugging
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                print("[AIProxyClient] OpenAI error \(http.statusCode): \(body)")
            }

            // Try gpt-5-nano fallback if gpt-5-mini fails (pro tier only)
            if http.statusCode >= 400, tier == "pro", model != "gpt-5-nano" {
                let fallbackBody = OpenAIRequest(
                    model: "gpt-5-nano",
                    messages: body.messages,
                    maxCompletionTokens: body.maxCompletionTokens,
                    reasoningEffort: body.reasoningEffort,
                    seed: body.seed,
                    responseFormat: body.responseFormat
                )
                var fallbackRequest = URLRequest(url: openAIURL())
                fallbackRequest.httpMethod = "POST"
                fallbackRequest.timeoutInterval = configuration.timeout
                for (key, value) in openAIHeaders() {
                    fallbackRequest.setValue(value, forHTTPHeaderField: key)
                }
                fallbackRequest.httpBody = try JSONEncoder().encode(fallbackBody)
                let (fallbackData, fallbackResponse) = try await session.data(for: fallbackRequest)
                guard let fallbackHTTP = fallbackResponse as? HTTPURLResponse else {
                    throw AIProxyError.scanFailed
                }
                if let fallbackError = mappedHTTPError(statusCode: fallbackHTTP.statusCode) {
                    let fb = String(data: fallbackData, encoding: .utf8) ?? "<no body>"
                    print("[AIProxyClient] Fallback also failed: \(fb)")
                    throw fallbackError
                }
                return try parseOpenAIResponse(fallbackData)
            }

            if let responseError = mappedHTTPError(statusCode: http.statusCode) {
                throw responseError
            }
            return try parseOpenAIResponse(data)
        } catch let error as AIProxyError { throw error }
        catch {
            print("[AIProxyClient] Unexpected error: \(error.localizedDescription)")
            throw mappedNetworkError(error)
        }
    }

    /// Parse OpenAI JSON response → VisionResponse. Strict `json_schema` mode
    /// (see `OpenAIResponseFormat.visionResponse`) guarantees `content` is
    /// schema-valid JSON with no markdown fences, so no cleanup is needed.
    private func parseOpenAIResponse(_ data: Data) throws -> ScanResult {
        let openAI = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let jsonString = openAI.choices.first?.message.content,
              let jsonData = jsonString.data(using: .utf8) else {
            throw AIProxyError.scanFailed
        }
        return ScanResult(
            response: try JSONDecoder().decode(VisionResponse.self, from: jsonData).sanitized(),
            rawJSON: jsonString
        )
    }
}

private func mappedHTTPError(statusCode: Int) -> AIProxyError? {
    switch statusCode {
    case 200..<300: return nil
    case 429: return .rateLimited
    case 500..<600: return .serverError
    default: return .scanFailed
    }
}

private func mappedProxyError(statusCode: Int, data: Data) -> AIProxyError? {
    guard !(200..<300).contains(statusCode) else { return nil }

    if let proxyError = try? JSONDecoder().decode(ProxyErrorResponse.self, from: data) {
        switch proxyError.error {
        case "rate_limited": return .rateLimited
        case "daily_limit_reached":
            let pool = FreeScanPool(rawValue: proxyError.limitType ?? "text") ?? .text
            return .dailyLimitReached(limitType: pool)
        case "upstream_error": return .serverError
        case "invalid_request": return .scanFailed
        default: break
        }
    }

    return mappedHTTPError(statusCode: statusCode)
}

private func mappedNetworkError(_ error: Error) -> AIProxyError {
    guard let urlError = error as? URLError else { return .scanFailed }
    switch urlError.code {
    case .notConnectedToInternet, .timedOut:
        return .offline
    default:
        return .scanFailed
    }
}

// MARK: - AI Prompts

private func commonPromptContract(locale: String) -> String {
    """
    USER LOCALE: \(locale). Use this locale only to interpret number and portion
    wording. Turkish output rules below always take precedence.

    RESPONSE CONTRACT:
    Return one JSON object with "items" (an array) and "no_food_detected" (a
    boolean). Every item must contain: Turkish "name", English "name_en",
    numeric "estimated_grams", "household_unit", numeric
    "household_quantity", "calories", "protein_g", "carbs_g", "fat_g",
    "confidence", and nullable "note". Structured Outputs enforces the shape;
    do not include sample or placeholder values.

    COMMON RULES:
    - "note", if present, MUST be in Turkish.
    - "name" must be lowercase Turkish except proper nouns (e.g. "mercimek çorbası", "İskender").
    - Keep "name" the canonical dish name ONLY — no size, packaging, or brand
      annotations (e.g. "ton balığı", never "ton balığı (80 gramlık kutu)").
      Put that kind of detail in "note" instead. A stray annotation in "name"
      stops it from matching known foods and makes the same dish look like a
      different one every time.
    - calories MUST be consistent with macros: calories ≈ 4·protein_g + 4·carbs_g + 9·fat_g (±15%).
    - Report visible drinks (tea, ayran, cola) as separate items. Report visible bread separately.
    - Use Turkish household units ONLY: "kepçe", "yemek kaşığı", "su bardağı", "çay bardağı", "dilim", "avuç", "kase", "adet".
    - household_quantity must be between 0.25 and 20; estimated_grams between 5 and 2500.
    - Estimate realistic grams for Turkish portions.
    - Be conservative with calorie estimates.
    - Set confidence between 0.0 and 1.0.
    - Return ONLY valid JSON, no markdown, no explanation.
    """
}

/// Prompt for photo-based food analysis. Language-aware: Turkish users get
/// Turkish-cuisine-specialized instructions; English users get a generic
/// international food analyser.
private func visionPrompt(locale: String) -> String {
    let isTurkish = locale.hasPrefix("tr")
    let contract = commonPromptContract(locale: locale)

    if isTurkish {
        return """
        You are a food analysis assistant specialized in Turkish cuisine.

        Analyze this food photo.

        \(contract)

        STEP 1 — SEGMENT BEFORE YOU NAME:
        A Turkish plate is almost always several separate foods placed side by side
        (e.g. a starch, a protein/sauce, a salad or vegetable), not one dish. Look
        at the plate region by region first — do not describe the whole plate with
        one name. Return ONE "items" entry per visually distinct food region.
        Only merge two regions into one item if they are truly a single preparation
        (e.g. a stew already mixed together, a soup).

        STEP 2 — GROUND EACH NAME IN WHAT YOU ACTUALLY SEE, not in what Turkish
        dish it "sounds like":
        - Individual translucent grains you can count, sometimes with orzo/vermicelli
          flecks → "pirinç pilavı" / "şehriyeli pilav", not a dumpling dish.
        - A smooth, whipped, spreadable pale-yellow paste with no distinct pieces
          → "patates püresi" (mashed potato). A sauce or stew spooned on top of it
          is a SEPARATE item (e.g. "kuşbaşı et sote" / "kırmızı soslu et"), not one
          fused invented name.
        - Small (1–2cm) individually foldable dough pieces, each countable, usually
          under a garlic-yogurt sauce → "mantı". Do NOT default to "mantı" just
          because a pale base is topped with a reddish sauce — that pattern also
          matches mashed potato, güveç, or many other dishes. Only use "mantı" when
          you can actually see discrete folded dumpling shapes.
        - Loose mixed leaves (lettuce, arugula, radicchio) → "yeşil salata" /
          "karışık salata", always its own item, never folded into another name.
        - When genuinely unsure of the specific named dish, describe what you see
          generically and accurately (e.g. "kırmızı soslu kuşbaşı et") rather than
          guessing a specific well-known dish name that doesn't match the visual
          evidence.

        STEP 3 — CONFIDENCE reflects how sure you are of the DISH IDENTITY itself,
        not just the portion size. If the identity is uncertain, say so honestly
        with a lower confidence and use "note" to flag the ambiguity — do not
        compensate for uncertainty by picking a more "recognizable" dish name.

        If no food is visible, set no_food_detected: true and items: [].
        """
    } else {
        return """
        You are a food analysis assistant.

        Analyze this food photo.

        \(contract)

        STEP 1 — SEGMENT BEFORE YOU NAME:
        A plate may contain several separate foods placed side by side
        (e.g. a starch, a protein, a vegetable), not one dish. Look
        at the plate region by region first. Return ONE "items" entry
        per visually distinct food region. Only merge two regions into one item
        if they are truly a single preparation (e.g. a stew already mixed together).

        STEP 2 — NAME WHAT YOU ACTUALLY SEE:
        Use standard English food names. When uncertain, describe generically
        (e.g. "grilled chicken with sauce") rather than guessing a specific dish.
        - Loose mixed leaves → "green salad" / "mixed salad", always its own item.

        STEP 3 — CONFIDENCE reflects how sure you are of the DISH IDENTITY itself,
        not just the portion size. If the identity is uncertain, say so honestly
        with a lower confidence and use "note" to flag the ambiguity.

        If no food is visible, set no_food_detected: true and items: [].
        """
    }
}

/// Prompt for text-based meal logging. Language-aware.
private func textPrompt(description: String, locale: String) -> String {
    let isTurkish = locale.hasPrefix("tr")
    let contract = commonPromptContract(locale: locale)

    if isTurkish {
        return """
        You are a food analysis assistant specialized in Turkish cuisine.

        The user typed this meal description: "\(description)"

        Parse the description into food items.

        \(contract)

        IMPORTANT RULES:
        - Extract quantity and unit from the description (e.g. "2 kepçe mercimek" → household_quantity: 2, household_unit: "kepçe")
        - If you can't parse anything meaningful, set no_food_detected: true and items: [].
        """
    } else {
        return """
        You are a food analysis assistant.

        The user typed this meal description: "\(description)"

        Parse the description into food items.

        \(contract)

        IMPORTANT RULES:
        - Extract quantity and unit from the description (e.g. "2 cups rice" → household_quantity: 2, household_unit: "cup")
        - If you can't parse anything meaningful, set no_food_detected: true and items: [].
        """
    }
}

// MARK: - Upload downscaling

enum ImageDownscaler {
    static let maxDimension: CGFloat = 1280
    static let jpegQuality: CGFloat = 0.7

    static func jpegForUpload(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension else {
            return image.jpegData(compressionQuality: jpegQuality)
        }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: image.size.width * scale,
                             height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }
}

// MARK: - Demo data (DEBUG fallback)

enum DemoVisionData {
    private static let latency: UInt64 = 1_400_000_000

    private static let sampleMeals: [[VisionItem]] = [
        [
            VisionItem(name: "Mercimek çorbası", nameEn: "Lentil soup", estimatedGrams: 250,
                       householdUnit: "kepçe", householdQuantity: 2, calories: 185,
                       proteinG: 11, carbsG: 27, fatG: 4, confidence: 0.92, note: nil),
            VisionItem(name: "Ekmek", nameEn: "Bread", estimatedGrams: 50,
                       householdUnit: "dilim", householdQuantity: 2, calories: 132,
                       proteinG: 4, carbsG: 26, fatG: 1, confidence: 0.88, note: nil),
        ],
        [
            VisionItem(name: "Kuru fasulye", nameEn: "White bean stew", estimatedGrams: 300,
                       householdUnit: "kepçe", householdQuantity: 2, calories: 342,
                       proteinG: 19, carbsG: 45, fatG: 10, confidence: 0.85,
                       note: "Tencere yemeği — porsiyon tahmini"),
            VisionItem(name: "Pirinç pilavı", nameEn: "Rice pilaf", estimatedGrams: 180,
                       householdUnit: "kase", householdQuantity: 1, calories: 258,
                       proteinG: 5, carbsG: 48, fatG: 5, confidence: 0.9, note: nil),
            VisionItem(name: "Ayran", nameEn: "Ayran", estimatedGrams: 200,
                       householdUnit: "su bardağı", householdQuantity: 1, calories: 76,
                       proteinG: 4, carbsG: 6, fatG: 4, confidence: 0.95, note: nil),
        ],
        [
            VisionItem(name: "Menemen", nameEn: "Menemen", estimatedGrams: 220,
                       householdUnit: "kase", householdQuantity: 1, calories: 265,
                       proteinG: 13, carbsG: 9, fatG: 19, confidence: 0.87, note: nil),
            VisionItem(name: "Beyaz peynir", nameEn: "White cheese", estimatedGrams: 40,
                       householdUnit: "dilim", householdQuantity: 2, calories: 106,
                       proteinG: 7, carbsG: 1, fatG: 8, confidence: 0.8, note: nil),
            VisionItem(name: "Çay", nameEn: "Black tea", estimatedGrams: 100,
                       householdUnit: "çay bardağı", householdQuantity: 1, calories: 2,
                       proteinG: 0, carbsG: 0, fatG: 0, confidence: 0.97, note: nil),
        ],
    ]

    static func photoResponse() async throws -> VisionResponse {
        try? await Task.sleep(nanoseconds: latency)
        let items = sampleMeals.randomElement() ?? sampleMeals[0]
        return VisionResponse(items: items, noFoodDetected: false)
    }

    static func textResponse(for description: String) async throws -> VisionResponse {
        try? await Task.sleep(nanoseconds: latency)
        let segments = description
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else {
            return VisionResponse(items: [], noFoodDetected: true)
        }
        return VisionResponse(items: segments.map(demoItem(from:)), noFoodDetected: false)
    }

    private static func demoItem(from segment: String) -> VisionItem {
        var quantity: Double = 1
        var unit = "adet"
        var name = segment

        let words = segment.split(separator: " ").map(String.init)
        if let first = words.first,
           let parsed = Double(first.replacingOccurrences(of: ",", with: ".")) {
            quantity = parsed
            name = words.dropFirst().joined(separator: " ")
            let unitWords = ["kepçe", "dilim", "kase", "avuç", "adet",
                             "su bardağı", "çay bardağı", "yemek kaşığı", "bardak"]
            for candidate in unitWords where name.lowercased().hasPrefix(candidate) {
                unit = candidate == "bardak" ? "su bardağı" : candidate
                name = String(name.dropFirst(candidate.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        if name.isEmpty { name = segment }
        let calories = Double.random(in: 60...320).rounded()
        return VisionItem(
            name: name.prefix(1).capitalized + name.dropFirst(),
            nameEn: name,
            estimatedGrams: (quantity * 120).rounded(),
            householdUnit: unit,
            householdQuantity: quantity,
            calories: calories,
            proteinG: (calories * 0.12 / 4).rounded(),
            carbsG: (calories * 0.5 / 4).rounded(),
            fatG: (calories * 0.3 / 9).rounded(),
            confidence: 0.9,
            note: nil
        )
    }
}
