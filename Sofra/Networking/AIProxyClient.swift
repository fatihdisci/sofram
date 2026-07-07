//
//  AIProxyClient.swift
//  Sofra — networking client for the AI vision proxy.
//
//  MODEL-AGNOSTIC BY DESIGN. This client POSTs an image to a configurable endpoint
//  and gets back the typed `VisionResponse`. It never names a model. The endpoint is
//  a black box (a Vercel Edge Function). On the backend — out of scope here — the
//  proxy runs a tier-based model chain (see MODEL_RESEARCH.md):
//
//    free tier: Gemini 2.5 Flash-Lite only (no fallback)
//    pro tier:  Gemini 2.5 Flash-Lite → GPT-4.1 mini (auto-fallback on error/refusal)
//
//  The tier is determined by StoreKit 2 subscription status and sent as a `tier`
//  field in the request body. The proxy caches by image hash via Upstash.
//  The client only ever sees a valid response or a generic failure, so the backend
//  can swap models with zero client changes.
//
//  Transport: JSON body with a base64-encoded JPEG (documented in PHASE_1_NOTES.md).
//

import Foundation
import UIKit

enum AIProxyError: LocalizedError {
    /// Endpoint URL missing/malformed in configuration.
    case invalidConfiguration
    /// The endpoint is still the REPLACE-ME placeholder — the proxy was never
    /// deployed/configured. Surfaced distinctly so it can't be mistaken for a
    /// camera or transient network problem.
    case notConfigured
    /// Anything the user should just retry: transport error, non-2xx, or unparseable body.
    /// Deliberately generic — the client does not distinguish which model failed.
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
    /// Model tier: "free" (Gemini 2.5 Flash-Lite only) or "pro" (Flash-Lite + GPT-4.1 mini fallback).
    /// Determined by StoreKit subscription status at request time.
    let tier: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case text
        case mode
        case locale
        case tier
    }

    /// Photo-scan request.
    static func photo(imageData: Data, locale: String, tier: String) -> AIProxyRequest {
        AIProxyRequest(
            imageBase64: imageData.base64EncodedString(),
            text: nil,
            mode: "photo",
            locale: locale,
            tier: tier
        )
    }

    /// Text-scan request.
    static func text(description: String, locale: String, tier: String) -> AIProxyRequest {
        AIProxyRequest(
            imageBase64: nil,
            text: description,
            mode: "text",
            locale: locale,
            tier: tier
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

    /// False while the endpoint is still the REPLACE-ME placeholder.
    var isConfigured: Bool {
        configuration.endpointURL.host()?.contains("REPLACE-ME") != true
    }

    /// Debug builds answer scans with local demo data while the proxy is not
    /// yet deployed, so the full capture → analysis → log flow stays testable.
    /// Release builds never fake results — they surface `.notConfigured`.
    var isDemoMode: Bool {
        #if DEBUG
        return !isConfigured
        #else
        return false
        #endif
    }

    /// Sends an image to the proxy and returns the typed result.
    /// Throws `AIProxyError.scanFailed` for any failure the user should retry.
    func scan(imageData: Data) async throws -> VisionResponse {
        if isDemoMode { return try await DemoVisionData.photoResponse() }
        guard isConfigured else { throw AIProxyError.notConfigured }
        let payload = ImageDownscaler.jpegForUpload(imageData) ?? imageData
        let tier = await FreeScanCounter.shared.isSubscribed ? "pro" : "free"
        let body = AIProxyRequest.photo(imageData: payload, locale: Locale.current.identifier, tier: tier)
        return try await performRequest(body: body)
    }

    /// Sends free-text description to the proxy and returns the typed result.
    func scanText(_ description: String) async throws -> VisionResponse {
        if isDemoMode { return try await DemoVisionData.textResponse(for: description) }
        guard isConfigured else { throw AIProxyError.notConfigured }
        let tier = await FreeScanCounter.shared.isSubscribed ? "pro" : "free"
        let body = AIProxyRequest.text(description: description, locale: Locale.current.identifier, tier: tier)
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

// MARK: - Upload downscaling

/// Full-resolution captures are ~5–10 MB; base64 inflates them another 33%.
/// The vision models don't need more than ~1280px on the long edge, so uploads
/// are resized + recompressed (typically to a few hundred KB) before encoding.
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

// MARK: - Demo data (DEBUG-only, used while the proxy endpoint is unconfigured)

enum DemoVisionData {

    /// Simulated network+inference latency so the analysis animation is exercised.
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

    /// Builds one plausible item per comma-separated segment of the typed text,
    /// with a light "2 kepçe mercimek" style quantity+unit parse.
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
