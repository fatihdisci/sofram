//
//  AIProxyClient.swift
//  Sofra — networking client for the AI vision proxy.
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

import Foundation
import UIKit

// MARK: - Errors

enum AIProxyError: LocalizedError {
    case invalidConfiguration
    case notConfigured
    case scanFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Yapılandırma hatası."
        case .notConfigured:
            return "AI sunucusu henüz bağlanmadı. Bu bir uygulama hatası değil — sunucu adresi yapılandırılınca tarama çalışacak."
        case .scanFailed:
            return "Tarama başarısız oldu, lütfen tekrar deneyin."
        }
    }
}

// MARK: - Proxy request body

struct AIProxyRequest: Encodable {
    let imageBase64: String?
    let text: String?
    let mode: String
    let locale: String
    let tier: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case text, mode, locale, tier
    }

    static func photo(imageData: Data, locale: String, tier: String) -> AIProxyRequest {
        AIProxyRequest(imageBase64: imageData.base64EncodedString(), text: nil, mode: "photo", locale: locale, tier: tier)
    }

    static func text(description: String, locale: String, tier: String) -> AIProxyRequest {
        AIProxyRequest(imageBase64: nil, text: description, mode: "text", locale: locale, tier: tier)
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

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
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

// MARK: - Client

final class AIProxyClient {

    struct Configuration {
        var endpointURL: URL
        var apiKey: String?
        var timeout: TimeInterval

        /// OpenAI API key from Secrets.plist (gitignored). Nil if not set up.
        var openAIKey: String? {
            guard let secretsURL = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
                  let secrets = NSDictionary(contentsOf: secretsURL),
                  let key = secrets["OpenAIAPIKey"] as? String,
                  !key.isEmpty
            else { return nil }
            return key
        }

        /// OpenAI organization ID from Secrets.plist (optional — project-scoped keys may need it).
        var openAIOrgID: String? {
            guard let secretsURL = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
                  let secrets = NSDictionary(contentsOf: secretsURL),
                  let orgID = secrets["OpenAIOrgID"] as? String,
                  !orgID.isEmpty
            else { return nil }
            return orgID
        }

        static let placeholderEndpoint = URL(string: "https://REPLACE-ME.vercel.app/api/scan")!

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

    func scan(imageData: Data) async throws -> VisionResponse {
        if isDemoMode { return try await DemoVisionData.photoResponse() }
        let tier = await FreeScanCounter.shared.isSubscribed ? "pro" : "free"

        // 1. Try Vercel proxy (production)
        if isConfigured {
            let payload = ImageDownscaler.jpegForUpload(imageData) ?? imageData
            let body = AIProxyRequest.photo(imageData: payload, locale: Locale.current.identifier, tier: tier)
            return try await performProxyRequest(body: body)
        }

        // 2. Try direct OpenAI (dev/testing)
        if canUseDirectOpenAI {
            return try await callOpenAIVision(imageData: imageData, tier: tier)
        }

        throw AIProxyError.notConfigured
    }

    func scanText(_ description: String) async throws -> VisionResponse {
        if isDemoMode { return try await DemoVisionData.textResponse(for: description) }
        let tier = await FreeScanCounter.shared.isSubscribed ? "pro" : "free"

        if isConfigured {
            let body = AIProxyRequest.text(description: description, locale: Locale.current.identifier, tier: tier)
            return try await performProxyRequest(body: body)
        }

        if canUseDirectOpenAI {
            return try await callOpenAIText(description: description, tier: tier)
        }

        throw AIProxyError.notConfigured
    }

    // MARK: - Vercel proxy

    private func performProxyRequest(body: AIProxyRequest) async throws -> VisionResponse {
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = configuration.apiKey {
            request.setValue(key, forHTTPHeaderField: "x-sofra-key")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AIProxyError.scanFailed
        }
        return try JSONDecoder().decode(VisionResponse.self, from: data)
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
    private func callOpenAIVision(imageData: Data, tier: String) async throws -> VisionResponse {
        let model = openAIModel(for: tier)
        let base64 = imageData.base64EncodedString()
        let prompt = visionPrompt(locale: Locale.current.identifier)

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
            reasoningEffort: "low"
        )

        return try await performOpenAIRequest(body: body, model: model, tier: tier)
    }

    /// Text → OpenAI Chat Completions.
    private func callOpenAIText(description: String, tier: String) async throws -> VisionResponse {
        let model = openAIModel(for: tier)
        let prompt = textPrompt(description: description, locale: Locale.current.identifier)

        let body = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "user", content: [.text(prompt)])
            ],
            maxCompletionTokens: 2048,
            reasoningEffort: "minimal"
        )

        return try await performOpenAIRequest(body: body, model: model, tier: tier)
    }

    /// Shared: POST to OpenAI, parse JSON response into VisionResponse.
    private func performOpenAIRequest(body: OpenAIRequest, model: String, tier: String) async throws -> VisionResponse {
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
                    reasoningEffort: body.reasoningEffort
                )
                var fallbackRequest = URLRequest(url: openAIURL())
                fallbackRequest.httpMethod = "POST"
                fallbackRequest.timeoutInterval = configuration.timeout
                for (key, value) in openAIHeaders() {
                    fallbackRequest.setValue(value, forHTTPHeaderField: key)
                }
                fallbackRequest.httpBody = try JSONEncoder().encode(fallbackBody)
                let (fallbackData, fallbackResponse) = try await session.data(for: fallbackRequest)
                guard let fallbackHTTP = fallbackResponse as? HTTPURLResponse,
                      (200..<300).contains(fallbackHTTP.statusCode) else {
                    let fb = String(data: fallbackData, encoding: .utf8) ?? "<no body>"
                    print("[AIProxyClient] Fallback also failed: \(fb)")
                    throw AIProxyError.scanFailed
                }
                return try parseOpenAIResponse(fallbackData)
            }

            guard (200..<300).contains(http.statusCode) else {
                throw AIProxyError.scanFailed
            }
            return try parseOpenAIResponse(data)
        } catch let error as AIProxyError { throw error }
        catch {
            print("[AIProxyClient] Unexpected error: \(error.localizedDescription)")
            throw AIProxyError.scanFailed
        }
    }

    /// Parse OpenAI JSON response → VisionResponse, with retry for malformed JSON.
    private func parseOpenAIResponse(_ data: Data) throws -> VisionResponse {
        let openAI = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let jsonString = openAI.choices.first?.message.content else {
            throw AIProxyError.scanFailed
        }
        // OpenAI may wrap JSON in ```json fences
        let cleaned = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8) else { throw AIProxyError.scanFailed }
        return try JSONDecoder().decode(VisionResponse.self, from: jsonData)
    }
}

// MARK: - AI Prompts

/// Prompt for photo-based food analysis. Must match VisionResponse JSON schema exactly.
private func visionPrompt(locale: String) -> String {
    """
    You are a food analysis assistant specialized in Turkish cuisine.

    Analyze this food photo and return a JSON object with this exact structure:
    {
      "items": [
        {
          "name": "Turkish dish name",
          "name_en": "English dish name",
          "estimated_grams": 250.0,
          "household_unit": "kepçe",
          "household_quantity": 2.0,
          "calories": 185.0,
          "protein_g": 11.0,
          "carbs_g": 27.0,
          "fat_g": 4.0,
          "confidence": 0.92,
          "note": null
        }
      ],
      "no_food_detected": false
    }

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

    OTHER RULES:
    - Use Turkish household units ONLY: "kepçe" (ladle), "yemek kaşığı" (tbsp), "su bardağı" (glass, ~200ml), "çay bardağı" (tea glass, ~100ml), "dilim" (slice), "avuç" (handful), "kase" (bowl), "adet" (piece)
    - Estimate realistic grams for Turkish portions
    - Be conservative with calorie estimates
    - Set confidence between 0.0 and 1.0
    - If no food is visible, set no_food_detected: true and items: []
    - Return ONLY valid JSON, no markdown, no explanation
    """
}

/// Prompt for text-based meal logging.
private func textPrompt(description: String, locale: String) -> String {
    """
    You are a food analysis assistant specialized in Turkish cuisine.

    The user typed this meal description: "\(description)"

    Parse it and return a JSON object with this exact structure:
    {
      "items": [
        {
          "name": "Turkish dish name",
          "name_en": "English dish name",
          "estimated_grams": 250.0,
          "household_unit": "kepçe",
          "household_quantity": 2.0,
          "calories": 185.0,
          "protein_g": 11.0,
          "carbs_g": 27.0,
          "fat_g": 4.0,
          "confidence": 0.85,
          "note": null
        }
      ],
      "no_food_detected": false
    }

    IMPORTANT RULES:
    - Extract quantity and unit from the description (e.g. "2 kepçe mercimek" → household_quantity: 2, household_unit: "kepçe")
    - Use Turkish household units ONLY: "kepçe", "yemek kaşığı", "su bardağı", "çay bardağı", "dilim", "avuç", "kase", "adet"
    - Estimate realistic grams for Turkish portions
    - Be conservative with calorie estimates
    - If you can't parse anything meaningful, set no_food_detected: true and items: []
    - Return ONLY valid JSON, no markdown, no explanation
    """
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
